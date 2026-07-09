(** Multivariate polynomials over the rationals.

    Abstract type: internally a finite map from canonical monomials to
    {b nonzero} rational coefficients. Every operation preserves this normal
    form, so {!equal} is equality of normal forms and cannot be fooled by
    construction history. Abstraction guarantees no value with a stored zero
    coefficient or a non-canonical key can exist. *)

type t

val zero : t
val one : t
val of_int : int -> t

(** The constant polynomial [c] (yields {!zero} when [c] is zero). *)
val const : Rational.t -> t

(** [var i] is the [i]-th variable. *)
val var : int -> t

(** [monomial m c] is the single term [c * m]. *)
val monomial : Monomial.t -> Rational.t -> t

val is_zero : t -> bool

(** Coefficient of a monomial (zero if absent). *)
val coeff : Monomial.t -> t -> Rational.t

(** Total degree; the zero polynomial has degree 0. *)
val degree : t -> int

(** Number of variables mentioned (highest used index plus one; 0 for a
    constant). *)
val num_vars : t -> int

(** Terms as an association list, sorted by {!Monomial.compare}. *)
val to_list : t -> (Monomial.t * Rational.t) list

val add : t -> t -> t
val neg : t -> t
val sub : t -> t -> t

(** Multiply every coefficient by a scalar. *)
val scalar_mul : Rational.t -> t -> t

val mul : t -> t -> t

(** [pow p n] raises [p] to the nonnegative power [n] ([pow p 0 = one]). *)
val pow : t -> int -> t

val sum : t list -> t

(** Re-establish the normal form of a possibly hand-built value. The identity on
    values produced by the constructors above. *)
val normalize : t -> t

(** Equality of normal forms. *)
val equal : t -> t -> bool
