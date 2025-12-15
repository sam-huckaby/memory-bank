(** Database handle type *)
type db = Sqlite3.db

(** Initialize database and create schema *)
let init database_path =
  let db = Sqlite3.db_open database_path in
  
  (* Create photos table *)
  let schema = {|
    CREATE TABLE IF NOT EXISTS photos (
      id TEXT PRIMARY KEY,
      original_filename TEXT NOT NULL,
      date_taken TEXT NOT NULL,
      file_size INTEGER NOT NULL,
      width INTEGER,
      height INTEGER,
      mime_type TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    
    CREATE INDEX IF NOT EXISTS idx_date_taken ON photos(date_taken);
  |} in
  
  let rc = Sqlite3.exec db schema in
  match rc with
  | Sqlite3.Rc.OK ->
      Printf.printf "[INFO] Database initialized successfully\n";
      flush stdout;
      Lwt.return db
  | _ ->
      let err = Sqlite3.errmsg db in
      failwith (Printf.sprintf "Failed to initialize database: %s" err)

(** Insert a photo record into the database *)
let insert_photo db (photo : Models.photo) =
  let stmt = Sqlite3.prepare db
    "INSERT INTO photos (id, original_filename, date_taken, file_size, width, height, mime_type, created_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)" in
  
  let bind_width = match photo.width with
    | Some w -> Sqlite3.Data.INT (Int64.of_int w)
    | None -> Sqlite3.Data.NULL
  in
  
  let bind_height = match photo.height with
    | Some h -> Sqlite3.Data.INT (Int64.of_int h)
    | None -> Sqlite3.Data.NULL
  in
  
  let params = [
    Sqlite3.Data.TEXT photo.id;
    Sqlite3.Data.TEXT photo.original_filename;
    Sqlite3.Data.TEXT photo.date_taken;
    Sqlite3.Data.INT (Int64.of_int photo.file_size);
    bind_width;
    bind_height;
    Sqlite3.Data.TEXT photo.mime_type;
    Sqlite3.Data.TEXT photo.created_at;
  ] in
  
  let rc = Sqlite3.bind_values stmt params in
  match rc with
  | Sqlite3.Rc.OK ->
      let step_rc = Sqlite3.step stmt in
      let _ = Sqlite3.finalize stmt in
      (match step_rc with
       | Sqlite3.Rc.DONE -> Lwt.return_unit
       | _ -> 
           let err = Sqlite3.errmsg db in
           Lwt.fail_with (Printf.sprintf "Failed to insert photo: %s" err))
  | _ ->
      let err = Sqlite3.errmsg db in
      let _ = Sqlite3.finalize stmt in
      Lwt.fail_with (Printf.sprintf "Failed to bind parameters: %s" err)

(** Get photo by ID *)
let get_photo_by_id db id =
  let stmt = Sqlite3.prepare db
    "SELECT id, original_filename, date_taken, file_size, width, height, mime_type, created_at 
     FROM photos WHERE id = ?" in
  
  let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT id) in
  
  let result = ref None in
  let callback row =
    result := Models.of_sql_row row
  in
  
  let rec step () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        callback row;
        step ()
    | Sqlite3.Rc.DONE ->
        let _ = Sqlite3.finalize stmt in
        Lwt.return !result
    | _ ->
        let err = Sqlite3.errmsg db in
        let _ = Sqlite3.finalize stmt in
        Lwt.fail_with (Printf.sprintf "Query failed: %s" err)
  in
  step ()

(** Get random playlist of photos (up to 1000) *)
let get_random_playlist db =
  let stmt = Sqlite3.prepare db
    "SELECT id, original_filename, date_taken, file_size, width, height, mime_type, created_at 
     FROM photos ORDER BY RANDOM() LIMIT 1000" in
  
  let results = ref [] in
  let callback row =
    match Models.of_sql_row row with
    | Some photo -> results := photo :: !results
    | None -> ()
  in
  
  let rec step () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        callback row;
        step ()
    | Sqlite3.Rc.DONE ->
        let _ = Sqlite3.finalize stmt in
        Lwt.return (List.rev !results)
    | _ ->
        let err = Sqlite3.errmsg db in
        let _ = Sqlite3.finalize stmt in
        Lwt.fail_with (Printf.sprintf "Query failed: %s" err)
  in
  step ()

(** Close database connection *)
let close db =
  let _ = Sqlite3.db_close db in
  Lwt.return_unit
