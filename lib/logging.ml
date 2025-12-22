(** Log levels *)
type level = INFO | WARN | ERROR

(** Log a structured message *)
let log level component message details =
  let level_str = match level with
    | INFO -> "INFO"
    | WARN -> "WARN"
    | ERROR -> "ERROR"
  in
  
  let timestamp = 
    let open Unix in
    let tm = gmtime (time ()) in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.000Z"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
      tm.tm_hour tm.tm_min tm.tm_sec
  in
  
  (* Build JSON log entry *)
  let log_entry = `Assoc [
    ("timestamp", `String timestamp);
    ("level", `String level_str);
    ("component", `String component);
    ("message", `String message);
    ("details", details);
  ] in
  
  let log_str = Yojson.Safe.to_string log_entry in
  
  (* Output to appropriate stream *)
  let output_channel = match level with
    | INFO -> stdout
    | WARN | ERROR -> stderr
  in
  
  Printf.fprintf output_channel "%s\n" log_str;
  flush output_channel

(** Log photo deletion *)
let log_photo_deleted ~id ~original_filename ~deleted_at =
  let details = `Assoc [
    ("photo_id", `String id);
    ("original_filename", `String original_filename);
    ("deleted_at", `String deleted_at);
    ("operation", `String "soft_delete");
  ] in
  log INFO "photo_management" "Photo soft deleted successfully" details
