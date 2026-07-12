(** The (untrusted) search engine.

    The prover looks for a sum-of-squares certificate for a target polynomial
    [p >= 0].  It is allowed to be heuristic, incomplete, and clever; anything
    it returns MUST still be validated by the trusted {!Checker} before the
    system claims [PROVED].

    {b Implemented so far:} an exact SOS solver based on the Gram matrix and a
    rational LDLᵀ factorisation (see below).  It tries a sequence of monomial
    bases — the degree-2 basis [{1, x_i}], even-power / product substitution
    bases, and the full degree-[d] basis for homogeneous targets — and resolves
    an under-determined Gram (an SDP) by a bounded rational grid search over up
    to two free entries.  Targets needing a wider multi-variable semidefinite
    search are still future work; see CLAUDE.md, "Automatic prover stages".  This
    module also provides the hand-written "hello world" example used by the
    [demo] command. *)

type result =
  | Proved of Certificate.t
  | No_certificate_found (** not disproof — just "this prover found nothing" *)

type constrained_result =
  | Proved_constrained of Constrained.t
  | No_constrained_certificate

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
  List.mapi (fun i e -> i, e) (Monomial.exponents m) |> List.filter (fun (_, e) -> e <> 0)
;;

(* Candidate Gram matrices Q with z^T Q z = p over a chosen monomial basis
   z = [basis.(0); ...; basis.(r-1)].

   Matching coefficients gives, for each product monomial m = basis_i*basis_j,
   the linear constraint  sum over pairs (i,j) with basis_i*basis_j = m of
   w_ij * Q[i][j] = coeff_p(m),  where w_ij = 1 if i=j else 2. Then:

   - if p has a monomial not producible as any such product, p is not
     representable in this basis -> no candidates;
   - if every product monomial is made by a UNIQUE pair, Q is forced -> one
     candidate;
   - otherwise the Gram is under-determined (an SDP). Each product monomial with
     k >= 2 pairs contributes k-1 free entries; if there are at most 2 free
     entries in total we enumerate a bounded rational grid of values for them,
     solving the remaining "dependent" entry from the constraint. More than 2
     free entries -> we give up (no candidates).

   Every returned matrix satisfies z^T Q z = p exactly by construction (the
   trusted checker re-verifies anyway); only its positive-semidefiniteness,
   tested later by LDL^T, distinguishes a real certificate. *)

(* Rational grid { n/2 : -12 <= n <= 12 } for free Gram entries. *)
let grid : Rational.t list = List.init 25 (fun n -> Rational.of_ints (n - 12) 2)

let gram_candidates (p : Polynomial.t) (basis : Monomial.t array)
  : Rational.t array array list
  =
  let r = Array.length basis in
  if r = 0
  then []
  else (
    (* product monomial -> list of (i, j) pairs (i <= j) that build it *)
    let pairs_of : (Monomial.t, (int * int) list) Hashtbl.t = Hashtbl.create 64 in
    for i = 0 to r - 1 do
      for j = i to r - 1 do
        let pm = Monomial.mul basis.(i) basis.(j) in
        let cur =
          try Hashtbl.find pairs_of pm with
          | Not_found -> []
        in
        Hashtbl.replace pairs_of pm ((i, j) :: cur)
      done
    done;
    let representable =
      List.for_all (fun (mono, _) -> Hashtbl.mem pairs_of mono) (Polynomial.to_list p)
    in
    if not representable
    then []
    else (
      let weight (i, j) = if i = j then Rational.one else Rational.of_int 2 in
      (* free entries: for each product monomial, all pairs beyond the first *)
      let free =
        Hashtbl.fold
          (fun _ ps acc ->
             match ps with
             | _ :: rest -> rest @ acc
             | [] -> acc)
          pairs_of
          []
      in
      if List.length free > 2
      then []
      else (
        (* Build a Gram from a value assigned to each free entry. *)
        let build (assign : int * int -> Rational.t) : Rational.t array array =
          let q = Array.make_matrix r r Rational.zero in
          let set (i, j) v =
            q.(i).(j) <- v;
            q.(j).(i) <- v
          in
          Hashtbl.iter
            (fun pm ps ->
               match ps with
               | [] -> ()
               | dep :: frees ->
                 let c = Polynomial.coeff pm p in
                 (* place free entries, accumulating their weighted contribution *)
                 let used =
                   List.fold_left
                     (fun acc e ->
                        let v = assign e in
                        set e v;
                        Rational.add acc (Rational.mul (weight e) v))
                     Rational.zero
                     frees
                 in
                 (* the dependent entry absorbs the rest of the constraint *)
                 set dep (Rational.div (Rational.sub c used) (weight dep)))
            pairs_of;
          q
        in
        match free with
        | [] -> [ build (fun _ -> Rational.zero) ]
        | [ e1 ] ->
          List.map (fun g1 -> build (fun e -> if e = e1 then g1 else Rational.zero)) grid
        | [ e1; e2 ] ->
          List.concat_map
            (fun g1 ->
               List.map
                 (fun g2 ->
                    build (fun e ->
                      if e = e1 then g1 else if e = e2 then g2 else Rational.zero))
                 grid)
            grid
        | _ -> [])))
