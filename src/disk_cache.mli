type t

val make : path:string -> t

val add : t -> string -> Hash.t Lwt.t
(** [add t path] copies [path] into the cache and returns its hash. *)

val validate : t -> Hash.t -> unit

val get : t -> Hash.t -> string
(** [get t hash] is the path of the image with hash [hash]. *)
