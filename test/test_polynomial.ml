(** Tests for the exact polynomial core: arithmetic laws, normalisation, and
    equality by canonical form. *)

open A_geq_b

(* Variable order for readable failure messages. *)
let vars = [ "a"; "b"; "c"; "d" ]

(* An Alcotest "testable" for polynomials: equality by normal form, pretty
   printing for diagnostics. *)
let poly =
  Alcotest.testable
    (fun fmt p -> Format.fprintf fmt "%s" (Pretty.string_of_poly vars p))
    Polynomial.equal
;;

let check = Alcotest.check poly

(* Shorthands. *)
let a = Polynomial.var 0
let b = Polynomial.var 1
let c = Polynomial.var 2
let k n = Polynomial.of_int n
let ( +! ) = Polynomial.add
let ( -! ) = Polynomial.sub
let ( *! ) = Polynomial.mul

(* A small deterministic bag of sample polynomials to exercise algebraic laws
   over (no randomness, so runs are reproducible). *)
let samples =
  [ Polynomial.zero
  ; Polynomial.one
  ; a
  ; b
  ; a +! b
  ; a -! c
  ; (a *! b) -! c
  ; (k 2 *! Polynomial.pow a 2) -! (k 3 *! b) +! Polynomial.one
  ; Polynomial.scalar_mul (Rational.of_ints 1 2) (a +! b +! c)
  ]
;;

let for_all_pairs f = List.iter (fun p -> List.iter (fun q -> f p q) samples) samples

let for_all_triples f =
  List.iter
    (fun p -> List.iter (fun q -> List.iter (fun r -> f p q r) samples) samples)
    samples
;;

(* --- individual behaviours --------------------------------------------- *)

let test_add_combines_like_terms () =
  check "a + a = 2a" (Polynomial.scalar_mul (Rational.of_int 2) a) (a +! a)
;;

let test_zero_terms_removed () =
  Alcotest.(check bool)
    "a - a is the empty (zero) polynomial"
    true
    (Polynomial.is_zero (a -! a))
;;

let test_mul_expands () =
  (* (a - b)^2 = a^2 - 2ab + b^2 *)
  let lhs = Polynomial.pow (a -! b) 2 in
  let ab = a *! b in
  let rhs =
    Polynomial.pow a 2
    -! Polynomial.scalar_mul (Rational.of_int 2) ab
    +! Polynomial.pow b 2
  in
  check "(a-b)^2 = a^2 - 2ab + b^2" rhs lhs
;;

let test_pow () =
  check "a^3 = a*a*a" (a *! a *! a) (Polynomial.pow a 3);
  check "a^0 = 1" Polynomial.one (Polynomial.pow a 0)
;;

let test_equal_ignores_construction () =
  (* Same polynomial reached two different ways. *)
  let p1 = (a +! b) *! (a -! b) in
  let p2 = Polynomial.pow a 2 -! Polynomial.pow b 2 in
  check "(a+b)(a-b) = a^2 - b^2" p2 p1
;;

let test_degree_and_vars () =
  Alcotest.(check int)
    "deg((a-b)^2) = 2"
    2
    (Polynomial.degree (Polynomial.pow (a -! b) 2));
  Alcotest.(check int) "deg(0) = 0" 0 (Polynomial.degree Polynomial.zero);
  Alcotest.(check int) "num_vars(a*c) = 3" 3 (Polynomial.num_vars (a *! c))
;;

(* --- algebraic laws over the sample set -------------------------------- *)

let test_add_identity () =
  List.iter (fun p -> check "p + 0 = p" p (p +! Polynomial.zero)) samples
;;

let test_sub_self () =
  List.iter
    (fun p -> Alcotest.(check bool) "p - p = 0" true (Polynomial.is_zero (p -! p)))
    samples
;;

let test_mul_identity () =
  List.iter (fun p -> check "p * 1 = p" p (p *! Polynomial.one)) samples
;;

let test_mul_commutes () = for_all_pairs (fun p q -> check "p*q = q*p" (p *! q) (q *! p))

let test_add_assoc () =
  for_all_triples (fun p q r -> check "(p+q)+r = p+(q+r)" (p +! q +! r) (p +! (q +! r)))
;;

let test_distributes () =
  for_all_triples (fun p q r ->
    check "p*(q+r) = p*q + p*r" (p *! (q +! r)) ((p *! q) +! (p *! r)))
;;

(* --- normaliser (AST -> polynomial) ------------------------------------ *)

let test_normalizer () =
  (* a^2 + b^2 built from an AST should equal the hand-built polynomial. *)
  let e = Ast.(Add (Pow (var "a", 2), Pow (var "b", 2))) in
  let built = Normalizer.poly_of_expr [ "a"; "b" ] e in
  check "normalizer builds a^2 + b^2" (Polynomial.pow a 2 +! Polynomial.pow b 2) built
;;

let () =
  Alcotest.run
    "polynomial"
    [ ( "operations"
      , [ Alcotest.test_case "add combines like terms" `Quick test_add_combines_like_terms
        ; Alcotest.test_case "zero terms removed" `Quick test_zero_terms_removed
        ; Alcotest.test_case "multiplication expands" `Quick test_mul_expands
        ; Alcotest.test_case "powers" `Quick test_pow
        ; Alcotest.test_case
            "equality ignores construction"
            `Quick
            test_equal_ignores_construction
        ; Alcotest.test_case "degree and num_vars" `Quick test_degree_and_vars
        ] )
    ; ( "laws"
      , [ Alcotest.test_case "additive identity" `Quick test_add_identity
        ; Alcotest.test_case "subtract self" `Quick test_sub_self
        ; Alcotest.test_case "multiplicative identity" `Quick test_mul_identity
        ; Alcotest.test_case "multiplication commutes" `Quick test_mul_commutes
        ; Alcotest.test_case "addition associates" `Quick test_add_assoc
        ; Alcotest.test_case "distributivity" `Quick test_distributes
        ] )
    ; "normalizer", [ Alcotest.test_case "AST to polynomial" `Quick test_normalizer ]
    ]
;;
