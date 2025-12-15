(** Generate a new UUID v4 for photo ID *)
let generate_id () : string =
  Uuidm.v4_gen (Random.State.make_self_init ()) ()
  |> Uuidm.to_string

(** Get full file path for a photo ID *)
let get_file_path storage_path id =
  Filename.concat storage_path id

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
