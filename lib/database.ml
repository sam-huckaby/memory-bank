(** Database handle type *)
type db = Sqlite3.db

(** Initialize database and run migrations *)
let init database_path migrations_dir =
  let db = Sqlite3.db_open database_path in
  
  let open Lwt.Syntax in
  
  (* Initialize migration tracking *)
  let* () = Migrations.init_migrations_table db in
  
  (* Run pending migrations *)
  let* () = Migrations.run_pending_migrations db migrations_dir in
  
  Printf.printf "[INFO] Database initialization complete\n";
  flush stdout;
  Lwt.return db

(** Insert a photo record into the database *)
let insert_photo db (photo : Models.photo) =
  let stmt = Sqlite3.prepare db
    "INSERT INTO photos (id, original_filename, date_taken, file_size, width, height, mime_type, created_at, deleted_at) 
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)" in
  
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
    "SELECT id, original_filename, date_taken, file_size, width, height, mime_type, created_at, deleted_at 
     FROM photos WHERE id = ? AND deleted_at IS NULL" in
  
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
    "SELECT id, original_filename, date_taken, file_size, width, height, mime_type, created_at, deleted_at 
     FROM photos WHERE deleted_at IS NULL ORDER BY RANDOM() LIMIT 1000" in
  
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

(** Begin a transaction *)
let begin_transaction db =
  let rc = Sqlite3.exec db "BEGIN IMMEDIATE TRANSACTION" in
  match rc with
  | Sqlite3.Rc.OK -> Lwt.return_unit
  | _ -> 
      let err = Sqlite3.errmsg db in
      Lwt.fail_with (Printf.sprintf "Failed to begin transaction: %s" err)

(** Commit a transaction *)
let commit_transaction db =
  let rc = Sqlite3.exec db "COMMIT" in
  match rc with
  | Sqlite3.Rc.OK -> Lwt.return_unit
  | _ -> 
      let err = Sqlite3.errmsg db in
      Lwt.fail_with (Printf.sprintf "Failed to commit transaction: %s" err)

(** Rollback a transaction *)
let rollback_transaction db =
  let rc = Sqlite3.exec db "ROLLBACK" in
  match rc with
  | Sqlite3.Rc.OK -> Lwt.return_unit
  | _ -> 
      let err = Sqlite3.errmsg db in
      Lwt.fail_with (Printf.sprintf "Failed to rollback transaction: %s" err)

(** Execute a function within a transaction with automatic commit/rollback *)
let with_transaction db f =
  let open Lwt.Syntax in
  Lwt.catch
    (fun () ->
      let* () = begin_transaction db in
      Lwt.catch
        (fun () ->
          let* result = f () in
          let* () = commit_transaction db in
          Lwt.return result)
        (fun exn ->
          let* () = rollback_transaction db in
          Lwt.fail exn))
    (fun exn -> Lwt.fail exn)

(** Soft delete photo by ID - sets deleted_at timestamp *)
let soft_delete_photo db id =
  let deleted_at = 
    (* ISO 8601 format: YYYY-MM-DDTHH:MM:SS.sssZ *)
    let open Unix in
    let tm = gmtime (time ()) in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.000Z"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
      tm.tm_hour tm.tm_min tm.tm_sec
  in
  
  let stmt = Sqlite3.prepare db 
    "UPDATE photos SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL" in
  
  let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT deleted_at) in
  let _ = Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT id) in
  
  let step_rc = Sqlite3.step stmt in
  let changes = Sqlite3.changes db in
  let _ = Sqlite3.finalize stmt in
  
  match step_rc with
  | Sqlite3.Rc.DONE ->
      if changes > 0 then
        Lwt.return deleted_at  (* Return timestamp for logging *)
      else
        Lwt.fail_with "Photo not found or already deleted"
  | _ ->
      let err = Sqlite3.errmsg db in
      Lwt.fail_with (Printf.sprintf "Failed to soft delete photo: %s" err)

(** Get total count of photos *)
let get_photo_count db =
  let stmt = Sqlite3.prepare db "SELECT COUNT(*) FROM photos WHERE deleted_at IS NULL" in
  
  let count = ref 0 in
  let rec step () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        (match row with
         | [| Sqlite3.Data.INT c |] -> count := Int64.to_int c
         | _ -> ());
        step ()
    | Sqlite3.Rc.DONE ->
        let _ = Sqlite3.finalize stmt in
        Lwt.return !count
    | _ ->
        let err = Sqlite3.errmsg db in
        let _ = Sqlite3.finalize stmt in
        Lwt.fail_with (Printf.sprintf "Count query failed: %s" err)
  in
  step ()

(** Get paginated photos with sorting options *)
let get_photos_paginated db ~page ~limit ~order ~sort_by =
  (* Validate sort_by parameter *)
  let sort_field = match sort_by with
    | "date_taken" -> "date_taken"
    | "created_at" -> "created_at"
    | _ -> "date_taken" (* Default fallback *)
  in
  
  (* Validate order parameter *)
  let sort_order = match order with
    | "asc" -> "ASC"
    | "desc" -> "DESC"
    | _ -> "DESC" (* Default fallback *)
  in
  
  (* Calculate offset *)
  let offset = (page - 1) * limit in
  
  (* Build SQL query with validated parameters *)
  let query = Printf.sprintf
    "SELECT id, original_filename, date_taken, file_size, width, height, mime_type, created_at, deleted_at 
     FROM photos WHERE deleted_at IS NULL ORDER BY %s %s LIMIT ? OFFSET ?"
    sort_field sort_order
  in
  
  let stmt = Sqlite3.prepare db query in
  
  (* Bind parameters *)
  let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int limit)) in
  let _ = Sqlite3.bind stmt 2 (Sqlite3.Data.INT (Int64.of_int offset)) in
  
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
        let photos = List.rev !results in
        (* Get total count and return both *)
        Lwt.bind (get_photo_count db) (fun total ->
          Lwt.return (photos, total))
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
