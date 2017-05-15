open Datakit_ci
open Lwt.Infix
open! Astring

let src = Logs.Src.create "linuxkit-build" ~doc:"LinuxKit CI builder"
module Log = (val Logs.src_log src : Logs.LOG)

let builder_ssh_key = "/run/secrets/builder-ssh"

type error_pattern = {
  score : int;
  re : Str.regexp;
  group : int;
}

let artifacts_path =
  let open! Datakit_path.Infix in
  Cache.Path.value / "artifacts"

(* Each line is checked against each pattern in this list. The first match is used as the score
   for the line. The matched group becomes the new best error, unless it's score is less than
   the current best. *)
let re_errors = [
  { score = 4; re = Str.regexp "## \\(.*\\)"; group = 1};
  { score = 1; re = Str.regexp ".* level=fatal msg=\"\\(exit status .*\\)\""; group = 1};
  { score = 3; re = Str.regexp ".* level=fatal msg=\"\\(.*\\)\""; group = 1};
  { score = 3; re = Str.regexp "\\(qemu: could not load .*\\)"; group = 1};
  { score = 2; re = Str.regexp "[^ ]*:[0-9]+\\(:[0-9]+\\)?:? \\(.*\\)"; group = 2};
  { score = 1; re = Str.regexp "Makefile:[0-9]+:? \\(.*\\)"; group = 2};
]

let ( / ) = Filename.concat

let build_timeout = 60. *. 60.

let ( >>*= ) x f =
  x >>= function
  | Ok x -> f x
  | Error e -> Utils.failf "Unexpected DB error: %a" DK.pp_error e

let pp_short_hash f c =
  Fmt.string f @@ String.with_range (Git.hash c) ~len:8

let fmt_json j = Yojson.Basic.pretty_print j

let with_child_switch switch fn =
  let child = Lwt_switch.create () in
  Lwt_switch.add_hook (Some switch) (fun () -> Lwt_switch.turn_off child);
  Lwt.finalize
    (fun () -> fn child)
    (fun () -> Lwt_switch.turn_off child)

let outputs = ["test.img.tar.gz"]

module Results : sig
  type t = Hash.t String.Map.t

  val to_json : t -> Yojson.Basic.json
  val of_json : Yojson.Basic.json -> t
