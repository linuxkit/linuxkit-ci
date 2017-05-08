open Datakit_ci
open! Astring
open Lwt.Infix

let timeout = 10. *. 60.

let with_child_switch switch fn =
  let child = Lwt_switch.create () in
  Lwt_switch.add_hook (Some switch) (fun () -> Lwt_switch.turn_off child);
  Lwt.finalize
    (fun () -> fn child)
    (fun () -> Lwt_switch.turn_off child)

let contains_success_message log =
  let log_output = Live_log.contents log in
  String.is_infix ~affix:"Kernel config test suite PASSED" log_output

module Builder = struct
  module Key = struct
    type t = {
      image : Hash.t;
    }
  end

  type t = {
    google_pool : Monitored_pool.t;
    vms : Gcp.t;
    build_cache : Disk_cache.t;
  }

  type context = job_id

  type value = unit

  let name _ = "LinuxKit test"

  let title _t _key = Fmt.strf "Test LinuxKit on GCP"

  let generate t ~switch ~log _trans job_id key =
    let { Key.image } = key in
    let image_path = Disk_cache.get t.build_cache image in
    let label = Fmt.strf "Test GCP image %a" Hash.pp image in
    Monitored_pool.use ~log ~label t.google_pool job_id @@ fun () ->
    Utils.with_timeout ~switch timeout @@ fun switch ->
    Gcp.allocate_vm_name ~log ~switch t.vms >>= fun vm ->
    with_child_switch switch @@ fun switch ->   (* Allow stopping the test early *)
    let output x =
      Live_log.write log x;
      if contains_success_message log then (
        Live_log.log log "Tests passed!";
        Lwt.async (fun () -> Lwt_switch.turn_off switch);     (* Exit early *)
      )
    in
    let cmd = ("", [| "/gcloud/test.py"; image_path; vm.Gcp.name |]) in
    Lwt.catch
      (fun () -> Process.run ~switch ~output cmd)
      (function Lwt_switch.Off -> Lwt.return ()
              | ex -> Lwt.fail ex
      )
    >|= fun () ->
    if contains_success_message log then
      Ok ()
    else
      Error (`Failure "Tests failed (success string not found in log output)")

  let load _t _tree _key =
    Lwt.return ()

  let branch _t { Key.image } =
    Fmt.strf "linuxkit-test-gcp-of-%a" Hash.pp image
end

module Result_cache = Cache.Make(Builder)

type t = Result_cache.t

let gcp t image =
  let open! Term.Infix in
  Term.job_id >>= fun job_id ->
  let key = { Builder.Key.
              image;
            } in
  Result_cache.find t job_id key

let make ~logs ~google_pool ~vms ~build_cache =
  Result_cache.create ~logs { Builder.google_pool; vms; build_cache }
