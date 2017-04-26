open Datakit_ci
open Astring

type t

module Results : sig
  type t = Hash.t String.Map.t
end

val make : logs:Live_log.manager -> pool:Monitored_pool.t -> google_pool:Monitored_pool.t -> vms:Gcp.t -> build_cache:Disk_cache.t -> t
val build : t -> target:Target.t -> Git.commit -> Results.t Term.t
