type t
val snapshot : Nocrypto.Hash.SHA256.t -> t

val pp : t Fmt.t
val to_string : t -> string
val to_json : t -> Yojson.Basic.json
val of_json : Yojson.Basic.json -> t
