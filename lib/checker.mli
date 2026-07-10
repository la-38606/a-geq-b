(** The trusted certificate checker -- the sole authority on soundness.

    This is the trusted core of the LCF-style design. The search engine
    ({!Prover}) is untrusted; the system reports [PROVED] only when this module
    accepts. It therefore stays small, obviously correct, and exact.

    Given a target [p] (already reduced to [A - B]) and a certificate
    [ [ (c_i, q_i) ] ], it verifies that every [c_i >= 0] and that [p] is
    {i exactly} equal to [sum_i c_i * q_i^2]. Because each [q_i^2] is a square
    and each [c_i] is nonnegative, that identity proves [p >= 0] for all reals.
    Soundness depends only on exact rational arithmetic, exact polynomial
    multiplication and addition, and structural equality -- nothing about how the
    certificate was found. *)

(** Why a certificate was rejected. *)
type failure =
  | Negative_coefficient of Rational.t
  | Mismatch of
      { target : Polynomial.t
      ; got : Polynomial.t
      }
  | Unknown_constraint of Polynomial.t
  (** a constrained certificate scaled a polynomial that is not a declared
      hypothesis of the matching kind *)

type outcome =
  | Verified
  | Rejected of failure

(** The polynomial [sum_i c_i * q_i^2] denoted by a certificate. *)
val expand : Certificate.t -> Polynomial.t

(** Full check, returning a reason on rejection. *)
val check : Polynomial.t -> Certificate.t -> outcome

(** [true] iff the certificate proves [target >= 0]. The predicate the CLI must
    consult before printing [PROVED]. *)
val check_sos : Polynomial.t -> Certificate.t -> bool

(** The polynomial [base + sum_i sigma_i g_i + sum_j lambda_j h_j] denoted by a
    constrained certificate. *)
val expand_constrained : Constrained.t -> Polynomial.t

(** Verify a Positivstellensatz certificate that [target >= 0] on the region cut
    out by [hypotheses]: every sum-of-squares part has nonnegative coefficients,
    every scaled polynomial is a declared hypothesis of the matching kind, and
    [target] equals the certificate's expansion exactly. *)
val check_constrained
  :  hypotheses:Constrained.hypothesis list
  -> Polynomial.t
  -> Constrained.t
  -> outcome

(** [true] iff the constrained certificate proves [target >= 0] on the region cut
    out by [hypotheses]. Consult before printing [PROVED]. *)
val check_constrained_ok
  :  hypotheses:Constrained.hypothesis list
  -> Polynomial.t
  -> Constrained.t
  -> bool
