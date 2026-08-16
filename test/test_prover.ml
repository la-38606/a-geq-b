(** Tests for the automatic prover (Stage B: degree-<=2 via Gram + LDL^T).

    Soundness is the priority: the prover must never return a certificate the
    checker rejects, and must never "prove" a false or out-of-scope claim.
    Completeness is checked on the degree-<=2 targets Stage B is meant to
    handle. *)

open A_geq_b

(* Build the target polynomial p = A - B from a claim string. *)
let target (s : string) : Polynomial.t =
  match Parser.parse s with
  | Ok c -> snd (Normalizer.poly_of_claim c)
  | Error m -> Alcotest.failf "test setup: could not parse %S: %s" s m
;;

let provable (s : string) () =
  let p = target s in
  match Prover.prove p with
  | Prover.Proved cert ->
    (* The returned certificate must independently pass the trusted checker. *)
    Alcotest.(check bool)
      ("checker accepts prover output for: " ^ s)
      true
      (Checker.check_sos p cert)
  | Prover.No_certificate_found -> Alcotest.failf "expected to prove: %s" s
;;

let not_provable (s : string) () =
  let p = target s in
  match Prover.prove p with
  | Prover.No_certificate_found -> ()
  | Prover.Proved _ -> Alcotest.failf "prover unsoundly proved: %s" s
;;

(* Targets the prover should handle: degree-<=2 via the {1, x_i} Gram basis,
   and even-power forms via monomial-basis substitution. *)
let provable_cases =
  [ (* degree <= 2 *)
    "a^2 + b^2 >= 2*a*b"
  ; "a^2 + b^2 + c^2 >= a*b + b*c + c*a"
  ; "3*(a^2 + b^2 + c^2) >= (a + b + c)^2"
  ; "a^2 + 1 >= 2*a"
  ; "a^2 + 5*b^2 + 4*a*b >= 0"
  ; "x^2 + x*y + y^2 >= 0"
  ; "a^2 + 9*b^2 + 25*c^2 + 30*b*c >= 6*a*b + 10*a*c"
  ; "a^2 + b^2 + c^2 + d^2 >= a*b + b*c + c*d + d*a"
  ; "a^2 + b^2 + 1 >= a*b + a + b"
  ; "a^2 + b^2 + c^2 >= a*b + a*c"
  ; "a >= a" (* target 0: the empty SOS is a valid proof *)
  ; "5 >= 2" (* target 3: a nonnegative constant *)
  ; (* even-power / monomial-substitution forms *)
    "a^4 + b^4 >= 2*a^2*b^2"
  ; "a^4 + b^4 + c^4 >= a^2*b^2 + b^2*c^2 + c^2*a^2"
  ; "a^6 + b^6 >= 2*a^3*b^3"
  ; "a^8 + b^8 >= 2*a^4*b^4"
  ; "(a^2 + b^2)*(c^2 + d^2) >= (a*c + b*d)^2" (* Lagrange 2 *)
  ; "a^2*b^2 + b^2*c^2 + c^2*a^2 >= a^2*b*c + a*b^2*c + a*b*c^2"
  ; (* under-determined Gram, resolved by the bounded grid search *)
    "a^4 + 6*a^2*b^2 + b^4 >= 4*a^3*b + 4*a*b^3" (* (a-b)^4 *)
  ; "8*(a^4 + b^4) >= (a + b)^4"
  ; "a^4 + b^4 >= a^3*b + a*b^3" (* cyclic *)
  ; (* after clearing denominators *)
    "(a - b)^2 / 2 >= 0"
  ; "a^2/2 + 1/2 >= a"
  ]
;;

(* Must NOT be proved: false claims, out-of-scope (needs constraints), and
   higher-degree targets that need Gram freedom (SDP) not yet implemented. *)
let unprovable_cases =
  [ "a^2 + b^2 >= 3*a*b" (* false *)
  ; "a^2 + b^2 + c^2 >= 2*(a*b + b*c + c*a)" (* false *)
  ; "a^2 >= 1" (* false for all reals *)
  ; "a + b + c >= 3" (* out of scope: only true under a constraint *)
  ; "a >= 0" (* linear: not nonnegative for all reals *)
  ; "a^3 + b^3 + c^3 >= 3*a*b*c" (* degree 3: needs a >= 0 *)
  ; "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d" (* needs a wider Gram search (SDP) *)
  ; "a^4 + b^4 + c^4 >= a^2*b*c + a*b^2*c + a*b*c^2" (* many free params: SDP *)
  ]
;;

(* --- constrained (Positivstellensatz) prover ---------------------------- *)

(* Parse a constrained claim into its (hypotheses, target). *)
let constrained (s : string) : Constrained.hypothesis list * Polynomial.t =
  match Parser.parse s with
  | Ok c ->
    let ctx, p = Normalizer.poly_of_claim c in
    Constrained.hypotheses_of_claim ctx c, p
  | Error m -> Alcotest.failf "test setup: could not parse %S: %s" s m
;;

