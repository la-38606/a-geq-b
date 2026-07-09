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
;;

(** Distinct variables of an expression, in order of first appearance. *)
let vars_of_expr (e : Ast.expr) : context =
  let seen = ref [] in
  let add v = if not (List.mem v !seen) then seen := v :: !seen in
  let rec go = function
    | Ast.Const _ -> ()
    | Ast.Var v -> add v
    | Ast.Neg a -> go a
    | Ast.Pow (a, _) -> go a
    | Ast.Add (a, b) | Ast.Sub (a, b) | Ast.Mul (a, b) | Ast.Div (a, b) ->
      go a;
      go b
  in
  go e;
  List.rev !seen
;;

(** Distinct variables of a claim, in order of first appearance (lhs then rhs). *)
let vars_of_claim (c : Ast.claim) : context =
  let l = vars_of_expr c.Ast.lhs
  and r = vars_of_expr c.Ast.rhs in
  List.fold_left (fun acc v -> if List.mem v acc then acc else acc @ [ v ]) l r
;;

(* A rational function is a pair (numerator, denominator) of polynomials, with a
   nonzero denominator. Expressions are evaluated to rational functions so that
   division is supported; a claim then clears denominators (see below).
   Fractions are combined but not reduced to lowest terms — denominators grow,
   but the result is exact and that is all the checker needs. *)

let rf_add (na, da) (nb, db) =
  Polynomial.add (Polynomial.mul na db) (Polynomial.mul nb da), Polynomial.mul da db
;;

let rf_sub (na, da) (nb, db) =
  Polynomial.sub (Polynomial.mul na db) (Polynomial.mul nb da), Polynomial.mul da db
;;

let rf_mul (na, da) (nb, db) = Polynomial.mul na nb, Polynomial.mul da db

let rf_div (na, da) (nb, db) =
  if Polynomial.is_zero nb
  then invalid_arg "Normalizer: division by zero"
  else Polynomial.mul na db, Polynomial.mul da nb
;;

let rf_pow (n, d) k = Polynomial.pow n k, Polynomial.pow d k

(** Evaluate [e] to a rational function [(num, den)] under the variable ordering
    [ctx]. Raises [Invalid_argument] on an unknown variable or a division by
    zero. The denominator is always a nonzero polynomial. *)
let rec ratfunc_of_expr (ctx : context) (e : Ast.expr) : Polynomial.t * Polynomial.t =
  match e with
  | Ast.Const q -> Polynomial.const q, Polynomial.one
  | Ast.Var v ->
    (match index_of ctx v with
     | Some i -> Polynomial.var i, Polynomial.one
     | None -> invalid_arg ("Normalizer: variable not in context: " ^ v))
  | Ast.Neg a ->
    let n, d = ratfunc_of_expr ctx a in
    Polynomial.neg n, d
  | Ast.Add (a, b) -> rf_add (ratfunc_of_expr ctx a) (ratfunc_of_expr ctx b)
  | Ast.Sub (a, b) -> rf_sub (ratfunc_of_expr ctx a) (ratfunc_of_expr ctx b)
  | Ast.Mul (a, b) -> rf_mul (ratfunc_of_expr ctx a) (ratfunc_of_expr ctx b)
  | Ast.Div (a, b) -> rf_div (ratfunc_of_expr ctx a) (ratfunc_of_expr ctx b)
  | Ast.Pow (a, n) -> rf_pow (ratfunc_of_expr ctx a) n
;;

(** Evaluate [e] to a polynomial under the variable ordering [ctx]. This is for
    expressions that ARE polynomials; a division by a non-constant raises
    [Invalid_argument] (use {!poly_of_claim}, which clears denominators, for
    genuine rational-function inequalities). Division by a nonzero constant is
    allowed. Raises [Invalid_argument] on an unknown variable. *)
let poly_of_expr (ctx : context) (e : Ast.expr) : Polynomial.t =
  let n, d = ratfunc_of_expr ctx e in
  if Polynomial.degree d = 0
  then (
    (* d is a nonzero constant c; the polynomial is n / c *)
    let c = Polynomial.coeff Monomial.one d in
    Polynomial.scalar_mul (Rational.div Rational.one c) n)
  else
    invalid_arg
      "Normalizer.poly_of_expr: expression is not a polynomial (division by a \
       non-constant)"
;;

(** Reduce a claim to [(context, p)] where proving [p >= 0] proves the claim.

    Denominators are cleared soundly: if [A - B = N / D] then, since [D^2 >= 0],
    [A - B >= 0] iff [N * D >= 0] wherever [D <> 0]. So the target polynomial is
    [p = N * D] (for [A >= B]; negated for [A <= B]). When the claim is already
    a polynomial ([D] constant [1]), this is exactly [A - B] as before.

    Pass [~context] to fix the variable ordering; otherwise it is inferred from
    the claim in order of first appearance. *)
let poly_of_claim ?(context : context option) (c : Ast.claim) : context * Polynomial.t =
  let ctx =
    match context with
    | Some ctx -> ctx
    | None -> vars_of_claim c
  in
  let na, da = ratfunc_of_expr ctx c.Ast.lhs in
  let nb, db = ratfunc_of_expr ctx c.Ast.rhs in
  (* A - B = num / den *)
  let num = Polynomial.sub (Polynomial.mul na db) (Polynomial.mul nb da) in
  let den = Polynomial.mul da db in
  let cleared = Polynomial.mul num den in
  (* (A - B) * den^2 *)
  let p =
    match c.Ast.op with
    | Ast.Ge -> cleared
    | Ast.Le -> Polynomial.neg cleared
  in
  ctx, p
;;
