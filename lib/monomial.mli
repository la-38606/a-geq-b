(** Monomials as exponent vectors, in canonical form.

    A monomial [a^2 b c^3] is the exponent vector [[2;1;3]]. The canonical form
    has {b no trailing zeros}, so each monomial has a unique representation
    ([a^2] is [[2]] regardless of the ambient variable count) and the constant
    monomial is the empty vector. The type is abstract so that only canonical,
    nonnegative exponent vectors can exist. *)

type t

(** Put an arbitrary exponent vector into canonical form (validating
    nonnegativity, dropping trailing zeros). The only way to build a monomial
    from raw exponents. *)
val canonical : int list -> t

(** The canonical exponent vector (trailing zeros stripped). *)
val exponents : t -> int list

(** The constant monomial [1]. *)
val one : t

(** [var i] is [x_i] (0-indexed). *)
val var : int -> t

val is_constant : t -> bool

(** Total degree (sum of exponents). *)
val degree : t -> int

(** Product: position-wise sum of exponents. *)
val mul : t -> t -> t

(** Total order on monomials (used as a [Map] key). *)
val compare : t -> t -> int

val equal : t -> t -> bool
