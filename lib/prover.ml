(** The (untrusted) search engine.

    The prover looks for a sum-of-squares certificate for a target polynomial
    [p >= 0].  It is allowed to be heuristic, incomplete, and clever; anything
    it returns MUST still be validated by the trusted {!Checker} before the
    system claims [PROVED].

    {b Implemented so far:} Stage B — an exact solver for degree-≤2 targets via
    the Gram matrix and a rational LDLᵀ factorisation (see below).  Higher-degree
    search (pairwise-difference patterns, general Gram / SDP) is still future
    work; see CLAUDE.md, "Automatic prover stages".  This module also provides
    the hand-written "hello world" example used by the [demo] command. *)

type result =
  | Proved of Certificate.t
  | No_certificate_found  (** not disproof — just "this prover found nothing" *)

(* ---------------------------------------------------------------------- *)
(* Stage B: degree-<=2 targets via Gram matrix + rational LDL^T.           *)
(*                                                                         *)
(* Any polynomial p of degree <= 2 in variables x_0..x_{n-1} can be        *)
(* written as z^T Q z, where z = [1; x_0; ...; x_{n-1}] and Q is a         *)
(* SYMMETRIC matrix whose entries are forced by p's coefficients:          *)
(*                                                                         *)
(*     Q[0][0]   = constant term of p                                      *)
(*     Q[0][i+1] = Q[i+1][0] = (coeff of x_i) / 2                          *)
(*     Q[i+1][i+1] = coeff of x_i^2                                        *)
(*     Q[i+1][j+1] = Q[j+1][i+1] = (coeff of x_i x_j) / 2                   *)
(*                                                                         *)
(* p >= 0 for all reals iff this (unique) Q is positive semidefinite. If   *)
(* it is, a rational LDL^T factorisation Q = L D L^T (with D >= 0) yields   *)
(* the exact certificate p = sum_k D_k (L^T z)_k^2. The engine is          *)
(* untrusted; the resulting certificate is re-verified by {!Checker}.      *)
(* ---------------------------------------------------------------------- *)

exception Not_psd

(* Nonzero (variable index, exponent) pairs of a monomial, in index order. *)
let support (m : Monomial.t) : (int * int) list =
  List.mapi (fun i e -> (i, e)) m |> List.filter (fun (_, e) -> e <> 0)

let half = Rational.of_ints 1 2

(* Build the Gram matrix Q with z^T Q z = p over a chosen monomial basis
   z = [basis.(0); ...; basis.(r-1)], returning [None] if p cannot be written
   uniquely this way. The entry Q[i][j] is forced by the coefficient in p of the
   product monomial basis.(i) * basis.(j):

   - if two different index pairs produce the SAME monomial, the Gram is not
     uniquely determined (an SDP would be needed) -> [None];
   - if some monomial of p is not a product of two basis elements, p is not
     representable in this basis -> [None].

   When it succeeds the returned matrix is exact and satisfies z^T Q z = p
   identically (later re-checked by the trusted checker anyway). *)
let gram_of_basis (p : Polynomial.t) (basis : Monomial.t array) : Rational.t array array option =
  let r = Array.length basis in
  if r = 0 then None
  else begin
    (* product monomial -> the unique (i, j) pair that makes it *)
    let pair_of : (Monomial.t, int * int) Hashtbl.t = Hashtbl.create 64 in
    let collision = ref false in
    (try
       for i = 0 to r - 1 do
         for j = i to r - 1 do
           let pm = Monomial.mul basis.(i) basis.(j) in
           if Hashtbl.mem pair_of pm then (collision := true; raise Exit)
           else Hashtbl.add pair_of pm (i, j)
         done
       done
     with Exit -> ());
    let representable =
      (not !collision)
      && List.for_all (fun (mono, _) -> Hashtbl.mem pair_of mono) (Polynomial.to_list p)
    in
    if not representable then None
    else begin
      let q = Array.make_matrix r r Rational.zero in
      Hashtbl.iter
        (fun pm (i, j) ->
          let c = Polynomial.coeff pm p in
          if not (Rational.is_zero c) then
            if i = j then q.(i).(i) <- c
            else begin
              let h = Rational.mul half c in
              q.(i).(j) <- h;
              q.(j).(i) <- h
            end)
        pair_of;
      Some q
    end
  end

(* Rational LDL^T of a symmetric matrix. Returns [(l, d)] with unit
   lower-triangular [l] and diagonal [d] such that q = l * diag(d) * l^T.
   Raises {!Not_psd} if q is not positive semidefinite (a negative pivot, or a
   zero pivot with a nonzero column below it). *)
let ldlt (q : Rational.t array array) : Rational.t array array * Rational.t array =
  let m = Array.length q in
  let l = Array.make_matrix m m Rational.zero in
  for i = 0 to m - 1 do l.(i).(i) <- Rational.one done;
  let d = Array.make m Rational.zero in
  for k = 0 to m - 1 do
    let dk = ref q.(k).(k) in
    for j = 0 to k - 1 do
      dk := Rational.sub !dk (Rational.mul (Rational.mul l.(k).(j) l.(k).(j)) d.(j))
    done;
    d.(k) <- !dk;
    if Rational.sign !dk < 0 then raise Not_psd;
    for i = k + 1 to m - 1 do
      let num = ref q.(i).(k) in
      for j = 0 to k - 1 do
        num := Rational.sub !num (Rational.mul (Rational.mul l.(i).(j) l.(k).(j)) d.(j))
      done;
      if Rational.is_zero d.(k) then begin
        if not (Rational.is_zero !num) then raise Not_psd
        (* else l.(i).(k) stays zero *)
      end
      else l.(i).(k) <- Rational.div !num d.(k)
    done
  done;
  (l, d)

(* Certificate from an LDL^T factorisation over [basis]: column k contributes
   the term D_k * (sum_{j>=k} L[j][k] * basis.(j))^2, kept only when D_k > 0. *)
let certificate_of_ldlt (basis : Monomial.t array) (l : Rational.t array array)
    (d : Rational.t array) : Certificate.t =
  let m = Array.length d in
  let terms = ref [] in
  for k = m - 1 downto 0 do
    if Rational.is_positive d.(k) then begin
      let qk = ref Polynomial.zero in
      for j = k to m - 1 do
        if not (Rational.is_zero l.(j).(k)) then
          qk :=
            Polynomial.add !qk
              (Polynomial.scalar_mul l.(j).(k) (Polynomial.monomial basis.(j) Rational.one))
      done;
      terms := Certificate.term d.(k) !qk :: !terms
    end
  done;
  Certificate.make !terms

(* Try to prove p >= 0 using SOS over a specific monomial basis. *)
let prove_with_basis (p : Polynomial.t) (basis : Monomial.t array) : Certificate.t option =
  match gram_of_basis p basis with
  | None -> None
  | Some q -> (
      match ldlt q with
      | l, d -> Some (certificate_of_ldlt basis l d)
      | exception Not_psd -> None)

(* Candidate bases, tried in order of increasing generality. *)

(* Stage B: {1, x_0, ..., x_{n-1}} -- proves every degree-<=2 SOS target. *)
let quadratic_basis (p : Polynomial.t) : Monomial.t array =
  let n = Polynomial.num_vars p in
  Array.of_list (Monomial.one :: List.init n (fun i -> Monomial.var i))

(* Square-root monomials of the perfect-square monomials of p (those with all
   even exponents). With [~pure], keep only single-variable roots (x_i^k); this
   avoids spurious cross generators for pure even-power problems like
   a^4+b^4 >= 2a^2b^2. Without it, all roots are used (e.g. {ab, bc, ca} for
   sum a^2b^2 >= abc*sum a). *)
let square_root_basis ?(pure = false) (p : Polynomial.t) : Monomial.t array =
  let roots =
    List.filter_map
      (fun (mono, _) ->
        if List.for_all (fun e -> e mod 2 = 0) mono then
          let nu = Monomial.canonical (List.map (fun e -> e / 2) mono) in
          if pure && List.length (support nu) > 1 then None else Some nu
        else None)
      (Polynomial.to_list p)
  in
  Array.of_list (List.sort_uniq Monomial.compare roots)

(** Attempt to find an SOS certificate for [p >= 0]. Tries a sequence of
    monomial bases (degree-2 Gram, then even-power substitution bases); each
    candidate is re-checked by the trusted {!Checker}, so a bug in the search
    can only cause a missed proof, never a false one. *)
let prove (p : Polynomial.t) : result =
  let bases =
    [ quadratic_basis p; square_root_basis ~pure:true p; square_root_basis ~pure:false p ]
  in
  let rec go = function
    | [] -> No_certificate_found
    | basis :: rest -> (
        match prove_with_basis p basis with
        | Some cert when Checker.check_sos p cert -> Proved cert
        | _ -> go rest)
  in
  go bases

(* ---------------------------------------------------------------------- *)
(* Built-in "hello world" example:                                         *)
(*     a^2 + b^2 + c^2 >= a*b + b*c + c*a                                   *)
(* with the classic certificate                                            *)
(*     = 1/2 (a-b)^2 + 1/2 (b-c)^2 + 1/2 (a-c)^2.                           *)
(* Everything is built with the variable order [a; b; c] so the target and *)
(* the certificate share the same monomial indices.                        *)
(* ---------------------------------------------------------------------- *)

let hello_world_vars : string list = [ "a"; "b"; "c" ]

let hello_world_claim_string : string = "a^2 + b^2 + c^2 >= a*b + b*c + c*a"

(** The target polynomial [p = A - B], built through the {!Ast} + {!Normalizer}
    pipeline to exercise that path. *)
let hello_world_target () : Polynomial.t =
  let open Ast in
  let claim =
    { lhs = Add (Add (Pow (var "a", 2), Pow (var "b", 2)), Pow (var "c", 2));
      op = Ge;
      rhs = Add (Add (Mul (var "a", var "b"), Mul (var "b", var "c")), Mul (var "c", var "a")) }
  in
  snd (Normalizer.poly_of_claim ~context:hello_world_vars claim)

(** The classic three-square certificate. Note [(a-c)^2 = (c-a)^2]; we use
    [a-c] so it prints nicely. *)
let hello_world_certificate () : Certificate.t =
  let a = Polynomial.var 0 and b = Polynomial.var 1 and c = Polynomial.var 2 in
  let half = Rational.of_ints 1 2 in
  Certificate.make
    [ Certificate.term half (Polynomial.sub a b);
      Certificate.term half (Polynomial.sub b c);
      Certificate.term half (Polynomial.sub a c) ]
