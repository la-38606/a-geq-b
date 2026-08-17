(** Sum-of-squares certificates.

    A certificate for [p >= 0] is a list of terms, each standing for
    [coeff * poly^2]; it {i claims} [p = sum_i coeff_i * poly_i^2] with every
    [coeff_i >= 0]. This module only holds and renders the data; deciding whether
    the claim is true is the job of the trusted {!Checker}. *)

(** One summand, representing [coeff * poly^2]. *)
type term =
  { coeff : Rational.t
  ; poly : Polynomial.t
  }

type t = term list

val term : Rational.t -> Polynomial.t -> term
val make : term list -> t

(** Render as ["c1*(q1)^2 + c2*(q2)^2 + ..."]. *)
val to_string : Pretty.vars -> t -> string

val to_latex : Pretty.vars -> t -> string

(** The summands of {!to_latex} individually (["c_i\\left(q_i\\right)^{2}"]),
    so a renderer can insert its own line breaks between terms. *)
val term_latexes : Pretty.vars -> t -> string list

(** Serialise to the JSON certificate format (see [examples/]). *)
val to_json : claim:string -> vars:Pretty.vars -> t -> Yojson.Safe.t

(** A certificate loaded from JSON, with the claim it is about and the target
    polynomial [A - B] the checker should verify. All polynomials are built in
    the [vars] context so their monomial indices line up. *)
type parsed =
  { claim_text : string
  ; vars : string list
  ; target : Polynomial.t
  ; certificate : t
  }

(** Load from a parsed JSON value. Returns [Error msg] (never raises) on any
    malformation: missing/mistyped fields, unparsable claim or polynomial, a
    malformed rational, or a variable outside the declared context. Validates
    shape only -- the caller must still run the {!Checker}. *)
val of_json : Yojson.Safe.t -> (parsed, string) result

(** Parse from a JSON string. *)
val of_string : string -> (parsed, string) result

(** Read and parse a JSON file. *)
val load_file : string -> (parsed, string) result