;;

(* Rational LDL^T of a symmetric matrix. Returns [(l, d)] with unit
   lower-triangular [l] and diagonal [d] such that q = l * diag(d) * l^T.
   Raises {!Not_psd} if q is not positive semidefinite (a negative pivot, or a
   zero pivot with a nonzero column below it). *)
let ldlt (q : Rational.t array array) : Rational.t array array * Rational.t array =
  let m = Array.length q in
  let l = Array.make_matrix m m Rational.zero in
  for i = 0 to m - 1 do
    l.(i).(i) <- Rational.one
  done;
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
      if Rational.is_zero d.(k)
      then (
        if not (Rational.is_zero !num) then raise Not_psd (* else l.(i).(k) stays zero *))
      else l.(i).(k) <- Rational.div !num d.(k)
    done
  done;
  l, d
;;

(* Certificate from an LDL^T factorisation over [basis]: column k contributes
   the term D_k * (sum_{j>=k} L[j][k] * basis.(j))^2, kept only when D_k > 0. *)
let certificate_of_ldlt
      (basis : Monomial.t array)
      (l : Rational.t array array)
      (d : Rational.t array)
  : Certificate.t
  =
  let m = Array.length d in
  let terms = ref [] in
  for k = m - 1 downto 0 do
    if Rational.is_positive d.(k)
    then (
      let qk = ref Polynomial.zero in
      for j = k to m - 1 do
        if not (Rational.is_zero l.(j).(k))
        then
          qk
          := Polynomial.add
               !qk
               (Polynomial.scalar_mul
                  l.(j).(k)
                  (Polynomial.monomial basis.(j) Rational.one))
      done;
      terms := Certificate.term d.(k) !qk :: !terms)
  done;
  Certificate.make !terms
;;

(* Try to prove p >= 0 using SOS over a specific monomial basis: return the
   certificate from the first candidate Gram matrix that is PSD. *)
let prove_with_basis (p : Polynomial.t) (basis : Monomial.t array) : Certificate.t option =
  let rec first = function
    | [] -> None
    | q :: rest ->
      (match ldlt q with
       | l, d -> Some (certificate_of_ldlt basis l d)
       | exception Not_psd -> first rest)
  in
  first (gram_candidates p basis)
;;

(* Candidate bases, tried in order of increasing generality. *)

(* Stage B: {1, x_0, ..., x_{n-1}} -- proves every degree-<=2 SOS target. *)
let quadratic_basis (p : Polynomial.t) : Monomial.t array =
  let n = Polynomial.num_vars p in
  Array.of_list (Monomial.one :: List.init n (fun i -> Monomial.var i))
;;

(* Square-root monomials of the perfect-square monomials of p (those with all
   even exponents). With [~pure], keep only single-variable roots (x_i^k); this
   avoids spurious cross generators for pure even-power problems like
   a^4+b^4 >= 2a^2b^2. Without it, all roots are used (e.g. {ab, bc, ca} for
   sum a^2b^2 >= abc*sum a). *)