end = struct
  type t = Hash.t String.Map.t

  let str_value (k, v) = (k, Hash.to_json v)

  let to_json t : Yojson.Basic.json = `Assoc [
      "outputs", `Assoc (String.Map.bindings t |> List.map str_value);
    ]

  let parse_output (k, v) = (k, Hash.of_json v)

  let of_json json =
    match Yojson.Basic.Util.member "outputs" json with
    | `Assoc outputs -> String.Map.of_list (List.map parse_output outputs)
    | x -> Utils.failf "Invalid results JSON: %a" fmt_json x
end

module Error_finder : sig
  type t

  val create : unit -> t

  val feed : t -> string -> unit
  (** [feed t data] adds output from the build. *)

  val best : t -> string option
  (** [best t] is the best error found. *)

  val reset : t -> unit
end = struct
  type t = {
    mutable buf : string;
    mutable best : (int * string) option;
  }

  let create () = {
    buf = "";
    best = None;
  }

  let reset t =
    t.buf <- "";
    t.best <- None

  let score line =
    let rec aux = function
      | [] -> None
      | { score; group; re } :: rest ->
        if Str.string_match re line 0 then
          Some (score, Str.matched_group group line)
        else aux rest
    in
    aux re_errors

  let process_line t line =
    match score line with
    | None -> ()
    | Some (new_score, msg) ->
      match t.best with
      | Some (prev_score, _) when prev_score > new_score -> ()
      | _ -> t.best <- Some (new_score, msg)

  let rec process t =
    match String.cut ~sep:"\n" t.buf with
    | None -> ()
    | Some (line, rest) ->
      process_line t line;
      t.buf <- rest;
      process t

  let feed t x =
    t.buf <- t.buf ^ x;
    process t

  let best t =
    match t.best with
    | None -> None
    | Some (_, msg) -> Some msg
end

let rec copy_to_transaction ~trans ~dir srcdir =
  let ( / ) = Datakit_path.Infix.( / ) in
  Utils.ls srcdir
  >>= Lwt_list.iter_s (function
      | "." | ".." -> Lwt.return ()
      | item ->
        let dk_path = dir / item in
        let path = Filename.concat srcdir item in
        Lwt_unix.lstat path >>= fun info ->
        match info.Lwt_unix.st_kind with
        | Lwt_unix.S_REG ->
          Log.debug (fun f -> f "Copying %S to results..." item);
          Lwt_io.with_file ~mode:Lwt_io.input path (fun ch -> Lwt_io.read ch) >>= fun data ->
          DK.Transaction.create_file trans dk_path (Cstruct.of_string data) >>*= Lwt.return
        | Lwt_unix.S_DIR ->
          DK.Transaction.create_dir trans dk_path >>*= fun () ->
          let open! Datakit_path.Infix in
          copy_to_transaction ~trans ~dir:dk_path (Filename.concat srcdir item)
        | _ ->
          Log.warn (fun f -> f "Ignoring non-file entry %S" item);
          Lwt.return ()
    )

let is_directory path =
  match Sys.is_directory path with
  | x -> x
  | exception _ -> false

let storing_logs ~log ~tmpdir ~trans fn () =
  Lwt.finalize fn
    (fun () ->
       let results_dir = tmpdir / "_results" in
       if is_directory results_dir then
         copy_to_transaction ~trans ~dir:Cache.Path.value results_dir
       else (
         Live_log.log log "Results directory %S not found, so not saving" results_dir;
         Lwt.return_unit
       )
    )

module Builder = struct
  module Key = struct
    type t = {
      src : Git.commit;
      target : Target.t;
    }
  end

  type t = {
    pool : Monitored_pool.t;
    google_pool : Monitored_pool.t;
    results : Disk_cache.t;
    vms : Gcp.t;
  }

  type context = job_id

  type value = Results.t

  let name _ = "LinuxKit build"

  let make_target = function
    | `PR _ -> "ci-pr", None
    | `Ref (_, ("heads" :: _)) -> "ci", None
    | `Ref (_, ("tags" :: name)) -> "ci-tag", Some name
    | `Ref _ -> assert false

  let title _t _key = Fmt.strf "Build LinuxKit"

  let with_vm vms ~switch ~log f =
    with_child_switch switch @@ fun switch ->
    Live_log.with_pending_reason log "Creating VM" (fun () -> Gcp.create_vm ~log ~switch vms) >>= fun (vm, ip) ->
    Live_log.log log "Created new VM %a" Gcp.pp_vm vm;
    f ip

  let build_in_vm ~switch ~log ~ip ~tmpdir ~output ~best_error =
    let src = tmpdir / "src" in
    let to_ssh, from_tar = Unix.pipe () in
    let tar_cmd = ("", [| "git"; "archive"; "--format=tar"; "HEAD" |]) in
    Lwt_mutex.with_lock Datakit_ci.Utils.chdir_lock (fun () ->
        Sys.chdir src;
        let child = Lwt_process.open_process_none ~stdout:(`FD_move from_tar) tar_cmd in
        Sys.chdir "/";   (* Just to detect problems with this scheme early *)
        Lwt.return child
      )
    >>= fun tar ->
    Lwt.finalize
      (fun () ->
         let stdin = `FD_move to_ssh in
         (* StrictHostKeyChecking=no isn't ideal, but this appears to be what "gcloud ssh" does anyway. *)
         let cmd = ("", [| "ssh"; "-i"; builder_ssh_key;
                           "-o"; "StrictHostKeyChecking=no"; "root@" ^ ip; "/usr/local/bin/test.sh" |]) in
         Lwt.catch
           (fun () ->
              Datakit_ci.Process.run ~switch ~log ~stdin ~output cmd >|= fun () ->
              Error_finder.reset best_error;
              Ok ()
           )
           (fun ex -> Lwt.return (Error ex))
      )
      (fun () ->
         tar#terminate;
         tar#status >|= Datakit_ci.Process.check_status tar_cmd
      )
    >>= fun status ->
    let targets =
      Fmt.strf "root@%s:/tmp/build/test/_results" ip ::
      (
        match status with
        | Ok () -> [Fmt.strf "root@%s:/tmp/build/artifacts" ip]
        | Error _ -> []
      )
    in
    let cmd = [
      "scp";
      "-r";
      "-i"; builder_ssh_key;
      "-o"; "StrictHostKeyChecking=no"
    ] @ targets @ [
      "."
    ] in
    Live_log.log log "Fetching results";
    let output = Live_log.write log in
    Lwt.catch
      (fun () ->
         Process.run ~cwd:tmpdir ~log ~switch ~output ("", Array.of_list cmd) >>= fun () ->
         match status with
         | Ok () -> Lwt.return ()
         | Error ex -> Lwt.fail ex
      )
      (fun ex ->
         Live_log.log log "Error fetching results: %a" Fmt.exn ex;
         match status with
         | Ok () ->
           Utils.failf "Failed to fetch %a"
             Fmt.(list ~sep:(const string ",") string) outputs
         | Error ex ->
           Lwt.fail ex
      )
    
  let generate t ~switch ~log trans job_id key =
    let { Key.src; target } = key in
    let label = Fmt.strf "Build LinuxKit (%a)" pp_short_hash src in
    let pool =
      match target with
      | `PR _ -> t.google_pool
      | `Ref _ -> t.pool
    in
    Monitored_pool.use ~log ~label pool job_id @@ fun () ->
    Utils.with_tmpdir ~prefix:"linuxkit-" ~mode:0o700 @@ fun tmpdir ->
    (* LinuxKit needs the .git directory, so we have to copy *)
    Git.with_checkout ~log ~job_id src (fun src_dir ->
        let output = Live_log.write log in
        let copy = tmpdir / "src" in
        Process.run ~log ~output ("", [| "git"; "clone"; src_dir; copy |]) >>= fun () ->
        Lwt.return copy
      )
    >>= fun src_dir ->
    let best_error = Error_finder.create () in
    let output x =
      Error_finder.feed best_error x;
      Live_log.write log x
    in
    Lwt.catch
      (storing_logs ~log ~tmpdir ~trans (fun () ->
         Utils.with_timeout ~switch build_timeout @@ fun switch ->
         match target with
         | `PR _ ->
           with_vm t.vms ~switch ~log (fun ip -> build_in_vm ~switch ~log ~ip ~tmpdir ~output ~best_error)
         | `Ref _ ->
           let make_target, tag_name = make_target target in
           let extra_args =
             match tag_name with
             | None -> []
             | Some name -> [Fmt.strf "CI_TAG=%s" (String.concat ~sep:"/" name)]
           in
           let label = Fmt.strf "LinuxKit LTP tests (%a)" pp_short_hash src in
           Monitored_pool.use ~log ~label t.google_pool job_id @@ fun () ->
           with_child_switch switch (fun switch ->
               Gcp.allocate_vm_name ~log ~switch t.vms >>= fun test_vm ->
               let cmd = "make" :: make_target :: ("CLOUDSDK_IMAGE_NAME=" ^ test_vm.Gcp.name) :: extra_args in
               Lwt.finalize
                 (fun () -> Process.run ~cwd:src_dir ~log ~switch ~output ("", Array.of_list cmd))
                 (fun () ->
                    if is_directory (src_dir / "artifacts") then
                      Unix.rename (src_dir / "artifacts") (tmpdir / "artifacts");
                    if is_directory (src_dir / "test/_results") then
                      Unix.rename (src_dir / "test/_results") (tmpdir / "_results");
                    Lwt.return ()
                 )
             )
      ))
      (fun ex ->
         match Error_finder.best best_error with
         | None -> Lwt.fail ex
         | Some msg -> Lwt.fail_with msg
      )
    >>= fun () ->
    let artifacts_dir = tmpdir / "artifacts" in
    let results = ref String.Map.empty in
    outputs |> Lwt_list.iter_s (fun output_name ->
        let path = artifacts_dir / output_name in
        if Sys.file_exists path then (
          Disk_cache.add t.results (artifacts_dir / output_name) >|= fun hash ->
          Live_log.log log "Saved build result %s (%a)" output_name Hash.pp hash;
          results := String.Map.add output_name hash !results
        ) else (
          Live_log.log log "Artifact %S does not exist, so not saving" output_name;
          Lwt.return ()
        )
      )
    >>= fun () ->
    let results = !results in
    let data = Cstruct.of_string (Yojson.Basic.to_string (Results.to_json results)) in
    DK.Transaction.create_file trans artifacts_path data >>*= fun () ->
    Lwt.return (Ok results)

  let load_json t data =
    let json = Yojson.Basic.from_string (Cstruct.to_string data) in
    let results = Results.of_json json in
    String.Map.iter (fun _k v -> Disk_cache.validate t.results v) results;
    Lwt.return results

  let load t tree _key =
    DK.Tree.read_file tree artifacts_path >>= function
    | Ok data -> load_json t data
    | Error `Not_file -> DK.Tree.read_file tree Cache.Path.value >>*= load_json t
    | Error e -> Utils.failf "Unexpected DB error: %a" DK.pp_error e

  let branch _t { Key.src; target} =
    let src_hash = Git.hash src in
    let target, tag_name = make_target target in
    let pp_opt_tag f = function
      | None -> ()
      | Some name -> Fmt.pf f "-%a" Fmt.(list ~sep:(const string "_") string) name
    in
    Fmt.strf "linuxkit-build-of-%s-default-%s%a"
      src_hash
      target
      pp_opt_tag tag_name
end

module Result_cache = Cache.Make(Builder)

type t = Result_cache.t

let build t ~target src =
  let open! Term.Infix in
  Term.job_id >>= fun job_id ->
  let key = { Builder.Key.
              src;
              target;
            } in
  Result_cache.find t job_id key

let make ~logs ~pool ~google_pool ~vms ~build_cache:results =
  Result_cache.create ~logs { Builder.pool; google_pool; vms; results }
