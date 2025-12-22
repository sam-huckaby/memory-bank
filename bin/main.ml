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

(** Handle GET /api/photos - List photos with pagination *)
let handle_list_photos state request =
  (* Parse query parameters with defaults *)
  let page_str = Dream.query request "page" |> Option.value ~default:"1" in
  let limit_str = Dream.query request "limit" |> Option.value ~default:"50" in
  let order = Dream.query request "order" |> Option.value ~default:"desc" in
  let sort_by = Dream.query request "sort_by" |> Option.value ~default:"date_taken" in
  
  (* Parse and validate page number *)
  let page = try
    let p = int_of_string page_str in
    if p < 1 then 1 else p
  with _ -> 1
  in
  
  (* Parse and validate limit *)
  let limit = try
    let l = int_of_string limit_str in
    if l < 1 then 50
    else if l > 100 then 100
    else l
  with _ -> 50
  in
  
  (* Validate order parameter *)
  let validated_order = match order with
    | "asc" | "desc" -> order
    | _ -> "desc"
  in
  
  (* Validate sort_by parameter *)
  let validated_sort_by = match sort_by with
    | "date_taken" | "created_at" -> sort_by
    | _ -> "date_taken"
  in
  
  (* Query database with pagination *)
  let* (photos, total) = Database.get_photos_paginated 
    state.db 
    ~page 
    ~limit 
    ~order:validated_order 
    ~sort_by:validated_sort_by 
  in
  
  (* Calculate pagination metadata *)
  let total_pages = if total = 0 then 0 else (total + limit - 1) / limit in
  let has_next = page < total_pages in
  let has_prev = page > 1 in
  
  (* Build response JSON *)
  let photos_json = Models.list_to_json photos in
  let pagination_json = `Assoc [
    ("page", `Int page);
    ("limit", `Int limit);
    ("total", `Int total);
    ("total_pages", `Int total_pages);
    ("has_next", `Bool has_next);
    ("has_prev", `Bool has_prev);
  ] in
  let response_json = `Assoc [
    ("photos", photos_json);
    ("pagination", pagination_json);
  ] in
  let response_str = Yojson.Safe.to_string response_json in
  Dream.json response_str

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
            deleted_at = None;
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

(** Handle DELETE /api/photos/:id - Soft delete with transaction safety *)
let handle_delete_photo state request =
  let id = Dream.param request "id" in
  
  (* Verify photo exists and is not already deleted *)
  let* photo_opt = Database.get_photo_by_id state.db id in
  match photo_opt with
  | None ->
      (* Either doesn't exist or already soft-deleted *)
      Dream.json ~status:`Not_Found 
        (Printf.sprintf {|{"error": "Photo not found or already deleted", "id": "%s"}|} id)
  | Some photo ->
      (* Transaction-safe soft delete *)
      Lwt.catch
        (fun () ->
          (* Step 1: Move file to backup location *)
          let* backup_result = Storage.backup_photo_for_delete
            ~storage_path:state.config.photo_storage_path
            ~id in
          
          match backup_result with
          | Error msg ->
              Logging.log ERROR "photo_delete" 
                (Printf.sprintf "Failed to backup photo: %s" msg)
                (`Assoc [("photo_id", `String id); ("error", `String msg)]);
              Dream.json ~status:`Internal_Server_Error
                (Printf.sprintf {|{"error": "%s", "id": "%s"}|} msg id)
          | Ok backup_path ->
              (* Step 2: Soft delete in database within transaction *)
              Lwt.catch
                (fun () ->
                  let* deleted_at = Database.with_transaction state.db (fun () ->
                    Database.soft_delete_photo state.db id
                  ) in
                  
                  (* Step 3: Transaction committed successfully - move to deleted dir *)
                  let* () = Storage.move_to_deleted 
                    ~backup_path 
                    ~storage_path:state.config.photo_storage_path 
                    ~id in
                  
                  (* Step 4: Log structured deletion event *)
                  Logging.log_photo_deleted 
                    ~id 
                    ~original_filename:photo.original_filename 
                    ~deleted_at;
                  
                  (* Return simple success response *)
                  Dream.json ~status:`OK 
                    {|{"message": "Photo deleted successfully"}|})
                (fun exn ->
                  (* Database operation failed - restore the file *)
                  Logging.log ERROR "photo_delete" 
                    "Database soft delete failed, restoring file"
                    (`Assoc [
                      ("photo_id", `String id); 
                      ("error", `String (Printexc.to_string exn))
                    ]);
                  
                  let* () = Storage.restore_photo 
                    ~backup_path 
                    ~storage_path:state.config.photo_storage_path 
                    ~id in
                  
                  Dream.json ~status:`Internal_Server_Error
                    {|{"error": "Failed to delete photo"}|}))
        (fun exn ->
          (* Top-level error handler *)
          Logging.log ERROR "photo_delete" 
            "Delete operation failed"
            (`Assoc [
              ("photo_id", `String id); 
              ("error", `String (Printexc.to_string exn))
            ]);
          Dream.json ~status:`Internal_Server_Error
            {|{"error": "Internal server error"}|})

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
          ("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
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
      Dream.add_header response "Access-Control-Allow-Methods" "GET, POST, DELETE, OPTIONS";
      Dream.add_header response "Access-Control-Allow-Headers" "Content-Type";
      Lwt.return response
    else
      Lwt.return response

(** Setup routes *)
let routes state = [
  Dream.get "/api/playlist" (handle_playlist state);
  Dream.get "/api/photos" (handle_list_photos state);
  Dream.get "/api/photos/:id" (handle_get_photo state);
  Dream.get "/api/photos/:id/metadata" (handle_get_metadata state);
  Dream.post "/api/photos" (handle_upload_photo state);
  Dream.delete "/api/photos/:id" (handle_delete_photo state);
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
  
  let db = Lwt_main.run (Database.init config.database_path config.migrations_dir) in
  let state = { db; config } in
  
  Printf.printf "[INFO] Server starting on http://%s:%d\n" config.interface config.port;
  Printf.printf "[INFO] Routes available:\n";
  Printf.printf "  GET    /api/playlist\n";
  Printf.printf "  GET    /api/photos (paginated list)\n";
  Printf.printf "  GET    /api/photos/:id\n";
  Printf.printf "  GET    /api/photos/:id/metadata\n";
  Printf.printf "  POST   /api/photos\n";
  Printf.printf "  DELETE /api/photos/:id\n";
  Printf.printf "[INFO] Ready to serve photos!\n";
  flush stdout;
  
  Dream.run ~interface:config.interface ~port:config.port
  @@ Dream.logger
  @@ cors_middleware config.cors_allowed_origins
  @@ Dream.memory_sessions
  @@ Dream.router (routes state)
