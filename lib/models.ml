(** Photo metadata record type *)
type photo = {
  id : string;
  original_filename : string;
  date_taken : string;
  file_size : int;
  width : int option;
  height : int option;
  mime_type : string;
  created_at : string;
  deleted_at : string option;
}
[@@deriving yojson]

(** Convert SQLite row data to photo record *)
let of_sql_row (row : Sqlite3.Data.t array) : photo option =
  match row with
  | [| Sqlite3.Data.TEXT id;
       Sqlite3.Data.TEXT original_filename;
       Sqlite3.Data.TEXT date_taken;
       Sqlite3.Data.INT file_size;
       width_data;
       height_data;
       Sqlite3.Data.TEXT mime_type;
       Sqlite3.Data.TEXT created_at;
       deleted_at_data |] ->
      let width = match width_data with
        | Sqlite3.Data.INT w -> Some (Int64.to_int w)
        | Sqlite3.Data.NULL -> None
        | _ -> None
      in
      let height = match height_data with
        | Sqlite3.Data.INT h -> Some (Int64.to_int h)
        | Sqlite3.Data.NULL -> None
        | _ -> None
      in
      let deleted_at = match deleted_at_data with
        | Sqlite3.Data.TEXT dt -> Some dt
        | Sqlite3.Data.NULL -> None
        | _ -> None
      in
      Some {
        id;
        original_filename;
        date_taken;
        file_size = Int64.to_int file_size;
        width;
        height;
        mime_type;
        created_at;
        deleted_at;
      }
  | _ -> None

(** Convert photo record to JSON *)
let to_json (photo : photo) : Yojson.Safe.t =
  photo_to_yojson photo

(** Convert JSON to photo record *)
let from_json (json : Yojson.Safe.t) : (photo, string) result =
  match photo_of_yojson json with
  | Ok p -> Ok p
  | Error msg -> Error msg

(** Convert photo list to JSON array *)
let list_to_json (photos : photo list) : Yojson.Safe.t =
  `List (List.map to_json photos)
