open Lwt.Syntax
open Memory_bank

(** State to hold database and config *)
type state = {
  db : Database.db;
  config : Config.t;
}

(** Handle GET /api/playlist - Return random playlist *)
let handle_playlist state _request =
  let* photos = Playlist.get state.db in
  let json = Models.list_to_json photos in
  let json_str = Yojson.Safe.to_string json in
  Dream.json json_str

(** Handle GET /api/photos/:id - Serve photo file *)
let handle_get_photo state request =
  let id = Dream.param request "id" in
  let* photo_opt = Database.get_photo_by_id state.db id in
  match photo_opt with
  | None ->
      Dream.json ~status:`Not_Found {|{"error": "Photo not found"}|}
  | Some photo ->
      let* content_result = Storage.read_photo 
        ~storage_path:state.config.photo_storage_path 
        ~id in
      match content_result with
      | Error msg ->
          Dream.json ~status:`Not_Found 
            (Printf.sprintf {|{"error": "%s"}|} msg)
      | Ok content ->
          Dream.respond ~headers:[("Content-Type", photo.mime_type)] content

(** Handle GET /api/photos/:id/metadata - Return photo metadata *)
let handle_get_metadata state request =
  let id = Dream.param request "id" in
  let* photo_opt = Database.get_photo_by_id state.db id in
  match photo_opt with
  | None ->
      Dream.json ~status:`Not_Found {|{"error": "Photo not found"}|}
  | Some photo ->
      let json = Models.to_json photo in
      let json_str = Yojson.Safe.to_string json in
      Dream.json json_str

(** Handle POST /api/photos - Upload new photo *)
let handle_upload_photo state request =
  let* parts = Dream.multipart ~csrf:false request in
  match parts with
  | `Ok parts -> (
      (* Find the photo field - Dream.multipart returns (filename option * content) for files *)
      let rec find_photo = function
        | [] -> None
        | (name, uploads) :: rest ->
            if name = "photo" then
              (* uploads is a list of (filename option * content) *)
              match uploads with
              | (filename_opt, content) :: _ -> Some (filename_opt, content)
              | [] -> find_photo rest
            else find_photo rest
      in
      
      match find_photo parts with
      | None ->
          Dream.json ~status:`Bad_Request {|{"error": "No photo field found"}|}
      | Some (filename_opt, content) ->
          (* Generate ID and timestamps *)
          let id = Storage.generate_id () in
          let created_at = Metadata.get_current_timestamp () in
          let filename = Option.value filename_opt ~default:"unknown" in
          
          (* Save file temporarily to extract metadata *)
          let temp_path = Filename.temp_file "upload" "" in
          let oc = open_out_bin temp_path in
          output_string oc content;
          close_out oc;
          
          (* Extract metadata *)
          let mime_type = Metadata.detect_mime_type filename content in
          let file_size = Storage.get_file_size temp_path in
          let dimensions = Metadata.extract_dimensions temp_path in
          let date_taken = Metadata.extract_date_taken temp_path created_at in
          
          let (width, height) = match dimensions with
            | Some (w, h) -> (Some w, Some h)
            | None -> (None, None)
          in
          
          (* Create photo record *)
          let photo : Models.photo = {
            id;
            original_filename = filename;
            date_taken;
            file_size;
            width;
            height;
            mime_type;
            created_at;
          } in
          
          (* Save to permanent storage *)
          let* () = Storage.save_photo 
            ~storage_path:state.config.photo_storage_path 
            ~id 
            ~content in
          
          (* Insert into database *)
          let* () = Database.insert_photo state.db photo in
          
          (* Clean up temp file *)
          Sys.remove temp_path;
          
          (* Return created photo metadata *)
          let json = Models.to_json photo in
          let json_str = Yojson.Safe.to_string json in
          Dream.json ~status:`Created json_str)
  | _ ->
      Dream.json ~status:`Bad_Request {|{"error": "Invalid multipart form data"}|}

(** CORS middleware to handle cross-origin requests *)
let cors_middleware allowed_origins handler request =
  (* Check if this is a preflight OPTIONS request *)
  if Dream.method_ request = `OPTIONS then
    (* Handle preflight request *)
    let origin = Dream.header request "Origin" in
    let should_allow = match origin with
      | None -> false
      | Some origin_val ->
          List.mem "*" allowed_origins || List.mem origin_val allowed_origins
    in
    if should_allow then
      let origin_header = match origin with
        | Some o when not (List.mem "*" allowed_origins) -> o
        | _ -> "*"
      in
      Dream.respond ~status:`No_Content
        ~headers:[
          ("Access-Control-Allow-Origin", origin_header);
          ("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
          ("Access-Control-Allow-Headers", "Content-Type");
          ("Access-Control-Max-Age", "86400");
        ]
        ""
    else
      Dream.respond ~status:`No_Content ""
  else
    (* Regular request - add CORS headers to response *)
    let* response = handler request in
    let origin = Dream.header request "Origin" in
    let should_allow = match origin with
      | None -> false
      | Some origin_val ->
          List.mem "*" allowed_origins || List.mem origin_val allowed_origins
    in
    if should_allow then
      let origin_header = match origin with
        | Some o when not (List.mem "*" allowed_origins) -> o
        | _ -> "*"
      in
      Dream.add_header response "Access-Control-Allow-Origin" origin_header;
      Dream.add_header response "Access-Control-Allow-Methods" "GET, POST, OPTIONS";
      Dream.add_header response "Access-Control-Allow-Headers" "Content-Type";
      Lwt.return response
    else
      Lwt.return response

(** Setup routes *)
let routes state = [
  Dream.get "/api/playlist" (handle_playlist state);
  Dream.get "/api/photos/:id" (handle_get_photo state);
  Dream.get "/api/photos/:id/metadata" (handle_get_metadata state);
  Dream.post "/api/photos" (handle_upload_photo state);
]

(** Main entry point *)
let () =
  (* Load config and initialize database before starting server *)
  Printf.printf "[INFO] Loading configuration...\n";
  flush stdout;
  
  let config = Config.load () in
  Config.print config;
  
  Printf.printf "[INFO] Initializing database...\n";
  flush stdout;
  
  let db = Lwt_main.run (Database.init config.database_path) in
  let state = { db; config } in
  
  Printf.printf "[INFO] Server starting on http://localhost:%d\n" config.port;
  Printf.printf "[INFO] Routes available:\n";
  Printf.printf "  GET  /api/playlist\n";
  Printf.printf "  GET  /api/photos/:id\n";
  Printf.printf "  GET  /api/photos/:id/metadata\n";
  Printf.printf "  POST /api/photos\n";
  Printf.printf "[INFO] Ready to serve photos!\n";
  flush stdout;
  
  Dream.run ~port:config.port
  @@ Dream.logger
  @@ cors_middleware config.cors_allowed_origins
  @@ Dream.memory_sessions
  @@ Dream.router (routes state)
