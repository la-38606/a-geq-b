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

type constrained_result =
  | Proved_constrained of Constrained.t
  | No_constrained_certificate

(** Attempt a Positivstellensatz certificate that [target >= 0] on the region cut
    out by [hypotheses]. First cut: constant hypothesis-multipliers (nonnegative
    on [Nonneg] hypotheses, any sign on [Zero] hypotheses) over a bounded grid,
    with the unconstrained {!prove} finding the sum-of-squares base on the
    residual. Any candidate is re-checked by the trusted {!Checker}, so the
    search can only miss a proof, never produce a false one. *)
val prove_constrained
  :  hypotheses:Constrained.hypothesis list
  -> Polynomial.t
  -> constrained_result

(** {2 Built-in "hello world" example}

    [a^2 + b^2 + c^2 >= a*b + b*c + c*a], with the classic three-square
    certificate. Used by the [demo] command and the tests. *)

val hello_world_vars : string list
val hello_world_claim_string : string
val hello_world_target : unit -> Polynomial.t
val hello_world_certificate : unit -> Certificate.t
