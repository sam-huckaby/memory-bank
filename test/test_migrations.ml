open Lwt.Syntax
open Memory_bank

(** Helper: Create temporary directory for tests *)
let make_temp_dir prefix =
  let temp_dir = Filename.temp_file prefix "" in
  Unix.unlink temp_dir;
  Unix.mkdir temp_dir 0o755;
  temp_dir

(** Helper: Clean up test directory *)
let cleanup_dir dir =
  if Sys.file_exists dir then (
    let files = Sys.readdir dir in
    Array.iter (fun f ->
      let path = Filename.concat dir f in
      if Sys.file_exists path then Unix.unlink path
    ) files;
    Unix.rmdir dir
  )

(** Helper: Create test migration files *)
let create_test_migrations dir =
  (* Migration 001 *)
  let migration_001 = {|-- Migration: Initial schema
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
CREATE INDEX IF NOT EXISTS idx_created_at ON photos(created_at);
|} in
  
  (* Migration 002 *)
  let migration_002 = {|-- Migration: Add soft delete
ALTER TABLE photos ADD COLUMN deleted_at TEXT;
CREATE INDEX IF NOT EXISTS idx_deleted_at ON photos(deleted_at);
|} in
  
  let oc = open_out (Filename.concat dir "001_initial_schema.sql") in
  output_string oc migration_001;
  close_out oc;
  
  let oc = open_out (Filename.concat dir "002_add_deleted_at.sql") in
  output_string oc migration_002;
  close_out oc

(** Test 1: Fresh database - all migrations should run *)
let test_fresh_database () =
  Alcotest.(check pass) "Setup" () ();
  
  let test_dir = make_temp_dir "test_fresh_" in
  let migrations_dir = Filename.concat test_dir "migrations" in
  Unix.mkdir migrations_dir 0o755;
  create_test_migrations migrations_dir;
  
  let db_path = Filename.concat test_dir "test.db" in
  
  let* db = Database.init db_path migrations_dir in
  
  (* Verify schema_migrations table exists and has 2 entries *)
  let stmt = Sqlite3.prepare db "SELECT COUNT(*) FROM schema_migrations" in
  let count = ref 0 in
  (match Sqlite3.step stmt with
   | Sqlite3.Rc.ROW ->
       let row = Sqlite3.row_data stmt in
       (match row with
        | [| Sqlite3.Data.INT c |] -> count := Int64.to_int c
        | _ -> ());
   | _ -> ());
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check int) "Two migrations applied" 2 !count;
  
  (* Verify deleted_at column exists *)
  let stmt = Sqlite3.prepare db "PRAGMA table_info(photos)" in
  let has_deleted_at = ref false in
  let rec check_columns () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        (match row with
         | [| _; Sqlite3.Data.TEXT name; _; _; _; _ |] ->
             if name = "deleted_at" then has_deleted_at := true
         | _ -> ());
        check_columns ()
    | Sqlite3.Rc.DONE -> ()
    | _ -> ()
  in
  check_columns ();
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check bool) "deleted_at column exists" true !has_deleted_at;
  
  let* () = Database.close db in
  cleanup_dir migrations_dir;
  cleanup_dir test_dir;
  Lwt.return_unit

(** Test 2: Database without deleted_at - only migration 002 should run *)
let test_migrate_deleted_at () =
  Alcotest.(check pass) "Setup" () ();
  
  let test_dir = make_temp_dir "test_legacy_" in
  let migrations_dir = Filename.concat test_dir "migrations" in
  Unix.mkdir migrations_dir 0o755;
  create_test_migrations migrations_dir;
  
  let db_path = Filename.concat test_dir "test.db" in
  
  (* Create "old" database with only migration 001 *)
  let db = Sqlite3.db_open db_path in
  let _ = Sqlite3.exec db {|
    CREATE TABLE schema_migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      applied_at TEXT NOT NULL
    );
    INSERT INTO schema_migrations (version, name, applied_at) 
    VALUES ('001', 'initial_schema', '2025-12-19T00:00:00.000Z');
    CREATE TABLE photos (
      id TEXT PRIMARY KEY,
      original_filename TEXT NOT NULL,
      date_taken TEXT NOT NULL,
      file_size INTEGER NOT NULL,
      width INTEGER,
      height INTEGER,
      mime_type TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
  |} in
  let _ = Sqlite3.db_close db in
  
  (* Now run migrations *)
  let* db = Database.init db_path migrations_dir in
  
  (* Verify only migration 002 was applied *)
  let stmt = Sqlite3.prepare db 
    "SELECT version FROM schema_migrations ORDER BY version" in
  let versions = ref [] in
  let rec collect () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        (match row with
         | [| Sqlite3.Data.TEXT v |] -> versions := v :: !versions
         | _ -> ());
        collect ()
    | Sqlite3.Rc.DONE -> ()
    | _ -> ()
  in
  collect ();
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check (list string)) "Both migrations recorded" 
    ["001"; "002"] (List.rev !versions);
  
  (* Verify deleted_at column now exists *)
  let stmt = Sqlite3.prepare db "SELECT deleted_at FROM photos LIMIT 0" in
  let has_column = match Sqlite3.step stmt with
    | Sqlite3.Rc.DONE -> true  (* Query succeeded, column exists *)
    | _ -> false
  in
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check bool) "deleted_at column added" true has_column;
  
  let* () = Database.close db in
  cleanup_dir migrations_dir;
  cleanup_dir test_dir;
  Lwt.return_unit

