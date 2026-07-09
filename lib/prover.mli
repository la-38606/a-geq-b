(** The (untrusted) search engine.

    Looks for a sum-of-squares certificate for a target [p >= 0] via a Gram
    matrix and rational LDLᵀ over a monomial basis. It may be heuristic and
    incomplete; anything it returns MUST still pass the trusted {!Checker} before
    the system claims [PROVED], so a bug in the search can only cause a missed
    proof, never a false one. *)

type result =
  | Proved of Certificate.t
  | No_certificate_found (** not disproof -- just "this prover found nothing" *)

(** Attempt to find an SOS certificate for [p >= 0]. Any candidate is re-checked
    by the trusted {!Checker}. *)
val prove : Polynomial.t -> result

(** {2 Built-in "hello world" example}

    [a^2 + b^2 + c^2 >= a*b + b*c + c*a], with the classic three-square
    certificate. Used by the [demo] command and the tests. *)

val hello_world_vars : string list
val hello_world_claim_string : string
val hello_world_target : unit -> Polynomial.t
val hello_world_certificate : unit -> Certificate.t
