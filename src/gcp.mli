open Datakit_ci

val builder_ssh_key : string
(** Path of the SSH private key file. *)

type vm = {
  name : string;
  mutable vm_state : [`Unknown | `Created | `Destroyed];
}

type t
(** A configuration for using Google Compute *)

val make : state:string -> prefix:string -> t
(** [make ~state ~prefix] is a configuration for creating Google Compute VMs.
    The state is persisted in the directory [state] so that we don't forget to delete
    VMs even after being restarted.
    All VMs created have their names prefixed with [prefix]. *)

val create_vm : log:Live_log.t -> switch:Lwt_switch.t -> t -> (vm * string) Lwt.t
(** [create_vm ~log ~switch t] creates a new VM with an unused name and returns
    its IP address.
    The VM will be destroyed when [switch] is turned off, or when the service
    is restarted. *)

val allocate_vm_name : log:Live_log.t -> switch:Lwt_switch.t -> t -> vm Lwt.t
(** [allocate_vm_name] is similar to [create_vm], but the VM is not actually
    created (the caller must do that). *)

val pp_vm : vm Fmt.t