let square_root_basis ?(pure = false) (p : Polynomial.t) : Monomial.t array =
  let roots =
    List.filter_map
      (fun (mono, _) ->
         let es = Monomial.exponents mono in
         if List.for_all (fun e -> e mod 2 = 0) es
         then (
           let nu = Monomial.canonical (List.map (fun e -> e / 2) es) in
           if pure && List.length (support nu) > 1 then None else Some nu)
         else None)
      (Polynomial.to_list p)
  in
  Array.of_list (List.sort_uniq Monomial.compare roots)
;;

let is_homogeneous (p : Polynomial.t) : bool =
  match Polynomial.to_list p with
  | [] -> true
  | (m0, _) :: rest ->
    let d0 = Monomial.degree m0 in
    List.for_all (fun (m, _) -> Monomial.degree m = d0) rest
;;

(* Per-variable maximum exponent occurring in p (a loose cap for basis size). *)
let max_exponents (p : Polynomial.t) (n : int) : int array =
  let mx = Array.make (max n 1) 0 in
  List.iter
    (fun (m, _) ->
       List.iteri (fun i e -> if e > mx.(i) then mx.(i) <- e) (Monomial.exponents m))
    (Polynomial.to_list p);
  mx
;;

(* All monomials of total degree exactly [d] over [n] variables, with each
   exponent capped by [cap.(i)]. *)
let monomials_of_degree (n : int) (d : int) (cap : int array) : Monomial.t list =
  let acc = ref [] in
  let rec go i rem cur =
    if i = n
    then (if rem = 0 then acc := Monomial.canonical (List.rev cur) :: !acc)
    else
      for e = 0 to min rem cap.(i) do
        go (i + 1) (rem - e) (e :: cur)
      done
  in
  go 0 d [];
  !acc
;;

(* For a homogeneous target of even degree 2d, the full degree-d monomial basis.
   Needed when a required generator (e.g. ab for a^4+b^4 >= a^3b+ab^3) is not a
   square root of any monomial of p. Empty for non-homogeneous or odd-degree p. *)
let homogeneous_basis (p : Polynomial.t) : Monomial.t array =
  let deg = Polynomial.degree p in
  if deg = 0 || deg mod 2 <> 0 || not (is_homogeneous p)
  then [||]
  else (
    let n = Polynomial.num_vars p in
    Array.of_list (monomials_of_degree n (deg / 2) (max_exponents p n)))
;;

(** Attempt to find an SOS certificate for [p >= 0]. Tries a sequence of
    monomial bases (degree-2 Gram, even-power substitution bases, then the full
    degree-d basis for homogeneous targets). Under-determined Gram matrices are
    resolved by a bounded rational grid search (see {!gram_candidates}). Every
    candidate is re-checked by the trusted {!Checker}, so a bug in the search can
    only cause a missed proof, never a false one. *)
let prove (p : Polynomial.t) : result =
  let bases =
    [ quadratic_basis p
    ; square_root_basis ~pure:true p
    ; square_root_basis ~pure:false p
    ; homogeneous_basis p
    ]
  in
  let rec go = function
    | [] -> No_certificate_found
    | basis :: rest ->
      (match prove_with_basis p basis with
       | Some cert when Checker.check_sos p cert -> Proved cert
       | _ -> go rest)
  in
  go bases
;;

(* ---------------------------------------------------------------------- *)
(* Constrained search (Positivstellensatz), first cut.                     *)
(*                                                                         *)
(* We look for   p = base + sum_i c_i g_i + sum_j d_j h_j   with CONSTANT  *)
(* multipliers: c_i >= 0 on the nonnegative hypotheses g_i, and d_j of any *)
(* sign on the vanishing hypotheses h_j.  For a fixed choice of constants  *)
(* the residual  r = p - sum c_i g_i - sum d_j h_j  must be a sum of       *)
(* squares, which we hand to the unconstrained {!prove}.  The constants    *)
(* are searched over a bounded grid, with at most two hypotheses active at *)
(* once (plus a uniform choice across all nonnegative hypotheses, which    *)
(* catches the common symmetric case).  A polynomial (non-constant)        *)
(* multiplier — needed e.g. for [a^3 >= b^3 given a = b] — is future work. *)
(* Every assembled certificate is re-checked by the trusted {!Checker}.    *)
(* ---------------------------------------------------------------------- *)

