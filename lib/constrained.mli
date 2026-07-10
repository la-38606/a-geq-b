(** Positivstellensatz certificates for {i constrained} inequalities.

    Where {!Certificate} proves [p >= 0] everywhere by a sum of squares, this
    proves [p >= 0] only on the region cut out by hypotheses [g_i >= 0] and
    [h_j = 0], via a certificate of the shape

    {[ p = base + sum_i sigma_i * g_i + sum_j lambda_j * h_j ]}

    with each [base]/[sigma_i] a sum of squares and each [lambda_j] arbitrary.
    This module holds the data only; the trusted {!Checker} verifies the
    identity and the sign conditions. *)

(** A hypothesis constraining the domain. *)
type hypothesis =
  | Nonneg of Polynomial.t (** [g >= 0] *)
  | Zero of Polynomial.t (** [h = 0] *)

(** One product term, its kind matched to the hypothesis kind it may use. *)
type product =
  | Times_nonneg of
      { multiplier : Certificate.t (** an SOS [sigma >= 0] *)
      ; nonneg : Polynomial.t (** the [Nonneg] hypothesis it scales *)
      }
  | Times_zero of
      { multiplier : Polynomial.t (** any polynomial [lambda] *)
      ; zero : Polynomial.t (** the [Zero] hypothesis it scales *)
      }

(** [p = base + sum products], with [base] and every {!Times_nonneg} multiplier
    a sum of squares. *)
type t =
  { base : Certificate.t
  ; products : product list
  }

val nonneg : Polynomial.t -> hypothesis
val zero : Polynomial.t -> hypothesis
val times_nonneg : multiplier:Certificate.t -> nonneg:Polynomial.t -> product
val times_zero : multiplier:Polynomial.t -> zero:Polynomial.t -> product
val make : base:Certificate.t -> products:product list -> t

(** Normalize a claim's [given] side conditions into hypotheses under the
    variable context: [a >= b] / [a <= b] give [Nonneg] of [a - b] / [b - a], and
    [a = b] gives [Zero (a - b)]. Raises [Invalid_argument] on an unknown variable
    or a non-polynomial side condition. *)
val hypotheses_of_claim : Normalizer.context -> Ast.claim -> hypothesis list

(** ["g >= 0"] or ["h = 0"]. *)
val string_of_hypothesis : Pretty.vars -> hypothesis -> string

(** Render the certificate's right-hand side [base + sum products]. *)
val to_string : Pretty.vars -> t -> string

val to_latex : Pretty.vars -> t -> string

(** Serialise to the constrained JSON format (see [examples/]). The hypotheses
    are carried explicitly, so [claim] is just the ["A >= B"] inequality. *)
val to_json
  :  claim:string
  -> vars:Pretty.vars
  -> hypotheses:hypothesis list
  -> t
  -> Yojson.Safe.t

(** A constrained certificate loaded from JSON, with the claim, the target
    polynomial [A - B], and the hypotheses cutting out the domain. All
    polynomials are built in the [vars] context. *)
type parsed =
  { claim_text : string
  ; vars : string list
  ; target : Polynomial.t
  ; hypotheses : hypothesis list
  ; certificate : t
  }

(** Load from a parsed JSON value. Returns [Error msg] (never raises) on any
    malformation. Validates shape only -- the caller must still run
    {!Checker.check_constrained}. *)
val of_json : Yojson.Safe.t -> (parsed, string) result

(** Parse from a JSON string. *)
val of_string : string -> (parsed, string) result

(** Read and parse a JSON file. *)
val load_file : string -> (parsed, string) result

(** The two certificate file shapes: an unconstrained sum-of-squares certificate
    or a constrained (Positivstellensatz) one. *)
type any =
  | Unconstrained of Certificate.parsed
  | Constrained of parsed

(** Load a certificate file of either shape, detected by a ["certificate"] object
    (constrained) versus a ["sos"] list (unconstrained). [Error msg] (never
    raises) on malformation. *)
val load_any : string -> (any, string) result
