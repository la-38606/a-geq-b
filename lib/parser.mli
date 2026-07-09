(** String -> {!Ast} parser (recursive descent).

    Grammar (tightest binding first): parentheses, powers, multiplication and
    division, addition and subtraction, then the relation. A bare integer
    fraction like ["1/2"] is a single rational literal; division between
    expressions (["a/(b+c)"]) is cleared by the {!Normalizer}. Both entry points
    return [Error msg] on malformed input and never raise. *)

(** Parse a bare expression. *)
val parse_expr : string -> (Ast.expr, string) result

(** Parse a full claim ["A >= B"] (with an optional leading ["prove"]). *)
val parse : string -> (Ast.claim, string) result