let provable_c (s : string) () =
  let hypotheses, p = constrained s in
  match Prover.prove_constrained ~hypotheses p with
  | Prover.Proved_constrained (_, cert) ->
    Alcotest.(check bool)
      ("checker accepts constrained proof for: " ^ s)
      true
      (Checker.check_constrained_ok ~hypotheses p cert)
  | Prover.No_constrained_certificate -> Alcotest.failf "expected to prove: %s" s
;;

let not_provable_c (s : string) () =
  let hypotheses, p = constrained s in
  match Prover.prove_constrained ~hypotheses p with
  | Prover.No_constrained_certificate -> ()
  | Prover.Proved_constrained _ -> Alcotest.failf "prover unsoundly proved: %s" s
;;

(* Handled by the constrained search: constant multipliers + an SOS base, and
   polynomial multipliers on equalities via reduction. *)
let provable_constrained_cases =
  [ "a^2 >= 0" (* no side conditions: base only *)
  ; "a + b >= 0 given a >= 0, b >= 0" (* pair of nonneg hypotheses *)
  ; "2*a + 3*b >= 0 given a >= 0, b >= 0" (* different constant multipliers *)
  ; "a + b + c >= 0 given a >= 0, b >= 0, c >= 0" (* uniform over 3 nonnegs *)
  ; "a >= 0 given a - 1 >= 0" (* nonneg hyp plus a constant base *)
  ; "a^2 + b^2 >= 2 given a*b = 1" (* equality hyp, constant multiplier *)
  ; "a^2 >= b^2 given a = b" (* equality, linear polynomial multiplier a+b *)
  ; "a^3 >= b^3 given a = b" (* equality, quadratic multiplier a^2+ab+b^2 *)
  ; "a*b >= 0 given a >= 0, b >= 0" (* product of two nonneg hypotheses (Schmüdgen) *)
  ]
;;

(* Beyond the search, so must return No_constrained_certificate — never a false
   proof: a claim a hypothesis does not support, and a triple product (only pairs
   of hypotheses are tried). *)
let unprovable_constrained_cases =
  [ "a >= 0 given b >= 0" (* irrelevant hypothesis; a may be negative *)
  ; "a*b*c >= 0 given a >= 0, b >= 0, c >= 0" (* needs the triple product a*b*c *)
  ]
;;

(* Contradictory hypothesis systems are detected by a Positivstellensatz
   refutation; consistent ones are not flagged. *)
let test_infeasible () =
  let infeasible s =
    let hypotheses, _ = constrained s in
    Prover.hypotheses_infeasible ~hypotheses
  in
  Alcotest.(check bool)
    "a - 1 >= 0, -a >= 0 is empty"
    true
    (infeasible "0 >= 1 given a - 1 >= 0, -a >= 0");
  Alcotest.(check bool)
    "a^2 + 1 = 0 is empty"
    true
    (infeasible "0 >= 1 given a^2 + 1 = 0");
  Alcotest.(check bool)
    "a = 0, a = 1 is empty"
    true
    (infeasible "0 >= 1 given a = 0, a = 1");
  Alcotest.(check bool)
    "a >= 0, b >= 0 is consistent"
    false
    (infeasible "a*b >= 0 given a >= 0, b >= 0");
  Alcotest.(check bool) "no hypotheses" false (infeasible "a^2 >= 0")
;;

(* A sparse high-degree many-variable target: its homogeneous half-degree basis
   is ~92000 monomials, which the Gram search must refuse (the basis cap) instead
   of enumerating. This asserts termination: prove returns quickly rather than
   hanging. (This particular family is in fact proved by the diagonal
   square-root path before the huge basis is reached; either way the result is
   sound, since any returned certificate is re-checked below.) *)
let test_large_basis_terminates () =
  let p = target "a^20 + b^20 + c^20 + d^20 + e^20 + f^20 >= 0" in
  match Prover.prove p with
  | Prover.No_certificate_found -> ()
  | Prover.Proved cert ->
    (* If it ever does return a certificate, it must still check out. *)
    Alcotest.(check bool)
      "any returned certificate still checks"
      true
      (Checker.check_sos p cert)
;;

let () =
  Alcotest.run
    "prover"
    [ ( "proves (degree <= 2)"
      , List.map (fun s -> Alcotest.test_case s `Quick (provable s)) provable_cases )
    ; ( "does not prove"
      , List.map (fun s -> Alcotest.test_case s `Quick (not_provable s)) unprovable_cases
      )
    ; ( "proves (constrained)"
      , List.map
          (fun s -> Alcotest.test_case s `Quick (provable_c s))
          provable_constrained_cases )
    ; ( "does not prove (constrained)"
      , List.map
          (fun s -> Alcotest.test_case s `Quick (not_provable_c s))
          unprovable_constrained_cases )
    ; ( "infeasibility"
      , [ Alcotest.test_case
            "contradictory vs consistent hypotheses"
            `Quick
            test_infeasible
        ] )
    ; ( "termination"
      , [ Alcotest.test_case
            "large-basis target terminates"
            `Quick
            test_large_basis_terminates
        ] )
    ]
;;
