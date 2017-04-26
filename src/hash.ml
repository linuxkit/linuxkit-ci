open Datakit_ci

type t = string

let fmt_json j = Yojson.Basic.pretty_print j

let snapshot h = Cstruct.to_string (Nocrypto.Hash.SHA256.get h)

let to_string t =
  let `Hex s = Hex.of_string t in s

let pp f t =
  Fmt.string f (to_string t)

let of_json = function
  | `String s -> Hex.to_string (`Hex s)
  | x -> Utils.failf "Invalid hash in JSON: %a" fmt_json x

let to_json t =
  let `Hex hex = Hex.of_string t in
  `String hex
