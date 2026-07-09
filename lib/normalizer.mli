(** Turn an {!Ast} into a {!Polynomial}, clearing denominators.

    The variable ordering matters: monomial exponent vectors are positional, so
    the target polynomial and every certificate polynomial must be built with the
    same [context] for their indices to line up. *)

(** Ordered list of variable names; position is the variable index used by
    {!Polynomial.var}. *)
type context = string list

(** Evaluate an expression to a polynomial under [context]. Raises
    [Invalid_argument] on an unknown variable, or on division by a non-constant
    (use {!poly_of_claim} for genuine rational-function inequalities); division
    by a nonzero constant is allowed. *)
val poly_of_expr : context -> Ast.expr -> Polynomial.t

(** Reduce a claim to [(context, p)] where proving [p >= 0] proves the claim.
    Denominators are cleared soundly: if [A - B = N/D] then, since [D^2 >= 0],
    [A - B >= 0] iff [N * D >= 0] wherever [D <> 0], and [p = N * D]. When there
    is no division this is exactly [A - B]. Pass [~context] to fix the variable
    ordering; otherwise it is inferred from the claim. Raises [Invalid_argument]
    on division by zero. *)
val poly_of_claim : ?context:context -> Ast.claim -> context * Polynomial.t