let nonneg_muls : Rational.t list =
  [ Rational.one
  ; Rational.of_int 2
  ; Rational.of_int 3
  ; Rational.of_ints 1 2
  ; Rational.of_ints 3 2
  ]
;;

let signed_muls : Rational.t list =
  List.concat_map (fun q -> [ q; Rational.neg q ]) nonneg_muls
;;

let hyp_poly : Constrained.hypothesis -> Polynomial.t = function
  | Nonneg g -> g
  | Zero h -> h
;;

let mul_values : Constrained.hypothesis -> Rational.t list = function
  | Nonneg _ -> nonneg_muls
  | Zero _ -> signed_muls
;;

(* The certificate product for scaling [hyp] by the constant [v]. *)
let product_of ((hyp, v) : Constrained.hypothesis * Rational.t) : Constrained.product =
  match hyp with
  | Nonneg g ->
    Constrained.times_nonneg ~multiplier:[ Certificate.term v Polynomial.one ] ~nonneg:g
  | Zero h -> Constrained.times_zero ~multiplier:(Polynomial.const v) ~zero:h
;;

(* Reduce [target] by the active (hypothesis, constant) assignments, prove the
   residual as an SOS base, assemble the certificate, and re-check it. *)
let try_assignment
      ~(hypotheses : Constrained.hypothesis list)
      (target : Polynomial.t)
      (active : (Constrained.hypothesis * Rational.t) list)
  : Constrained.t option
  =
  let subtract =
    List.fold_left
      (fun acc (hyp, v) -> Polynomial.add acc (Polynomial.scalar_mul v (hyp_poly hyp)))
      Polynomial.zero
      active
  in
  match prove (Polynomial.sub target subtract) with
  | No_certificate_found -> None
  | Proved base ->
    let cert = Constrained.make ~base ~products:(List.map product_of active) in
    if Checker.check_constrained_ok ~hypotheses target cert then Some cert else None
;;

(* Unordered pairs of a list, preserving element identity. *)
let rec pairs : 'a list -> ('a * 'a) list = function
  | [] -> []
  | x :: xs -> List.map (fun y -> x, y) xs @ pairs xs
;;

(* Search for a certificate with CONSTANT hypothesis-multipliers: base SOS plus a
   grid of constant multiples of the hypotheses (see the note above). *)
let prove_by_constants ~(hypotheses : Constrained.hypothesis list) (target : Polynomial.t)
  : constrained_result
  =
  (* Candidate active-assignments, cheapest first. *)
  let none = [ [] ] in
  let uniform =
    let nonnegs =
      List.filter
        (function
          | Constrained.Nonneg _ -> true
          | Zero _ -> false)
        hypotheses
    in
    if List.length nonnegs >= 2
    then List.map (fun c -> List.map (fun h -> h, c) nonnegs) nonneg_muls
    else []
  in
  let singles =
    List.concat_map (fun h -> List.map (fun v -> [ h, v ]) (mul_values h)) hypotheses
  in
  let doubles =
    List.concat_map
      (fun (h1, h2) ->
         List.concat_map
           (fun v1 -> List.map (fun v2 -> [ h1, v1; h2, v2 ]) (mul_values h2))
           (mul_values h1))
      (pairs hypotheses)
  in
  let rec go = function
    | [] -> No_constrained_certificate
    | active :: rest ->
      (match try_assignment ~hypotheses target active with
       | Some cert -> Proved_constrained cert
       | None -> go rest)
  in
  go (none @ uniform @ singles @ doubles)
;;

(* --- polynomial multipliers on equality hypotheses --------------------- *)
(*                                                                         *)
(* For a vanishing hypothesis h = 0, ANY polynomial multiple lambda*h is 0 *)
(* on the domain, so we may reduce the target modulo h by exact polynomial *)
(* division: target = q*h + r, and q is exactly the multiplier we want. We *)
(* then only need the remainder r to be provable (SOS, possibly using the  *)
(* nonnegative hypotheses).  Division is under {!Monomial.compare}, which  *)
(* is the lexicographic order — a genuine (multiplication-compatible,      *)
(* well-founded) monomial order, so the reduction terminates.  The trusted *)
(* checker still re-verifies everything, so a bug here only misses proofs. *)

