(** Tests for the trusted checker.

    The valid case is the built-in hello-world example; the rejection cases
    corrupt it in each of the ways the design says must be caught: negative
    coefficient, wrong expansion, a missing term, and an extra term. *)

open A_geq_b

let a = Polynomial.var 0
let b = Polynomial.var 1
let c = Polynomial.var 2
let half = Rational.of_ints 1 2

(* Target: a^2 + b^2 + c^2 - a*b - b*c - c*a. *)
let target = Prover.hello_world_target ()

(* Valid certificate: 1/2(a-b)^2 + 1/2(b-c)^2 + 1/2(a-c)^2. *)
let valid_cert = Prover.hello_world_certificate ()

let test_accepts_valid () =
  Alcotest.(check bool)
    "valid SOS certificate accepted"
    true
    (Checker.check_sos target valid_cert)
;;

let test_expand_equals_target () =
  Alcotest.(check bool)
    "expansion equals the target polynomial"
    true
    (Polynomial.equal target (Checker.expand valid_cert))
;;

let test_rejects_negative_coeff () =
  (* Flip one coefficient to -1/2: the sum still equals target numerically only
     if... it does not; but even the identity is destroyed, so the primary
     reason we reject is the negative coefficient. *)
  let bad =
    Certificate.make
      [ Certificate.term (Rational.neg half) (Polynomial.sub a b)
      ; Certificate.term half (Polynomial.sub b c)
      ; Certificate.term half (Polynomial.sub a c)
      ]
  in
  Alcotest.(check bool)
    "negative coefficient rejected"
    false
    (Checker.check_sos target bad)
;;

let test_rejects_wrong_poly () =
  (* Replace (a - b) with (a - 2b): the expansion no longer matches. *)
  let two_b = Polynomial.scalar_mul (Rational.of_int 2) b in
  let bad =
    Certificate.make
      [ Certificate.term half (Polynomial.sub a two_b)
      ; Certificate.term half (Polynomial.sub b c)
      ; Certificate.term half (Polynomial.sub a c)
      ]
  in
  Alcotest.(check bool) "wrong expansion rejected" false (Checker.check_sos target bad)
;;

let test_rejects_missing_term () =
  let bad =
    Certificate.make
      [ Certificate.term half (Polynomial.sub a b)
      ; Certificate.term half (Polynomial.sub b c)
      ]
  in
  Alcotest.(check bool) "missing term rejected" false (Checker.check_sos target bad)
;;

let test_rejects_extra_term () =
  let bad =
    Certificate.make
      [ Certificate.term half (Polynomial.sub a b)
      ; Certificate.term half (Polynomial.sub b c)
      ; Certificate.term half (Polynomial.sub a c)
      ; Certificate.term Rational.one a (* spurious + a^2 *)
      ]
  in
  Alcotest.(check bool) "extra term rejected" false (Checker.check_sos target bad)
;;

let test_failure_reason_negative () =
  (* The reported reason for a negative coefficient should be exactly that. *)
  let bad = Certificate.make [ Certificate.term (Rational.neg half) a ] in
  match Checker.check target bad with
  | Checker.Rejected (Checker.Negative_coefficient _) -> ()
  | _ -> Alcotest.fail "expected Negative_coefficient rejection"
;;

let () =
  Alcotest.run
    "checker"
    [ ( "accept"
      , [ Alcotest.test_case "valid certificate" `Quick test_accepts_valid
        ; Alcotest.test_case "expansion equals target" `Quick test_expand_equals_target
        ] )
    ; ( "reject"
      , [ Alcotest.test_case "negative coefficient" `Quick test_rejects_negative_coeff
        ; Alcotest.test_case "wrong expansion" `Quick test_rejects_wrong_poly
        ; Alcotest.test_case "missing term" `Quick test_rejects_missing_term
        ; Alcotest.test_case "extra term" `Quick test_rejects_extra_term
        ; Alcotest.test_case
            "reason is negative-coefficient"
            `Quick
            test_failure_reason_negative
        ] )
    ]
;;
