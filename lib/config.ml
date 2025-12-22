(** Configuration record *)
type t = {
  photo_storage_path : string;
  database_path : string;
  migrations_dir : string;
  port : int;
  interface : string;
  cors_allowed_origins : string list;
}

(** Get environment variable with optional default *)
let get_env name default =
  try Sys.getenv name
  with Not_found -> default

(** Load configuration from environment variables *)
let load () : t =
  (* Required: photo storage path *)
  let photo_storage_path =
    try Sys.getenv "PHOTO_STORAGE_PATH"
    with Not_found ->
      failwith "PHOTO_STORAGE_PATH environment variable is required"
  in
  
  (* Create storage directory if it doesn't exist *)
  if not (Sys.file_exists photo_storage_path) then
    Unix.mkdir photo_storage_path 0o755
  else if not (Sys.is_directory photo_storage_path) then
    failwith (Printf.sprintf "PHOTO_STORAGE_PATH '%s' is not a directory" photo_storage_path);
  
  (* Create backups and deleted subdirectories *)
  let backups_dir = Filename.concat photo_storage_path "backups" in
  let deleted_dir = Filename.concat photo_storage_path "deleted" in
  
  if not (Sys.file_exists backups_dir) then
    Unix.mkdir backups_dir 0o755
  else if not (Sys.is_directory backups_dir) then
    failwith (Printf.sprintf "Backups path '%s' exists but is not a directory" backups_dir);
  
  if not (Sys.file_exists deleted_dir) then
    Unix.mkdir deleted_dir 0o755
  else if not (Sys.is_directory deleted_dir) then
    failwith (Printf.sprintf "Deleted path '%s' exists but is not a directory" deleted_dir);
  
  (* Optional: database path *)
  let database_path = get_env "DATABASE_PATH" "./photos.db" in
  
  (* Optional: port *)
  let port =
    try int_of_string (get_env "PORT" "8080")
    with Failure _ ->
      failwith "PORT must be a valid integer"
  in
  
  (* Optional: interface (0.0.0.0 for all interfaces, 127.0.0.1 for localhost only) *)
  let interface = get_env "INTERFACE" "0.0.0.0" in
  
  (* Optional: CORS allowed origins *)
  let cors_allowed_origins =
    let origins_str = get_env "CORS_ALLOWED_ORIGINS" "*" in
    (* Split by comma and trim whitespace *)
    String.split_on_char ',' origins_str
    |> List.map String.trim
    |> List.filter (fun s -> String.length s > 0)
  in
  
  (* Optional: migrations directory *)
  let migrations_dir = get_env "MIGRATION_DIR" "./migrations" in
  
  (* Create migrations directory if it doesn't exist *)
  if not (Sys.file_exists migrations_dir) then
    Unix.mkdir migrations_dir 0o755
  else if not (Sys.is_directory migrations_dir) then
    failwith (Printf.sprintf "MIGRATION_DIR '%s' is not a directory" migrations_dir);
  
  { photo_storage_path; database_path; migrations_dir; port; interface; cors_allowed_origins }

(** Print configuration for debugging *)
let print config =
  Printf.printf "[INFO] Configuration loaded:\n";
  Printf.printf "  Photo storage: %s\n" config.photo_storage_path;
  Printf.printf "  Database: %s\n" config.database_path;
  Printf.printf "  Migrations directory: %s\n" config.migrations_dir;
  Printf.printf "  Port: %d\n" config.port;
  Printf.printf "  Interface: %s\n" config.interface;
  Printf.printf "  CORS allowed origins: %s\n" (String.concat ", " config.cors_allowed_origins);
  flush stdout
