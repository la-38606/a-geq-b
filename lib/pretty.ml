(** Human-readable and LaTeX rendering of monomials and polynomials.

    All functions take a [vars] argument: the ordered list of variable names to
    use for the (positional) exponent vectors.  If a monomial mentions a
    variable index beyond [vars], a fallback name ["x<n>"] is used so rendering
    never fails. *)

type vars = string list

let name_of (vars : vars) (i : int) : string =
  match List.nth_opt vars i with
  | Some n -> n
  | None -> Printf.sprintf "x%d" (i + 1)
;;

(* Terms are shown in a stable, readable order: higher total degree first, then
   descending lexicographic on the exponent vector (so a^2, a*b, a*c, b^2, ...). *)
let display_order (m1, _) (m2, _) =
  let d = Int.compare (Monomial.degree m2) (Monomial.degree m1) in
  if d <> 0 then d else Monomial.compare m2 m1
;;

(* --- plain-text ("string") rendering ----------------------------------- *)

(** e.g. [[2; 1]] -> "a^2*b"; the constant monomial [[]] -> "". *)
let string_of_monomial (vars : vars) (m : Monomial.t) : string =
  List.mapi
    (fun i e ->
       if e = 0
       then None
       else if e = 1
       then Some (name_of vars i)
       else Some (Printf.sprintf "%s^%d" (name_of vars i) e))
    (Monomial.exponents m)
  |> List.filter_map Fun.id
  |> String.concat "*"
;;

let string_of_poly (vars : vars) (p : Polynomial.t) : string =
  if Polynomial.is_zero p
  then "0"
  else (
    let terms = List.sort display_order (Polynomial.to_list p) in
    let buf = Buffer.create 64 in
    List.iteri
      (fun idx (m, c) ->
         let neg = Rational.sign c < 0 in
         if idx = 0
         then (if neg then Buffer.add_string buf "-")
         else Buffer.add_string buf (if neg then " - " else " + ");
         let mag = Rational.to_string (Rational.abs c) in
         let mono = string_of_monomial vars m in
         if mono = ""
         then Buffer.add_string buf mag (* constant term *)
         else if Rational.equal (Rational.abs c) Rational.one
         then Buffer.add_string buf mono (* coefficient +/-1 is implicit *)
         else (
           Buffer.add_string buf mag;
           Buffer.add_char buf '*';
           Buffer.add_string buf mono))
      terms;
    Buffer.contents buf)
;;

(* --- LaTeX rendering ---------------------------------------------------- *)

(** e.g. [[2; 1]] -> "a^{2}b" (juxtaposition, braces around exponents). *)
let latex_of_monomial (vars : vars) (m : Monomial.t) : string =
  List.mapi
    (fun i e ->
       if e = 0
       then None
       else if e = 1
       then Some (name_of vars i)
       else Some (Printf.sprintf "%s^{%d}" (name_of vars i) e))
    (Monomial.exponents m)
  |> List.filter_map Fun.id
  |> String.concat ""
;;

let latex_of_poly (vars : vars) (p : Polynomial.t) : string =
  if Polynomial.is_zero p
  then "0"
  else (
    let terms = List.sort display_order (Polynomial.to_list p) in
    let buf = Buffer.create 64 in
    List.iteri
      (fun idx (m, c) ->
         let neg = Rational.sign c < 0 in
         if idx = 0
         then (if neg then Buffer.add_string buf "-")
         else Buffer.add_string buf (if neg then " - " else " + ");
         let mag = Rational.to_latex (Rational.abs c) in
         let mono = latex_of_monomial vars m in
         if mono = ""
         then Buffer.add_string buf mag
         else if Rational.equal (Rational.abs c) Rational.one
         then Buffer.add_string buf mono
         else (
           Buffer.add_string buf mag;
           Buffer.add_string buf mono))
      terms;
    Buffer.contents buf)
;;

(* --- LaTeX of a parsed claim, purely syntactically ----------------------- *)

(* Rendering the input AST rather than a normalized polynomial: nothing is
   simplified, combined, or reordered, so the typeset preview shows exactly the
   claim the user wrote and typesetting cannot change meaning. *)

(* Variable names as typed; multi-character names are set upright-italic as one
   identifier rather than as a product of letters. *)
let latex_of_name (s : string) : string =
  if String.length s <= 1 then s else Printf.sprintf "\\mathit{%s}" s
;;

(* Precedence of the operator that produced a node, for minimal bracketing. *)
let prec : Ast.expr -> int = function
  | Ast.Add (_, _) | Ast.Sub (_, _) -> 1
  | Ast.Neg _ -> 2
  | Ast.Mul (_, _) | Ast.Div (_, _) -> 3
  | Ast.Pow (_, _) -> 4
  | Ast.Const _ | Ast.Var _ -> 5
;;

let rec latex_of_expr (e : Ast.expr) : string =
  (* Bracket a subexpression whose operator binds no tighter than [level]. *)
  let atom level sub =
    let s = latex_of_expr sub in
    if prec sub < level then Printf.sprintf "\\left(%s\\right)" s else s
  in
  match e with
  | Ast.Const q -> Rational.to_latex q
  | Ast.Var s -> latex_of_name s
  | Ast.Neg a -> "-" ^ atom 2 a
  | Ast.Add (a, b) -> latex_of_expr a ^ " + " ^ atom 1 b
  | Ast.Sub (a, b) -> latex_of_expr a ^ " - " ^ atom 2 b
  | Ast.Mul (a, b) ->
    let left = atom 3 a
    and right = atom 4 b (* also brackets x/y so a*(b/c) is not read as ab/c *) in
    (* Juxtapose (2ab), except when the right factor starts with a digit or a
       sign, where an explicit dot keeps 2*3 from reading as 23. *)
    let needs_dot =
      right <> ""
      &&
      match right.[0] with
      | '0' .. '9' | '-' | '\\' -> true
      | _ -> false
    in
    if needs_dot then left ^ " \\cdot " ^ right else left ^ right
  | Ast.Div (a, b) ->
    Printf.sprintf "\\frac{%s}{%s}" (latex_of_expr a) (latex_of_expr b)
  | Ast.Pow (a, n) -> Printf.sprintf "%s^{%d}" (atom 5 a) n
;;

let latex_of_relop : Ast.relop -> string = function
  | Ast.Ge -> "\\ge"
  | Ast.Le -> "\\le"
;;

let latex_of_hyp_op : Ast.hyp_op -> string = function
  | Ast.Hyp_ge -> "\\ge"
  | Ast.Hyp_le -> "\\le"
  | Ast.Hyp_eq -> "="
;;

let latex_of_claim (c : Ast.claim) : string =
  let head =
    Printf.sprintf
      "%s %s %s"
      (latex_of_expr c.Ast.lhs)
      (latex_of_relop c.Ast.op)
      (latex_of_expr c.Ast.rhs)
  in
  match c.Ast.hyps with
  | [] -> head
  | hyps ->
    let hyp h =
      Printf.sprintf
        "%s %s %s"
        (latex_of_expr h.Ast.hyp_lhs)
        (latex_of_hyp_op h.Ast.hyp_op)
        (latex_of_expr h.Ast.hyp_rhs)
    in
    head ^ " \\;\\text{ given }\\; " ^ String.concat ",\\; " (List.map hyp hyps)
;;
