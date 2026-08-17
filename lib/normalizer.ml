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

(** Distinct variables of a claim, in order of first appearance: the claim's
    [lhs] then [rhs], then each side condition's [lhs] then [rhs]. Hypothesis
    variables must be included so that a variable occurring only in a [given]
    condition (e.g. [a >= 0 given b >= 0]) is still in the context. *)
let vars_of_claim (c : Ast.claim) : context =
  let add acc v = if List.mem v acc then acc else acc @ [ v ] in
  let add_expr acc e = List.fold_left add acc (vars_of_expr e) in
  let acc = add_expr (add_expr [] c.Ast.lhs) c.Ast.rhs in
  List.fold_left
    (fun acc (h : Ast.hyp) -> add_expr (add_expr acc h.hyp_lhs) h.hyp_rhs)
    acc
    c.Ast.hyps
;;

(* A rational function is a pair (numerator, denominator) of polynomials, with a
   nonzero denominator. Expressions are evaluated to rational functions so that
   division is supported; a claim then clears denominators (see below).
   Fractions are combined but not reduced to lowest terms; denominators grow,
   but the result is exact and that is all the checker needs. *)

(* Cap intermediate polynomial size on three axes so exact arithmetic cannot be
   made to hang on pathological input:
     - total DEGREE (nested powers compose: [((a+b)^80)^80] is degree 6400);
     - monomial COUNT (a low-degree polynomial in many variables can still have
       astronomically many terms: [(a+..+h)^100] is degree 100 but ~2.6e10 terms);
     - coefficient MAGNITUDE (nested powers of a constant, [((2)^100)^100], blow
       up the integers without changing degree or term count).
   Every degree-increasing multiplication is guarded BEFORE it runs, and powers go
   through that same guard term by term, so the oversized object is never built.
   No real inequality here comes close (the corpus tops out at degree 8), so only
   pathological input is refused. *)
let max_degree = 100
let max_terms = 20_000
let max_coeff_bits = 10_000
let too_big () = invalid_arg "Normalizer: intermediate result is too large to build"
let terms (p : Polynomial.t) : int = List.length (Polynomial.to_list p)

let coeff_bits (p : Polynomial.t) : int =
  List.fold_left (fun m (_, c) -> max m (Rational.size_bits c)) 0 (Polynomial.to_list p)
;;

let mul_capped (a : Polynomial.t) (b : Polynomial.t) : Polynomial.t =
  if
    Polynomial.degree a + Polynomial.degree b > max_degree
    || terms a * terms b > max_terms
    || coeff_bits a + coeff_bits b > max_coeff_bits
  then too_big ()
  else Polynomial.mul a b
;;

(* p^k via repeated capped multiplication, so the degree/count/magnitude guards
   apply at every step; a cheap up-front degree check short-circuits the obvious
   blow-up before any multiplication. *)
let pow_capped (p : Polynomial.t) (k : int) : Polynomial.t =
  if k = 0
  then Polynomial.one
  else if Polynomial.degree p * k > max_degree
  then too_big ()
  else (
    let rec go acc i = if i = 0 then acc else go (mul_capped acc p) (i - 1) in
    go p (k - 1))
;;

let rf_add (na, da) (nb, db) =
  Polynomial.add (mul_capped na db) (mul_capped nb da), mul_capped da db
;;

let rf_sub (na, da) (nb, db) =
  Polynomial.sub (mul_capped na db) (mul_capped nb da), mul_capped da db
;;

let rf_mul (na, da) (nb, db) = mul_capped na nb, mul_capped da db

let rf_div (na, da) (nb, db) =
  if Polynomial.is_zero nb
  then invalid_arg "Normalizer: division by zero"
  else mul_capped na db, mul_capped da nb
;;

let rf_pow (n, d) k = pow_capped n k, pow_capped d k

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
  (* A - B = num / den; the clearing multiplications are degree-capped too. *)
  let num = Polynomial.sub (mul_capped na db) (mul_capped nb da) in
  let den = mul_capped da db in
  let cleared = mul_capped num den in
  (* (A - B) * den^2 *)
  let p =
    match c.Ast.op with
    | Ast.Ge -> cleared
    | Ast.Le -> Polynomial.neg cleared
  in
  ctx, p
;;
