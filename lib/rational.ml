(** Exact rational numbers.

    This module is the single point of contact with the underlying big-number
    library (Zarith).  Every other module in the project speaks in terms of
    [Rational.t] and never touches [Q] / [Z] directly.  Keeping the dependency
    localised here means:

    - the *trusted* checker relies on a tiny, well-understood arithmetic surface;
    - swapping the arithmetic backend (e.g. a self-contained bignum) later only
      touches this file.

    Invariant: values are always kept in lowest terms with a positive
    denominator.  Zarith's [Q] already guarantees this for every result of an
    arithmetic operation, so we get canonical rationals for free. *)

type t = Q.t

let zero : t = Q.zero
let one : t = Q.one

let of_int (n : int) : t = Q.of_int n

(** [of_ints num den] is the rational [num/den].  [den] must be non-zero. *)
let of_ints (num : int) (den : int) : t =
  if den = 0 then invalid_arg "Rational.of_ints: zero denominator";
  Q.of_ints num den

(** Parse a decimal integer or "p/q" fraction, e.g. "3", "-4", "1/2".
    Returns [None] on malformed input (used when validating certificates). *)
let of_string_opt (s : string) : t option =
  match Q.of_string s with
  | q -> if Q.is_real q then Some q else None
  | exception _ -> None

let add : t -> t -> t = Q.add
let sub : t -> t -> t = Q.sub
let mul : t -> t -> t = Q.mul
let div : t -> t -> t = Q.div
let neg : t -> t = Q.neg
let abs : t -> t = Q.abs

let compare : t -> t -> int = Q.compare
let equal : t -> t -> bool = Q.equal

(** [-1], [0] or [1] according to the sign of the argument. *)
let sign : t -> int = Q.sign

let is_zero (q : t) : bool = sign q = 0
let is_nonneg (q : t) : bool = sign q >= 0
let is_positive (q : t) : bool = sign q > 0

(** Human-readable form: "3", "-4", "1/2". *)
let to_string : t -> string = Q.to_string

(** LaTeX form: integers verbatim, fractions as [\frac{p}{q}] with a leading
    sign kept outside the fraction. *)
let to_latex (q : t) : string =
  let n = Q.num q and d = Q.den q in
  if Z.equal d Z.one then Z.to_string n
  else
    let frac = Printf.sprintf "\\frac{%s}{%s}" (Z.to_string (Z.abs n)) (Z.to_string d) in
    if Z.sign n < 0 then "-" ^ frac else frac
