(lang dune 3.20)

(name memory-bank)

(generate_opam_files true)

(source
 (github sam-huckaby/memory-bank))

(authors "Sam Huckaby <samhuckaby@gmail.com>")

(maintainers "Sam Huckaby <samhuckaby@gmail.com>")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name memory-bank)
 (synopsis "Photo API server for living room display")
 (description "REST API for managing and serving photos with EXIF metadata extraction")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.20))
  dream
  sqlite3
  uuidm
  yojson
  (ppx_deriving_yojson (>= 3.7.0))
  lwt
  lwt_ppx)
 (tags
  (photo api rest ocaml dream sqlite)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
