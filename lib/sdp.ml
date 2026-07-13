(** Untrusted numerical SDP path.

    The exact prover ({!Prover.prove}) resolves an under-determined Gram matrix
    only by a bounded grid search over at most two free entries. For the harder
    targets the Gram has more freedom than that, which is a genuine semidefinite
    feasibility problem. This module is the OCaml half of the pipeline the design
    calls for: emit the Gram SDP as JSON ({!problem_json}) for an external
    numerical solver (the Python code in [sdp/]), then round its floating-point
    solution back to an exact rational certificate ({!certificate_of_solution}).

    Nothing here is trusted. A numerically wrong Gram matrix simply fails to
    round to a positive-semidefinite rational one, or the certificate it yields
    is rejected by {!Checker.check_sos}; either way the result is [None], never a
    false proof. The trusted checker remains the sole authority. *)

(* Product monomial -> the basis index pairs (i <= j) whose product is it. This
   is the shared structure of every Gram matrix over the basis: entry [(i, j)]
   contributes to the coefficient of [basis.(i) * basis.(j)]. *)
let pairs_of (basis : Monomial.t array) : (Monomial.t, (int * int) list) Hashtbl.t =
  let r = Array.length basis in
  let tbl = Hashtbl.create 64 in
  for i = 0 to r - 1 do
    for j = i to r - 1 do
      let pm = Monomial.mul basis.(i) basis.(j) in
      let cur =
        try Hashtbl.find tbl pm with
        | Not_found -> []
      in
      Hashtbl.replace tbl pm ((i, j) :: cur)
    done
  done;
  tbl
;;

(* z^T Q z = sum_i Q_ii z_i^2 + 2 sum_{i<j} Q_ij z_i z_j, so an off-diagonal
   entry carries weight 2 in each coefficient constraint, a diagonal one weight 1. *)
let weight ((i, j) : int * int) : Rational.t =
  if i = j then Rational.one else Rational.of_int 2
;;

(** The Gram SDP for [p >= 0] as JSON:
    {v
      { "dim": r,
        "basis": [[e, ..], ..],
        "constraints": [ { "terms": [[i, j], ..], "rhs": "p/q" }, .. ] }
    v}
    Each constraint reads [sum_{(i,j) in terms} w_ij * Q_ij = rhs] with [w_ij] as
    in {!weight}. Together with [Q >= 0] (imposed by the solver) this says
    exactly "[Q] is a positive-semidefinite Gram matrix of [p]". Every product
    monomial gets a constraint, including those absent from [p] (right-hand side
    zero), so the off-support entries are pinned too. *)
let problem_json (p : Polynomial.t) : Yojson.Safe.t =
  let basis = Prover.sdp_basis p in
  let pairs = pairs_of basis in
  let constraints =
    Hashtbl.fold
      (fun mu ijs acc ->
         let terms = List.map (fun (i, j) -> `List [ `Int i; `Int j ]) ijs in
         let rhs = Rational.to_string (Polynomial.coeff mu p) in
         `Assoc [ "terms", `List terms; "rhs", `String rhs ] :: acc)
      pairs
      []
  in
  let basis_json =
    Array.to_list basis
    |> List.map (fun m -> `List (List.map (fun e -> `Int e) (Monomial.exponents m)))
  in
  `Assoc
    [ "dim", `Int (Array.length basis)
    ; "basis", `List basis_json
    ; "constraints", `List constraints
    ]
;;

(* Build the exact rational Gram matrix determined by rational values on the free
   entries. For each product monomial the pairs beyond the first are "free" and
   set directly from [value]; the first ("dependent") pair absorbs whatever the
   coefficient constraint requires. So [z^T Q z = p] holds exactly for ANY choice
   of free values -- the numbers only decide whether Q is PSD. (This mirrors the
   completion the grid search performs in {!Prover}.) *)
let gram_of_free
      (p : Polynomial.t)
      (basis : Monomial.t array)
      (pairs : (Monomial.t, (int * int) list) Hashtbl.t)
      (value : int * int -> Rational.t)
  : Rational.t array array
  =
  let r = Array.length basis in
  let q = Array.make_matrix r r Rational.zero in
  let set (i, j) v =
    q.(i).(j) <- v;
    q.(j).(i) <- v
  in
  Hashtbl.iter
    (fun mu ijs ->
       match ijs with
       | [] -> ()
       | dep :: frees ->
         let used =
           List.fold_left
             (fun acc e ->
                let v = value e in
                set e v;
                Rational.add acc (Rational.mul (weight e) v))
             Rational.zero
             frees
         in
         let residual = Rational.sub (Polynomial.coeff mu p) used in
         set dep (Rational.div residual (weight dep)))
    pairs;
  q
;;

(* Nearest rational to [x] with denominator [d]. *)
let round_to (d : int) (x : float) : Rational.t =
  Rational.of_ints (int_of_float (Float.round (x *. float_of_int d))) d
;;

(* Common denominators tried, smallest first. SOS certificates that arise in
   practice have small rational Gram entries, so a modest denominator recovers
   them; a numerical solution near the true one rounds to it exactly. *)
let denominators = [ 1; 2; 3; 4; 6; 8; 12; 24; 48; 120; 360; 720; 2520; 5040 ]

(** Turn a numerical Gram solution [q] -- indexed by {!Prover.sdp_basis} [p], the
    same basis {!problem_json} emitted -- into an exact SOS certificate for
    [p >= 0], or [None]. For each candidate denominator it rounds the free
    entries, completes the dependent ones so [z^T Q z = p] holds to the letter,
    reads off the SOS by exact LDLᵀ, and keeps the first certificate the trusted
    {!Checker} accepts. *)
let certificate_of_solution (p : Polynomial.t) (q : float array array)
  : Certificate.t option
  =
  let basis = Prover.sdp_basis p in
  let r = Array.length basis in
  if Array.length q <> r || Array.exists (fun row -> Array.length row <> r) q
  then None
  else (
    let pairs = pairs_of basis in
    let try_denominator d =
      let value (i, j) = round_to d q.(i).(j) in
      let gram = gram_of_free p basis pairs value in
      match Prover.certificate_of_gram basis gram with
      | Some cert when Checker.check_sos p cert -> Some cert
      | _ -> None
    in
    List.find_map try_denominator denominators)
;;
