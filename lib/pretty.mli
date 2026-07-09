(** Human-readable and LaTeX rendering of monomials and polynomials.

    Each function takes the ordered list of variable names to use for the
    positional exponent vectors; an index beyond the list gets a fallback name
    ["x<n>"], so rendering never fails. *)

type vars = string list

val string_of_monomial : vars -> Monomial.t -> string
val string_of_poly : vars -> Polynomial.t -> string
val latex_of_monomial : vars -> Monomial.t -> string
val latex_of_poly : vars -> Polynomial.t -> string
