(** String -> {!Ast} parser (recursive descent).

    Turns strings like ["prove a^2 + b^2 >= 2*a*b"] into an {!Ast.claim}, and
    bare expressions like ["1/2*a^2 - b"] into an {!Ast.expr}.

    {2 Grammar}

    {v
      claim   := "prove"? expr relop expr
      relop   := ">=" | "<="
      expr    := term   (("+" | "-") term)*
      term    := factor (("*" | "/") factor)*
      factor  := base ("^" nat)?
      base    := number | ident | "(" expr ")" | "-" factor
      number  := int | int "/" int          (* e.g. 3, -4, 1/2 *)
      ident   := letter (letter | digit)*    (* e.g. a, b, x1 *)
    v}

    Precedence (tightest first): parentheses, powers, multiplication/division,
    addition/subtraction, then the relation.  Unary minus binds a [factor]
    (so [-a^2] parses as [-(a^2)]).  Implicit multiplication (["ab"]) is out of
    scope for v1 — write ["a*b"].  Division between expressions (["a/(b+c)"]) is
    allowed and is cleared of denominators by the {!Normalizer}; a bare integer
    fraction like ["1/2"] is still read as a single rational literal.

    Both entry points return [Error msg] on malformed input and never raise. *)

(* ---------------------------------------------------------------------- *)
(* Lexer                                                                    *)
(* ---------------------------------------------------------------------- *)

type token =
  | INT of int
  | IDENT of string
  | PROVE
  | PLUS
  | MINUS
  | STAR
  | CARET
  | SLASH
  | LPAREN
  | RPAREN
  | GE
  | LE
  | EOF

exception Error_msg of string

let is_digit c = c >= '0' && c <= '9'
let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_alnum c = is_digit c || is_alpha c

let tokenize (s : string) : token list =
  let n = String.length s in
  let toks = ref [] in
  let push t = toks := t :: !toks in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    match c with
    | ' ' | '\t' | '\n' | '\r' -> incr i
    | '+' ->
      push PLUS;
      incr i
    | '-' ->
      push MINUS;
      incr i
    | '*' ->
      push STAR;
      incr i
    | '^' ->
      push CARET;
      incr i
    | '/' ->
      push SLASH;
      incr i
    | '(' ->
      push LPAREN;
      incr i
    | ')' ->
      push RPAREN;
      incr i
    | '>' ->
      if !i + 1 < n && s.[!i + 1] = '='
      then (
        push GE;
        i := !i + 2)
      else raise (Error_msg "expected '>=' after '>'")
    | '<' ->
      if !i + 1 < n && s.[!i + 1] = '='
      then (
        push LE;
        i := !i + 2)
      else raise (Error_msg "expected '<=' after '<'")
    | _ when is_digit c ->
      let j = ref !i in
      while !j < n && is_digit s.[!j] do
        incr j
      done;
      let text = String.sub s !i (!j - !i) in
      (match int_of_string_opt text with
       | Some v -> push (INT v)
       | None -> raise (Error_msg ("integer literal out of range: " ^ text)));
      i := !j
    | _ when is_alpha c ->
      let j = ref !i in
      while !j < n && is_alnum s.[!j] do
        incr j
      done;
      let name = String.sub s !i (!j - !i) in
      push (if String.equal name "prove" then PROVE else IDENT name);
      i := !j
    | _ -> raise (Error_msg (Printf.sprintf "unexpected character %C" c))
  done;
  List.rev (EOF :: !toks)
;;

(* ---------------------------------------------------------------------- *)
(* Parser (operates on a mutable token cursor)                              *)
(* ---------------------------------------------------------------------- *)

type cursor = { mutable toks : token list }

let peek (c : cursor) : token =
  match c.toks with
  | t :: _ -> t
  | [] -> EOF
;;

let peek2 (c : cursor) : token =
  match c.toks with
  | _ :: t :: _ -> t
  | _ -> EOF
;;

let advance (c : cursor) : unit =
  match c.toks with
  | _ :: r -> c.toks <- r
  | [] -> ()
;;

let expect (c : cursor) (t : token) (msg : string) : unit =
  if peek c = t then advance c else raise (Error_msg msg)
;;

(* number := int | int "/" int
   A '/' is only absorbed into a rational literal when it is immediately
   followed by an integer (so "1/2" is the literal 1/2, while "1/a" leaves the
   '/' for division in p_term). *)
let p_number (c : cursor) : Rational.t =
  match peek c with
  | INT num ->
    advance c;
    (match peek c, peek2 c with
     | SLASH, INT den ->
       advance c (* '/' *);
       advance c (* denominator *);
       if den = 0 then raise (Error_msg "zero denominator in rational literal");
       Rational.of_ints num den
     | _ -> Rational.of_int num)
  | _ -> raise (Error_msg "expected a number")
;;

let rec p_base (c : cursor) : Ast.expr =
  match peek c with
  | INT _ -> Ast.Const (p_number c)
  | IDENT name ->
    advance c;
    Ast.Var name
  | LPAREN ->
    advance c;
    let e = p_expr c in
    expect c RPAREN "expected ')'";
    e
  | MINUS ->
    advance c;
    Ast.Neg (p_factor c)
  | _ -> raise (Error_msg "expected a number, variable, '(' or '-'")

and p_factor (c : cursor) : Ast.expr =
  let b = p_base c in
  match peek c with
  | CARET ->
    advance c;
    (match peek c with
     | INT k ->
       advance c;
       if k < 0 then raise (Error_msg "negative exponent");
       Ast.Pow (b, k)
     | _ -> raise (Error_msg "expected an integer exponent after '^'"))
  | _ -> b

and p_term (c : cursor) : Ast.expr =
  let left = ref (p_factor c) in
  let continue = ref true in
  while !continue do
    match peek c with
    | STAR ->
      advance c;
      left := Ast.Mul (!left, p_factor c)
    | SLASH ->
      advance c;
      left := Ast.Div (!left, p_factor c)
    | _ -> continue := false
  done;
  !left

and p_expr (c : cursor) : Ast.expr =
  let left = ref (p_term c) in
  let continue = ref true in
  while !continue do
    match peek c with
    | PLUS ->
      advance c;
      left := Ast.Add (!left, p_term c)
    | MINUS ->
      advance c;
      left := Ast.Sub (!left, p_term c)
    | _ -> continue := false
  done;
  !left
;;

let p_claim (c : cursor) : Ast.claim =
  if peek c = PROVE then advance c;
  let lhs = p_expr c in
  let op =
    match peek c with
    | GE ->
      advance c;
      Ast.Ge
    | LE ->
      advance c;
      Ast.Le
    | _ -> raise (Error_msg "expected '>=' or '<='")
  in
  let rhs = p_expr c in
  { Ast.lhs; op; rhs }
;;

(* ---------------------------------------------------------------------- *)
(* Public entry points                                                      *)
(* ---------------------------------------------------------------------- *)

let run (start : cursor -> 'a) (s : string) : ('a, string) result =
  match
    let c = { toks = tokenize s } in
    let result = start c in
    expect c EOF "unexpected trailing input";
    result
  with
  | v -> Ok v
  | exception Error_msg m -> Error m
;;

let parse_expr (s : string) : (Ast.expr, string) result = run p_expr s
let parse (s : string) : (Ast.claim, string) result = run p_claim s
