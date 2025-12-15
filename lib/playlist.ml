(** Get a random playlist of photos from the database *)
let get db =
  Database.get_random_playlist db
