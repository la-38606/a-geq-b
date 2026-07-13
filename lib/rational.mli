(** Exact rational numbers.

    The single point of contact with the underlying big-number backend (Zarith).
    Every other module speaks in terms of {!t} and never touches [Q]/[Z]
    directly, which keeps the trusted checker's arithmetic surface tiny and makes
    the backend swappable.

    Values are always kept in lowest terms with a positive denominator. *)

type t

val zero : t
val one : t
val of_int : int -> t

(** [of_ints num den] is [num/den]; [den] must be non-zero. *)
val of_ints : int -> int -> t

(** Parse a decimal integer or ["p/q"] fraction; [None] on malformed input. *)
val of_string_opt : string -> t option

val add : t -> t -> t
val sub : t -> t -> t
val mul : t -> t -> t
val div : t -> t -> t
val neg : t -> t
val abs : t -> t
val compare : t -> t -> int
val equal : t -> t -> bool

(** [-1], [0] or [1] according to sign. *)
val sign : t -> int

val is_zero : t -> bool
val is_nonneg : t -> bool
val is_positive : t -> bool

(** A rough magnitude in bits (numerator bit-length plus denominator bit-length),
    used to bound coefficient growth; [0] for [0] and [±1]. *)
val size_bits : t -> int

(** Human-readable form: ["3"], ["-4"], ["1/2"]. *)
val to_string : t -> string

(** LaTeX form: integers verbatim, fractions as [\frac{p}{q}]. *)
val to_latex : t -> string
