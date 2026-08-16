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

(** {2 Semidefinite (SDP) path helpers}

    Building blocks for the external numerical SDP prover (see the [sdp/]
    directory): OCaml emits a Gram semidefinite program, Python solves it
    numerically, and OCaml rounds the result back to exact rationals with these.
    Untrusted, like the rest of the prover: any certificate produced through them
    is re-checked by the trusted {!Checker} before the system claims [PROVED]. *)

(** The monomial basis the SDP path uses for [p] -- wider than the bases
    {!prove} tries, so the numerical solver has the Gram freedom the bounded grid
    search cannot explore. Both sides of the pipeline must agree on it. *)
val sdp_basis : Polynomial.t -> Monomial.t array

(** SOS certificate read off a rational Gram matrix over the given basis by exact
    LDLᵀ, or [None] if the matrix is not positive semidefinite. *)
val certificate_of_gram
  :  Monomial.t array
  -> Rational.t array array
  -> Certificate.t option

(** Which constrained strategy found the certificate, reported so interfaces can
    describe the route taken. Carries no soundness weight: the trusted {!Checker}
    re-verifies the certificate regardless of its origin. *)
type constrained_strategy =
  | Constant_multipliers
  (** constant multiples of hypotheses subtracted; an SOS base proves the
      residual *)
  | Equality_reduction
  (** polynomial multipliers on equalities, found by reduction modulo them *)
  | Hypothesis_products
  (** a constant times a product of two nonnegative hypotheses (Schmüdgen) *)

type constrained_result =
  | Proved_constrained of constrained_strategy * Constrained.t
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

(** [true] iff the hypotheses are provably contradictory (they cut out an empty
    region), detected by a Positivstellensatz refutation ([-1 >= 0] on the
    region) that the trusted {!Checker} accepts. Incomplete: [false] means "not
    shown", not "consistent". A claim proved under contradictory hypotheses holds
    only vacuously. *)
val hypotheses_infeasible : hypotheses:Constrained.hypothesis list -> bool

(** {2 Built-in "hello world" example}

    [a^2 + b^2 + c^2 >= a*b + b*c + c*a], with the classic three-square
    certificate. Used by the [demo] command and the tests. *)

val hello_world_vars : string list
val hello_world_claim_string : string
val hello_world_target : unit -> Polynomial.t
val hello_world_certificate : unit -> Certificate.t
