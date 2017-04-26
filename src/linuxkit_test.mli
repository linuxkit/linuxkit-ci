open Datakit_ci

type t

val make : logs:Live_log.manager -> google_pool:Monitored_pool.t -> vms:Gcp.t -> build_cache:Disk_cache.t -> t
val gcp : t -> Hash.t -> unit Term.t
