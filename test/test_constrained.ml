(** Tests for the trusted constrained (Positivstellensatz) checker.

    Accept cases exercise the three certificate ingredients — a [Nonneg]
    hypothesis scaled by an SOS, a [Zero] hypothesis scaled by an arbitrary
    polynomial, and an SOS [base]. Reject cases corrupt them in each way the
    design must catch: a negative multiplier coefficient, a scaled polynomial
    that is not a hypothesis, a hypothesis used at the wrong kind, and a wrong
    expansion. *)

open A_geq_b

let a = Polynomial.var 0
let b = Polynomial.var 1
let one = Polynomial.one
let sq p = Certificate.term Rational.one p (* the SOS term 1 * p^2 *)

(* a^3 >= 0  given  a >= 0, via a^3 = (1 * a^2) * a. *)
let cube = Polynomial.pow a 3
let cube_hyps = [ Constrained.nonneg a ]

let cube_cert =
  Constrained.make
    ~base:[]
    ~products:[ Constrained.times_nonneg ~multiplier:[ sq a ] ~nonneg:a ]
;;

(* a^2 - 1 >= 0  given  a - 1 = 0, via (a + 1) * (a - 1). *)
let a2m1 = Polynomial.sub (Polynomial.mul a a) one
let a_minus_1 = Polynomial.sub a one
let a_plus_1 = Polynomial.add a one
let eq_hyps = [ Constrained.zero a_minus_1 ]

let eq_cert =
  Constrained.make
    ~base:[]
    ~products:[ Constrained.times_zero ~multiplier:a_plus_1 ~zero:a_minus_1 ]
;;

let test_accepts_nonneg () =
  Alcotest.(check bool)
    "a^3 >= 0 given a >= 0 accepted"
    true
    (Checker.check_constrained_ok ~hypotheses:cube_hyps cube cube_cert)
;;

let test_accepts_zero () =
  Alcotest.(check bool)
    "a^2 - 1 >= 0 given a - 1 = 0 accepted"
    true
    (Checker.check_constrained_ok ~hypotheses:eq_hyps a2m1 eq_cert)
;;

let test_accepts_with_base () =
  (* a^3 + b^2 >= 0 given a >= 0: base b^2, plus (1 * a^2) * a. *)
  let target = Polynomial.add cube (Polynomial.mul b b) in
  let cert =
    Constrained.make
      ~base:[ sq b ]
      ~products:[ Constrained.times_nonneg ~multiplier:[ sq a ] ~nonneg:a ]
  in
  Alcotest.(check bool)
    "a^3 + b^2 >= 0 given a >= 0 accepted"
    true
    (Checker.check_constrained_ok ~hypotheses:cube_hyps target cert)
;;

let test_expand_equals_target () =
  Alcotest.(check bool)
    "constrained expansion equals the target"
    true
    (Polynomial.equal cube (Checker.expand_constrained cube_cert))
;;

let test_rejects_negative_coeff () =
  (* Multiplier -1 * a^2 is not an SOS. *)
  let bad =
    Constrained.make
      ~base:[]
      ~products:
        [ Constrained.times_nonneg
            ~multiplier:[ Certificate.term (Rational.of_int (-1)) a ]
            ~nonneg:a
        ]
  in
  match Checker.check_constrained ~hypotheses:cube_hyps cube bad with
  | Checker.Rejected (Checker.Negative_coefficient _) -> ()
  | _ -> Alcotest.fail "expected Negative_coefficient rejection"
;;

let test_rejects_undeclared_constraint () =
  (* No hypotheses declared, yet the certificate scales `a`. *)
  match Checker.check_constrained ~hypotheses:[] cube cube_cert with
  | Checker.Rejected (Checker.Unknown_constraint _) -> ()
  | _ -> Alcotest.fail "expected Unknown_constraint rejection"
;;

let test_rejects_wrong_kind () =
  (* a - 1 is only a Zero hypothesis; using it as a Nonneg must be rejected. *)
  let bad =
    Constrained.make
      ~base:[]
      ~products:[ Constrained.times_nonneg ~multiplier:[ sq one ] ~nonneg:a_minus_1 ]
  in
  match Checker.check_constrained ~hypotheses:eq_hyps a2m1 bad with
  | Checker.Rejected (Checker.Unknown_constraint _) -> ()
  | _ ->
    Alcotest.fail "expected Unknown_constraint rejection for a Zero hyp used as Nonneg"
;;

let test_rejects_wrong_expansion () =
  (* Structure and hypotheses are fine, but (1 * 1^2) * a = a /= a^3. *)
  let bad =
    Constrained.make
      ~base:[]
      ~products:[ Constrained.times_nonneg ~multiplier:[ sq one ] ~nonneg:a ]
  in
  match Checker.check_constrained ~hypotheses:cube_hyps cube bad with
  | Checker.Rejected (Checker.Mismatch _) -> ()
  | _ -> Alcotest.fail "expected Mismatch rejection"
;;

let () =
  Alcotest.run
    "constrained"
    [ ( "accept"
      , [ Alcotest.test_case "nonneg hypothesis" `Quick test_accepts_nonneg
        ; Alcotest.test_case "zero hypothesis" `Quick test_accepts_zero
        ; Alcotest.test_case "with an SOS base" `Quick test_accepts_with_base
        ; Alcotest.test_case "expansion equals target" `Quick test_expand_equals_target
        ] )
    ; ( "reject"
      , [ Alcotest.test_case
            "negative multiplier coefficient"
            `Quick
            test_rejects_negative_coeff
        ; Alcotest.test_case
            "undeclared constraint"
            `Quick
            test_rejects_undeclared_constraint
        ; Alcotest.test_case
            "hypothesis used at wrong kind"
            `Quick
            test_rejects_wrong_kind
        ; Alcotest.test_case "wrong expansion" `Quick test_rejects_wrong_expansion
        ] )
    ]
;;
