(** Turn an {!Ast} into a {!Polynomial} in canonical form.

    Two jobs:

    - {!poly_of_expr}: evaluate an expression tree into a polynomial, using a
      fixed variable ordering (the [context]);
    - {!poly_of_claim}: reduce a claim [A >= B] (or [A <= B]) to the single
      polynomial [p] that must be shown [>= 0].  For [A >= B] that is [A - B];
      for [A <= B] it is [B - A].

    The variable ordering matters: monomial exponent vectors are positional, so
    the target polynomial and every certificate polynomial must be built with
    the {b same} [context] for their indices to line up. *)

(** Ordered list of variable names; position in the list is the variable index
    used by {!Monomial.var} / {!Polynomial.var}. *)
type context = string list

(** Index of [name] in [ctx], or [None] if it is not present. *)
let index_of (ctx : context) (name : string) : int option =
  let rec go i = function
    | [] -> None
    | x :: xs -> if String.equal x name then Some i else go (i + 1) xs
  in
  go 0 ctx

(** Distinct variables of an expression, in order of first appearance. *)
let vars_of_expr (e : Ast.expr) : context =
  let seen = ref [] in
  let add v = if not (List.mem v !seen) then seen := v :: !seen in
  let rec go = function
    | Ast.Const _ -> ()
    | Ast.Var v -> add v
    | Ast.Neg a -> go a
    | Ast.Pow (a, _) -> go a
    | Ast.Add (a, b) | Ast.Sub (a, b) | Ast.Mul (a, b) -> go a; go b
  in
  go e;
  List.rev !seen

(** Distinct variables of a claim, in order of first appearance (lhs then rhs). *)
let vars_of_claim (c : Ast.claim) : context =
  let l = vars_of_expr c.Ast.lhs and r = vars_of_expr c.Ast.rhs in
  List.fold_left (fun acc v -> if List.mem v acc then acc else acc @ [ v ]) l r

(** Evaluate [e] to a polynomial under the variable ordering [ctx].
    Raises [Invalid_argument] if [e] mentions a variable absent from [ctx]. *)
let rec poly_of_expr (ctx : context) (e : Ast.expr) : Polynomial.t =
  match e with
  | Ast.Const q -> Polynomial.const q
  | Ast.Var v -> (
      match index_of ctx v with
      | Some i -> Polynomial.var i
      | None -> invalid_arg ("Normalizer: variable not in context: " ^ v))
  | Ast.Neg a -> Polynomial.neg (poly_of_expr ctx a)
  | Ast.Add (a, b) -> Polynomial.add (poly_of_expr ctx a) (poly_of_expr ctx b)
  | Ast.Sub (a, b) -> Polynomial.sub (poly_of_expr ctx a) (poly_of_expr ctx b)
  | Ast.Mul (a, b) -> Polynomial.mul (poly_of_expr ctx a) (poly_of_expr ctx b)
  | Ast.Pow (a, n) -> Polynomial.pow (poly_of_expr ctx a) n

(** Reduce a claim to [(context, p)] where proving [p >= 0] proves the claim.
    Pass [~context] to fix the variable ordering; otherwise it is inferred from
    the claim in order of first appearance. *)
let poly_of_claim ?(context : context option) (c : Ast.claim) : context * Polynomial.t =
  let ctx = match context with Some ctx -> ctx | None -> vars_of_claim c in
  let a = poly_of_expr ctx c.Ast.lhs and b = poly_of_expr ctx c.Ast.rhs in
  let p =
    match c.Ast.op with
    | Ast.Ge -> Polynomial.sub a b (* prove A - B >= 0 *)
    | Ast.Le -> Polynomial.sub b a (* prove B - A >= 0 *)
  in
  (ctx, p)
