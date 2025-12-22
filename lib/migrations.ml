(** Migration record type *)
type migration = {
  version: string;
  name: string;
  sql: string;
}

(** Create schema_migrations table if it doesn't exist *)
let init_migrations_table db =
  let schema = {|
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      applied_at TEXT NOT NULL
    );
  |} in
  
  let rc = Sqlite3.exec db schema in
  match rc with
  | Sqlite3.Rc.OK ->
      Printf.printf "[INFO] Migration tracking table initialized\n";
      flush stdout;
      Lwt.return_unit
  | _ ->
      let err = Sqlite3.errmsg db in
      Lwt.fail_with (Printf.sprintf "Failed to create schema_migrations table: %s" err)

(** Parse migration version from filename *)
let parse_migration_filename filename =
  try
    (* Extract version (e.g., "001" from "001_initial_schema.sql") *)
    let regex = Str.regexp "^\\([0-9]+\\)_\\(.+\\)\\.sql$" in
    if Str.string_match regex filename 0 then
      let version = Str.matched_group 1 filename in
      let name = Str.matched_group 2 filename in
      Some (version, name)
    else
      None
  with _ -> None

(** Load all migration files from directory *)
let load_migrations migrations_dir =
  if not (Sys.file_exists migrations_dir) then
    Lwt.fail_with (Printf.sprintf "Migrations directory not found: %s" migrations_dir)
  else
    let files = Sys.readdir migrations_dir in
    let migration_files = Array.to_list files
      |> List.filter (fun f -> Filename.check_suffix f ".sql")
      |> List.sort String.compare  (* Sort alphabetically = sort by version *)
    in
    
    let migrations = List.filter_map (fun filename ->
      match parse_migration_filename filename with
      | None ->
          Printf.fprintf stderr "[WARN] Skipping invalid migration filename: %s\n" filename;
          flush stderr;
          None
      | Some (version, name) ->
          let filepath = Filename.concat migrations_dir filename in
          let ic = open_in filepath in
          let sql = really_input_string ic (in_channel_length ic) in
          close_in ic;
          Some { version; name; sql }
    ) migration_files in
    
    Printf.printf "[INFO] Found %d migration file(s)\n" (List.length migrations);
    flush stdout;
    Lwt.return migrations

(** Get list of applied migrations from database *)
let get_applied_migrations db =
  let stmt = Sqlite3.prepare db "SELECT version FROM schema_migrations ORDER BY version" in
  
  let versions = ref [] in
  let rec step () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        (match row with
         | [| Sqlite3.Data.TEXT v |] -> versions := v :: !versions
         | _ -> ());
        step ()
    | Sqlite3.Rc.DONE ->
        let _ = Sqlite3.finalize stmt in
        Lwt.return (List.rev !versions)
    | _ ->
        let err = Sqlite3.errmsg db in
        let _ = Sqlite3.finalize stmt in
        Lwt.fail_with (Printf.sprintf "Failed to query applied migrations: %s" err)
  in
  step ()

(** Get current timestamp in ISO 8601 format *)
let get_timestamp () =
  let open Unix in
  let tm = gmtime (time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.000Z"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec

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

(** Apply a single migration within a transaction *)
let apply_migration db migration =
  let open Lwt.Syntax in
  Printf.printf "[INFO] Applying migration %s_%s...\n" migration.version migration.name;
  flush stdout;
  
  (* Begin transaction *)
  let* () = begin_transaction db in
  
  Lwt.catch
    (fun () ->
      (* Execute migration SQL *)
      let rc = Sqlite3.exec db migration.sql in
      match rc with
      | Sqlite3.Rc.OK ->
          (* Record migration in schema_migrations *)
          let timestamp = get_timestamp () in
          let stmt = Sqlite3.prepare db
            "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)" in
          
          let _ = Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT migration.version) in
          let _ = Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT migration.name) in
          let _ = Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT timestamp) in
          
          let step_rc = Sqlite3.step stmt in
          let _ = Sqlite3.finalize stmt in
          
          (match step_rc with
           | Sqlite3.Rc.DONE ->
               let* () = commit_transaction db in
               Printf.printf "[INFO] Successfully applied migration %s_%s\n" 
                 migration.version migration.name;
               flush stdout;
               Lwt.return_unit
           | _ ->
               let err = Sqlite3.errmsg db in
               let* () = rollback_transaction db in
               Lwt.fail_with (Printf.sprintf "Failed to record migration: %s" err))
      | _ ->
          let err = Sqlite3.errmsg db in
          let* () = rollback_transaction db in
          Lwt.fail_with (Printf.sprintf "Migration SQL failed: %s" err))
    (fun exn ->
      let* () = rollback_transaction db in
      Lwt.fail exn)

(** Run all pending migrations *)
let run_pending_migrations db migrations_dir =
  let open Lwt.Syntax in
  
  Printf.printf "[INFO] Checking for pending migrations...\n";
  flush stdout;
  
  let* migrations = load_migrations migrations_dir in
  let* applied = get_applied_migrations db in
  
  Printf.printf "[INFO] %d migration(s) already applied\n" (List.length applied);
  flush stdout;
  
  (* Filter pending migrations *)
  let pending = List.filter (fun m ->
    not (List.mem m.version applied)
  ) migrations in
  
  if List.length pending = 0 then (
    Printf.printf "[INFO] Database is up to date\n";
    flush stdout;
    Lwt.return_unit
  ) else (
    Printf.printf "[INFO] %d pending migration(s) to apply\n" (List.length pending);
    flush stdout;
    
    (* Apply each pending migration sequentially *)
    Lwt_list.iter_s (apply_migration db) pending
  )
