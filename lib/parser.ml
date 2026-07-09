(** String -> {!Ast} parser.

    {b STATUS: stub.}  This is intentionally not implemented yet — the first
    skeleton milestone is the exact polynomial core and the certificate checker
    (see CLAUDE.md).  Tests and the [demo] build their ASTs / polynomials
    directly, so nothing depends on this parser working yet.

    {2 Grammar to implement (Milestone 2)}

    {v
      claim   := "prove"? expr relop expr
      relop   := ">=" | "<="
      expr    := term   (("+" | "-") term)*
      term    := factor ("*" factor)*
      factor  := base ("^" nat)?
      base    := number | ident | "(" expr ")" | "-" factor
      number  := int | int "/" int          (* e.g. 3, -4, 1/2 *)
      ident   := letter (letter | digit)*    (* e.g. a, b, x1 *)
    v}

    Precedence (tightest first): parentheses, powers, multiplication,
    addition/subtraction, then the relation.  Implicit multiplication (["ab"])
    is out of scope for v1; require explicit ["a*b"].  When implemented, this
    should return [Error msg] on malformed input rather than raising, so the CLI
    can report [INVALID_INPUT] cleanly. *)

(** Parse a bare expression. TODO(Milestone 2). *)
let parse_expr (_s : string) : (Ast.expr, string) result =
  Error "Parser.parse_expr: not implemented yet (TODO: Milestone 2)"

(** Parse a full claim ["A >= B"] (with an optional leading "prove").
    TODO(Milestone 2). *)
let parse (_s : string) : (Ast.claim, string) result =
  Error "Parser.parse: not implemented yet (TODO: Milestone 2)"
