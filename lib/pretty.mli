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

(** LaTeX of a parsed expression, purely syntactically: nothing is simplified,
    combined, or reordered, so the typeset form shows exactly what was written
    and typesetting cannot change meaning. Minimal bracketing by precedence;
    division renders as a fraction. *)
val latex_of_expr : Ast.expr -> string

(** LaTeX of a whole claim, [A \ge B] (or [\le]), with any side conditions
    appended after "given". Used for input previews. *)
val latex_of_claim : Ast.claim -> string
