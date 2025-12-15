(** Detect MIME type from file extension and magic bytes *)
let detect_mime_type _filename content =
  (* Check magic bytes for common formats *)
  let magic_bytes = if String.length content >= 4 then String.sub content 0 4 else "" in
  
  if String.length magic_bytes >= 2 then
    let byte1 = int_of_char magic_bytes.[0] in
    let byte2 = int_of_char magic_bytes.[1] in
    
    match (byte1, byte2) with
    | (0xFF, 0xD8) -> "image/jpeg"
    | (0x89, 0x50) -> "image/png"  (* PNG starts with 0x89504E47 *)
    | (0x47, 0x49) -> "image/gif"  (* GIF starts with "GIF" *)
    | (0x49, 0x49) | (0x4D, 0x4D) -> "image/tiff"  (* TIFF *)
    | _ ->
        (* Check for HEIC/HEIF - more complex, check ftyp box *)
        if String.length content >= 12 then
          let ftyp = String.sub content 4 8 in
          if String.sub ftyp 0 4 = "ftyp" then
            let brand = String.sub ftyp 4 4 in
            if brand = "heic" || brand = "heix" || brand = "hevc" || brand = "hevx" then
              "image/heic"
            else if brand = "mif1" then
              "image/heif"
            else
              "application/octet-stream"
          else
            "application/octet-stream"
        else
          "application/octet-stream"
  else
    "application/octet-stream"

(** Parse EXIF date string to ISO 8601 format *)
let parse_exif_date date_str =
  try
    (* EXIF format: "2023:12:13 14:30:45" *)
    let date_str = String.trim date_str in
    let parts = String.split_on_char ' ' date_str in
    match parts with
    | [date; time] ->
        let date_fixed = String.map (fun c -> if c = ':' then '-' else c) date in
        Some (date_fixed ^ "T" ^ time ^ "Z")
    | _ -> None
  with _ -> None

(** Extract EXIF data using exiftool *)
let extract_exif_data file_path =
  try
    let cmd = Printf.sprintf "exiftool -json -DateTimeOriginal -ImageWidth -ImageHeight -Orientation '%s' 2>/dev/null" file_path in
    let ic = Unix.open_process_in cmd in
    let json_str = input_line ic in
    let _ = Unix.close_process_in ic in
    
    (* Parse JSON response *)
    let json = Yojson.Safe.from_string json_str in
    match json with
    | `List (obj :: _) -> Some obj
    | _ -> None
  with _ -> None

(** Extract date taken from EXIF data *)
let extract_date_taken file_path created_at =
  match extract_exif_data file_path with
  | Some json ->
      (try
        let open Yojson.Safe.Util in
        let date_str = json |> member "DateTimeOriginal" |> to_string in
        match parse_exif_date date_str with
        | Some parsed_date -> parsed_date
        | None -> created_at
      with _ -> created_at)
  | None -> created_at

(** Extract image dimensions from EXIF data *)
let extract_dimensions file_path =
  match extract_exif_data file_path with
  | Some json ->
      (try
        let open Yojson.Safe.Util in
        let width = json |> member "ImageWidth" |> to_int in
        let height = json |> member "ImageHeight" |> to_int in
        
        (* Check for orientation and swap dimensions if needed *)
        let orientation = 
          try json |> member "Orientation" |> to_int
          with _ -> 1
        in
        
        (* Orientations 5-8 require dimension swap *)
        if orientation >= 5 && orientation <= 8 then
          Some (height, width)
        else
          Some (width, height)
      with _ -> None)
  | None -> None

(** Get current timestamp in ISO 8601 format *)
let get_current_timestamp () =
  let open Unix in
  let tm = gettimeofday () in
  let utc = gmtime tm in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (utc.tm_year + 1900)
    (utc.tm_mon + 1)
    utc.tm_mday
    utc.tm_hour
    utc.tm_min
    utc.tm_sec
