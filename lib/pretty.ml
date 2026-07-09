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
    m
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
    m
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