(* Term of [p] with the largest monomial under {!Monomial.compare}. *)
let leading (p : Polynomial.t) : (Monomial.t * Rational.t) option =
  List.fold_left
    (fun acc (m, c) ->
       match acc with
       | Some (mm, _) when Monomial.compare m mm <= 0 -> acc
       | _ -> Some (m, c))
    None
    (Polynomial.to_list p)
;;

(* Does monomial [a] divide monomial [b] (exponent-wise, padding with zeros)? *)
let mono_divides (a : Monomial.t) (b : Monomial.t) : bool =
  let rec go xs ys =
    match xs, ys with
    | [], _ -> true
    | _ :: _, [] -> false
    | x :: xs, y :: ys -> x <= y && go xs ys
  in
  go (Monomial.exponents a) (Monomial.exponents b)
;;

(* [b / a] as a monomial ([a] must divide [b]). *)
let mono_div (b : Monomial.t) (a : Monomial.t) : Monomial.t =
  let rec go ys xs =
    match ys, xs with
    | ys, [] -> ys
    | [], _ -> []
    | y :: ys, x :: xs -> (y - x) :: go ys xs
  in
  Monomial.canonical (go (Monomial.exponents b) (Monomial.exponents a))
;;

(* Divide [f] by a nonzero [g]: returns [(q, r)] with [f = q*g + r] and no term
   of [r] divisible by the leading monomial of [g]. *)
let reduce (f : Polynomial.t) (g : Polynomial.t) : Polynomial.t * Polynomial.t =
  match leading g with
  | None -> Polynomial.zero, f (* g = 0: no reduction *)
  | Some (lm_g, lc_g) ->
    let rec go p q r =
      match leading p with
      | None -> q, r
      | Some (lm_p, lc_p) ->
        if mono_divides lm_g lm_p
        then (
          let factor =
            Polynomial.monomial (mono_div lm_p lm_g) (Rational.div lc_p lc_g)
          in
          go (Polynomial.sub p (Polynomial.mul factor g)) (Polynomial.add q factor) r)
        else (
          let lt = Polynomial.monomial lm_p lc_p in
          go (Polynomial.sub p lt) q (Polynomial.add r lt))
    in
    go f Polynomial.zero Polynomial.zero
;;

(* Reduce [target] successively by the equality-hypothesis polynomials, returning
   the [Times_zero] products for the nonzero quotients and the final remainder;
   [target = sum (q_j * h_j) + remainder]. *)
let reduce_by_zeros (target : Polynomial.t) (zeros : Polynomial.t list)
  : Constrained.product list * Polynomial.t
  =
  List.fold_left
    (fun (products, current) h ->
       if Polynomial.is_zero h
       then products, current
       else (
         let q, r = reduce current h in
         let products =
           if Polynomial.is_zero q
           then products
           else Constrained.times_zero ~multiplier:q ~zero:h :: products
         in
         products, r))
    ([], target)
    zeros
;;

let nonneg_polys (hypotheses : Constrained.hypothesis list) : Polynomial.t list =
  List.filter_map
    (function
      | Constrained.Nonneg g -> Some g
      | Zero _ -> None)
    hypotheses
;;

(* Polynomial multipliers on equalities: reduce the target modulo the equality
   hypotheses, then prove the remainder over the nonnegative hypotheses. *)
let prove_by_reduction ~(hypotheses : Constrained.hypothesis list) (target : Polynomial.t)
  : constrained_result
  =
  let zeros =
    List.filter_map
      (function
        | Constrained.Zero h -> Some h
        | Nonneg _ -> None)
      hypotheses
  in
  match zeros with
  | [] -> No_constrained_certificate
  | _ :: _ ->
    let nonnegs =
      List.filter
        (function
          | Constrained.Nonneg _ -> true
          | Zero _ -> false)
        hypotheses
    in
    let eq_products, remainder = reduce_by_zeros target zeros in
    (match prove_by_constants ~hypotheses:nonnegs remainder with
     | No_constrained_certificate -> No_constrained_certificate
     | Proved_constrained inner ->
       let cert =
         Constrained.make ~base:inner.base ~products:(inner.products @ eq_products)
       in
       if Checker.check_constrained_ok ~hypotheses target cert
       then Proved_constrained cert
       else No_constrained_certificate)
