open Datakit_ci
open Lwt.Infix

let ( / ) = Filename.concat

type t = {
  path : string;
}

let make ~path = { path }

let get t hash =
  t.path / Hash.to_string hash

let add t path =
  let module SHA256 = Nocrypto.Hash.SHA256 in
  let h = SHA256.init () in
  Lwt_io.with_file ~mode:Lwt_io.input path (fun ch ->
      Lwt_io.read ~count:8192 ch >|= fun data ->
      SHA256.feed h (Cstruct.of_string data)
    )
  >>= fun () ->
  let hash = Hash.snapshot h in
  let dst = get t hash in
  let cmd = ("", [| "cp"; "--"; path; dst |]) in
  Process.run ~output:(output_string stdout) cmd >>= fun () ->
  Lwt.return hash

let validate t hash =
  let path = get t hash in
  if not (Sys.file_exists path) then
    Utils.failf "Saved cache entry %s no longer exists" path
