(** Human-readable and LaTeX rendering of monomials and polynomials.

    Each function takes the ordered list of variable names to use for the
    positional exponent vectors; an index beyond the list gets a fallback name
    ["x<n>"], so rendering never fails. *)

type vars = string list

(** Name for the [i]-th variable ([List.nth vars i], or a fallback ["x<i+1>"]
    when [i] is beyond [vars]). *)
val name_of : vars -> int -> string

val string_of_monomial : vars -> Monomial.t -> string
val string_of_poly : vars -> Polynomial.t -> string
val latex_of_monomial : vars -> Monomial.t -> string
val latex_of_poly : vars -> Polynomial.t -> string