;;

(* Schmüdgen products: for each pair of nonnegative hypotheses g_i, g_j and a
   constant c >= 0, subtract c * g_i * g_j and try to prove the remainder as an
   SOS base. The certificate term is [c] (a degree-0 SOS) times the product
   [g_i * g_j] of two nonnegative hypotheses. *)
let prove_by_products ~(hypotheses : Constrained.hypothesis list) (target : Polynomial.t)
  : constrained_result
  =
  let candidates =
    List.concat_map
      (fun (gi, gj) ->
         let product = Polynomial.mul gi gj in
         List.map (fun c -> c, gi, gj, product) nonneg_muls)
      (pairs (nonneg_polys hypotheses))
  in
  let rec go = function
    | [] -> No_constrained_certificate
    | (c, gi, gj, product) :: rest ->
      let residual = Polynomial.sub target (Polynomial.scalar_mul c product) in
      (match prove residual with
       | No_certificate_found -> go rest
       | Proved base ->
         let cert =
           Constrained.make
             ~base
             ~products:
               [ Constrained.times_product
                   ~multiplier:[ Certificate.term c Polynomial.one ]
                   ~factors:[ gi; gj ]
               ]
         in
         if Checker.check_constrained_ok ~hypotheses target cert
         then Proved_constrained cert
         else go rest)
  in
  go candidates
;;

(** Attempt a Positivstellensatz certificate that [target >= 0] on the region cut
    out by [hypotheses], trying in turn: constant hypothesis-multipliers with an
    SOS base ({!prove}); polynomial multipliers on the equality hypotheses (by
    reduction modulo the constraint); and products of two nonnegative hypotheses
    (Schmüdgen). Every candidate is re-checked by the trusted {!Checker}, so the
    search can only miss a proof, never produce a false one. *)
let prove_constrained ~(hypotheses : Constrained.hypothesis list) (target : Polynomial.t)
  : constrained_result
  =
  let ( <|> ) first next =
    match first with
    | Proved_constrained _ as proved -> proved
    | No_constrained_certificate -> next ()
  in
  prove_by_constants ~hypotheses target
  <|> (fun () -> prove_by_reduction ~hypotheses target)
  <|> fun () -> prove_by_products ~hypotheses target
;;

(** [true] iff the hypotheses are provably contradictory, i.e. cut out an EMPTY
    region. Detected by finding a Positivstellensatz refutation: a certificate
    that [-1 >= 0] on the region. If a feasible point existed, the polynomial
    identity [-1 = base + sum sigma_i g_i + sum lambda_j h_j] could not hold (it
    would force [-1 >= 0] there), so a certificate the trusted checker accepts
    exists only when the region is empty. Incomplete (bounded by the search), so
    a [false] result means "not shown", not "consistent". *)
let hypotheses_infeasible ~(hypotheses : Constrained.hypothesis list) : bool =
  match hypotheses with
  | [] -> false
  | _ :: _ ->
    (match prove_constrained ~hypotheses (Polynomial.const (Rational.of_int (-1))) with
     | Proved_constrained _ -> true
     | No_constrained_certificate -> false)
;;

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
    { lhs = Add (Add (Pow (var "a", 2), Pow (var "b", 2)), Pow (var "c", 2))
    ; op = Ge
    ; rhs =
        Add (Add (Mul (var "a", var "b"), Mul (var "b", var "c")), Mul (var "c", var "a"))
    ; hyps = []
    }
  in
  snd (Normalizer.poly_of_claim ~context:hello_world_vars claim)
;;

(** The classic three-square certificate. Note [(a-c)^2 = (c-a)^2]; we use
    [a-c] so it prints nicely. *)
let hello_world_certificate () : Certificate.t =
  let a = Polynomial.var 0
  and b = Polynomial.var 1
  and c = Polynomial.var 2 in
  let half = Rational.of_ints 1 2 in
  Certificate.make
    [ Certificate.term half (Polynomial.sub a b)
    ; Certificate.term half (Polynomial.sub b c)
    ; Certificate.term half (Polynomial.sub a c)
    ]
;;
