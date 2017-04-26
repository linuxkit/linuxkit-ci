open! Astring
open Lwt.Infix
open Datakit_ci

let src = Logs.Src.create "gcp" ~doc:"Google Cloud Platform VMs"
module Log = (val Logs.src_log src : Logs.LOG)

let vm_start_timeout = 15. *. 60.

type vm = {
  name : string;
  mutable vm_state : [`Unknown | `Created | `Destroyed];
}

let pp_vm f vm = Fmt.string f vm.name

type t = {
  prefix : string;
  state : string;
  ready : unit Lwt.t;
  mutable free_names : string list;
  mutable next : int;
}

let path t id =
  Filename.concat t.state (id ^ ".vm")

let add t id =
  let fd = Unix.openfile (path t id) [Unix.O_CREAT; Unix.O_EXCL] 0o600 in
  Unix.close fd

let remove t id =
  t.free_names <- id :: t.free_names;
  Unix.unlink (path t id)

let ls t =
  let ch = Unix.opendir t.state in
  let items = ref [] in
  try
    while true do
      let item = Unix.readdir ch in
      match String.cut ~rev:true ~sep:"." item with
      | Some (name, "vm") -> items := {name; vm_state = `Unknown} :: !items
      | _ -> ()
    done;
    assert false
  with End_of_file ->
    !items

let destroy_vm ?log t ~output vm =
  match vm.vm_state with
  | `Destroyed -> Lwt.return ()
  | `Unknown | `Created as vm_state ->
    begin match log with
      | Some log -> Live_log.log log "Removing test VM...";
      | None -> Log.info (fun f -> f "Removing test VM...")
    end;
    Lwt.catch
      (fun () -> Process.run ?log ~output ("", [| "/gcloud/destroy.py"; vm.name |]))
      (fun ex ->
         begin match vm_state with
           | `Created -> Log.err (fun f -> f "Failed to remove test VM %S: %s" vm.name (Printexc.to_string ex))
           | `Unknown -> Log.debug (fun f -> f "Failed to remove test VM (might never have been created): %s" (Printexc.to_string ex))
         end;
         Lwt.return ()
      )
    >|= fun () ->
    vm.vm_state <- `Destroyed;
    remove t vm.name

let allocate_vm_name ~log ~switch t =
  let output = Live_log.write log in
  t.ready >|= fun () ->
  let name =
    match t.free_names with
    | [] ->
      let name = t.prefix ^ string_of_int t.next in
      t.next <- t.next + 1;
      name
    | x :: xs ->
      t.free_names <- xs;
      x
  in
  add t name;
  let vm = { name; vm_state = `Unknown } in
  Lwt_switch.add_hook (Some switch) (fun () -> destroy_vm t ~log ~output vm);
  vm

let create_vm ~log ~switch t =
  allocate_vm_name ~log ~switch t >>= fun vm ->
  let ip = Buffer.create 32 in
  let cmd = ("", [| "/gcloud/create.py"; vm.name |]) in
  Utils.with_timeout ~switch vm_start_timeout (fun switch ->
      let output = Live_log.write log in
      Process.run ~switch ~log ~output:(Buffer.add_string ip) ~stderr:output cmd
    )
  >>= fun () ->
  let ip = String.trim (Buffer.contents ip) in
  vm.vm_state <- `Created;
  Lwt.return (vm, ip)

let cleanup_leftovers t = function
  | [] -> Lwt.return ()
  | leftovers ->
    Log.info (fun f -> f "Cleaning up left-over VMs: %a" (Fmt.Dump.list pp_vm) leftovers);
    let output x = output_string stdout x; flush stdout in
    leftovers |> Lwt_list.iter_s (fun vm -> destroy_vm t ~output vm)

let make ~state ~prefix =
  let state = Utils.abs_path state in
  let ready, set_ready = Lwt.wait () in
  Utils.ensure_dir ~mode:0o700 state;
  let t = { prefix; state; ready; free_names = []; next = 0 } in
  Lwt.async (fun () ->
      Lwt.catch (fun () ->
          Lwt_unix.sleep 1.0 >>= fun () ->    (* Allow logging to initialise *)
          cleanup_leftovers t (ls t)
        )
        (fun ex ->
           Log.err (fun f -> f "Error cleaning up left-over VMs: %a" Fmt.exn ex);
           Lwt.return ()
        )
      >|= fun () ->
      t.free_names <- [];
      Lwt.wakeup set_ready ()
    );
  t
