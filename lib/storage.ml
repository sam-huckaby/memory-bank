(** Generate a new UUID v4 for photo ID *)
let generate_id () : string =
  Uuidm.v4_gen (Random.State.make_self_init ()) ()
  |> Uuidm.to_string

(** Get full file path for a photo ID *)
let get_file_path storage_path id =
  Filename.concat storage_path id

(** Get the deleted photos directory path *)
let get_deleted_dir storage_path =
  Filename.concat storage_path "deleted"

(** Get the backup directory path *)
let get_backup_dir storage_path =
  Filename.concat storage_path "backups"

(** Ensure a directory exists, create if needed *)
let ensure_directory_exists dir_path =
  if not (Sys.file_exists dir_path) then
    Unix.mkdir dir_path 0o755
  else if not (Sys.is_directory dir_path) then
    failwith (Printf.sprintf "Path exists but is not a directory: %s" dir_path)

(** Get full file path for a photo ID in the deleted directory *)
let get_deleted_file_path storage_path id =
  Filename.concat (get_deleted_dir storage_path) id

(** Get backup file path *)
let get_backup_file_path storage_path id timestamp =
  let backup_dir = get_backup_dir storage_path in
  let backup_filename = Printf.sprintf "%s.backup.%f" id timestamp in
  Filename.concat backup_dir backup_filename

(** Save photo content to disk with UUID-only filename *)
let save_photo ~storage_path ~id ~content =
  let file_path = get_file_path storage_path id in
  let oc = open_out_bin file_path in
  output_string oc content;
  close_out oc;
  Lwt.return_unit

(** Read photo content from disk *)
let read_photo ~storage_path ~id =
  let file_path = get_file_path storage_path id in
  if not (Sys.file_exists file_path) then
    Lwt.return_error "Photo not found"
  else
    let ic = open_in_bin file_path in
    let length = in_channel_length ic in
    let content = really_input_string ic length in
    close_in ic;
    Lwt.return_ok content

(** Get file size in bytes *)
let get_file_size file_path =
  let stats = Unix.stat file_path in
  stats.Unix.st_size

(** Check if photo exists *)
let photo_exists ~storage_path ~id =
  let file_path = get_file_path storage_path id in
  Sys.file_exists file_path

(** Move photo to backup location (transaction safety) *)
let backup_photo_for_delete ~storage_path ~id =
  ensure_directory_exists (get_backup_dir storage_path);
  let file_path = get_file_path storage_path id in
  if not (Sys.file_exists file_path) then
    Lwt.return_error "Photo file not found"
  else
    let timestamp = Unix.time () in
    let backup_path = get_backup_file_path storage_path id timestamp in
    try
      Unix.rename file_path backup_path;
      Lwt.return_ok backup_path
    with
    | Unix.Unix_error (err, _, _) ->
        Lwt.return_error (Printf.sprintf "Failed to backup photo: %s" 
                           (Unix.error_message err))
    | e ->
        Lwt.return_error (Printf.sprintf "Failed to backup photo: %s" 
                           (Printexc.to_string e))

(** Move backup to deleted directory (after successful soft delete) *)
let move_to_deleted ~backup_path ~storage_path ~id =
  ensure_directory_exists (get_deleted_dir storage_path);
  let deleted_path = get_deleted_file_path storage_path id in
  try
    Unix.rename backup_path deleted_path;
    Lwt.return_unit
  with
  | Unix.Unix_error (err, _, _) ->
      (* Log but don't fail - file is already backed up *)
      Printf.fprintf stderr "[WARN] Failed to move to deleted dir: %s\n" 
        (Unix.error_message err);
      flush stderr;
      Lwt.return_unit
  | e ->
      Printf.fprintf stderr "[WARN] Failed to move to deleted dir: %s\n" 
        (Printexc.to_string e);
      flush stderr;
      Lwt.return_unit

(** Restore photo from backup (on transaction failure) *)
let restore_photo ~backup_path ~storage_path ~id =
  let file_path = get_file_path storage_path id in
  try
    Unix.rename backup_path file_path;
    Lwt.return_unit
  with
  | Unix.Unix_error (err, _, _) ->
      Lwt.fail_with (Printf.sprintf "Failed to restore photo: %s" 
                      (Unix.error_message err))
  | e ->
      Lwt.fail_with (Printf.sprintf "Failed to restore photo: %s" 
                      (Printexc.to_string e))