(** Test 3: Database already up-to-date - no migrations should run *)
let test_already_migrated () =
  Alcotest.(check pass) "Setup" () ();
  
  let test_dir = make_temp_dir "test_current_" in
  let migrations_dir = Filename.concat test_dir "migrations" in
  Unix.mkdir migrations_dir 0o755;
  create_test_migrations migrations_dir;
  
  let db_path = Filename.concat test_dir "test.db" in
  
  (* First initialization *)
  let* db = Database.init db_path migrations_dir in
  let* () = Database.close db in
  
  (* Second initialization - should be idempotent *)
  let* db = Database.init db_path migrations_dir in
  
  (* Count should still be 2 *)
  let stmt = Sqlite3.prepare db "SELECT COUNT(*) FROM schema_migrations" in
  let count = ref 0 in
  (match Sqlite3.step stmt with
   | Sqlite3.Rc.ROW ->
       let row = Sqlite3.row_data stmt in
       (match row with
        | [| Sqlite3.Data.INT c |] -> count := Int64.to_int c
        | _ -> ());
   | _ -> ());
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check int) "No duplicate migrations" 2 !count;
  
  let* () = Database.close db in
  cleanup_dir migrations_dir;
  cleanup_dir test_dir;
  Lwt.return_unit

(** Test 4: Invalid SQL in migration - should fail and rollback *)
let test_migration_failure () =
  Alcotest.(check pass) "Setup" () ();
  
  let test_dir = make_temp_dir "test_failure_" in
  let migrations_dir = Filename.concat test_dir "migrations" in
  Unix.mkdir migrations_dir 0o755;
  
  (* Create migration with invalid SQL *)
  let invalid_migration = {|-- Migration: Invalid
INVALID SQL STATEMENT HERE;
|} in
  
  let oc = open_out (Filename.concat migrations_dir "001_invalid.sql") in
  output_string oc invalid_migration;
  close_out oc;
  
  let db_path = Filename.concat test_dir "test.db" in
  
  (* This should fail *)
  let failed = ref false in
  let* () = Lwt.catch
    (fun () ->
      let* _db = Database.init db_path migrations_dir in
      Lwt.return_unit)
    (fun _exn ->
      failed := true;
      Lwt.return_unit)
  in
  
  Alcotest.(check bool) "Migration failed as expected" true !failed;
  
  cleanup_dir migrations_dir;
  cleanup_dir test_dir;
  Lwt.return_unit

(** Test 5: Migrations run in correct order *)
let test_migration_ordering () =
  Alcotest.(check pass) "Setup" () ();
  
  let test_dir = make_temp_dir "test_order_" in
  let migrations_dir = Filename.concat test_dir "migrations" in
  Unix.mkdir migrations_dir 0o755;
  
  (* Create migrations out of order in filesystem *)
  let migration_003 = {|-- Migration: Third
CREATE TABLE test_table (id INTEGER);
|} in
  
  let migration_001 = {|-- Migration: First
CREATE TABLE IF NOT EXISTS photos (id TEXT PRIMARY KEY);
|} in
  
  let migration_002 = {|-- Migration: Second
ALTER TABLE photos ADD COLUMN name TEXT;
|} in
  
  (* Write in reverse order *)
  let oc = open_out (Filename.concat migrations_dir "003_third.sql") in
  output_string oc migration_003;
  close_out oc;
  
  let oc = open_out (Filename.concat migrations_dir "001_first.sql") in
  output_string oc migration_001;
  close_out oc;
  
  let oc = open_out (Filename.concat migrations_dir "002_second.sql") in
  output_string oc migration_002;
  close_out oc;
  
  let db_path = Filename.concat test_dir "test.db" in
  let* db = Database.init db_path migrations_dir in
  
  (* Verify they ran in correct order *)
  let stmt = Sqlite3.prepare db 
    "SELECT version FROM schema_migrations ORDER BY id" in
  let versions = ref [] in
  let rec collect () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let row = Sqlite3.row_data stmt in
        (match row with
         | [| Sqlite3.Data.TEXT v |] -> versions := v :: !versions
         | _ -> ());
        collect ()
    | Sqlite3.Rc.DONE -> ()
    | _ -> ()
  in
  collect ();
  let _ = Sqlite3.finalize stmt in
  
  Alcotest.(check (list string)) "Migrations ran in order" 
    ["001"; "002"; "003"] (List.rev !versions);
  
  let* () = Database.close db in
  cleanup_dir migrations_dir;
  cleanup_dir test_dir;
  Lwt.return_unit

(** Alcotest suite definition *)
let () =
  let open Alcotest in
  run "Database Migrations" [
    "fresh_database", [
      test_case "All migrations run on fresh database" `Quick 
        (fun () -> Lwt_main.run (test_fresh_database ()));
    ];
    "legacy_database", [
      test_case "Missing deleted_at column is added" `Quick 
        (fun () -> Lwt_main.run (test_migrate_deleted_at ()));
    ];
    "idempotent", [
      test_case "Already migrated database stays unchanged" `Quick 
        (fun () -> Lwt_main.run (test_already_migrated ()));
    ];
    "error_handling", [
      test_case "Invalid migration fails gracefully" `Quick 
        (fun () -> Lwt_main.run (test_migration_failure ()));
    ];
    "ordering", [
      test_case "Migrations run in numeric order" `Quick 
        (fun () -> Lwt_main.run (test_migration_ordering ()));
    ];
  ]
