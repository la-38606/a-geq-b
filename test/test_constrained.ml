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

(* a*b >= 0  given  a >= 0, b >= 0, via the product hypothesis a*b (Schmüdgen). *)
let ab = Polynomial.mul a b
let prod_hyps = [ Constrained.nonneg a; Constrained.nonneg b ]

let prod_cert =
  Constrained.make
    ~base:[]
    ~products:[ Constrained.times_product ~multiplier:[ sq one ] ~factors:[ a; b ] ]
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

let test_accepts_product () =
  Alcotest.(check bool)
    "a*b >= 0 given a >= 0, b >= 0 accepted (product of hypotheses)"
    true
    (Checker.check_constrained_ok ~hypotheses:prod_hyps ab prod_cert)
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

let test_rejects_product_undeclared_factor () =
  (* Only a is declared nonneg; the product factor b is not a hypothesis. *)
  match Checker.check_constrained ~hypotheses:[ Constrained.nonneg a ] ab prod_cert with
  | Checker.Rejected (Checker.Unknown_constraint _) -> ()
  | _ -> Alcotest.fail "expected Unknown_constraint for an undeclared product factor"
;;

let test_rejects_product_zero_factor () =
  (* a is only a Zero hypothesis; a product factor must be a Nonneg hypothesis. *)
  match
    Checker.check_constrained
      ~hypotheses:[ Constrained.zero a; Constrained.nonneg b ]
      ab
      prod_cert
  with
  | Checker.Rejected (Checker.Unknown_constraint _) -> ()
  | _ ->
    Alcotest.fail "expected Unknown_constraint for a Zero hyp used as a product factor"
;;

(* --- JSON --- *)

let checks (p : Constrained.parsed) =
  Checker.check_constrained_ok ~hypotheses:p.hypotheses p.target p.certificate
;;

let test_json_roundtrip () =
  let json =
    Constrained.to_json ~claim:"a^2 - 1 >= 0" ~vars:[ "a" ] ~hypotheses:eq_hyps eq_cert
  in
  match Constrained.of_json json with
  | Error m -> Alcotest.fail ("round-trip parse failed: " ^ m)
  | Ok p -> Alcotest.(check bool) "round-tripped certificate still checks" true (checks p)
;;

let test_json_product_roundtrip () =
  let json =
    Constrained.to_json
      ~claim:"a*b >= 0"
      ~vars:[ "a"; "b" ]
      ~hypotheses:prod_hyps
      prod_cert
  in
  match Constrained.of_json json with
  | Error m -> Alcotest.fail ("product round-trip failed: " ^ m)
  | Ok p ->
    Alcotest.(check bool) "product certificate round-trips and checks" true (checks p)
;;

let test_of_string_valid () =
  let src =
    {|{ "claim":"a^2 - 1 >= 0", "variables":["a"],
       "hypotheses":[{"poly":"a - 1","kind":"zero"}],
       "certificate":{"base":[],
         "products":[{"kind":"zero","multiplier":"a + 1","constraint":"a - 1"}]} }|}
  in
  match Constrained.of_string src with
  | Error m -> Alcotest.fail ("parse failed: " ^ m)
  | Ok p -> Alcotest.(check bool) "parsed certificate checks" true (checks p)
;;

let test_of_string_corrupted () =
  (* multiplier a + 2 makes (a+2)(a-1) /= a^2 - 1; the checker must reject. *)
  let src =
    {|{ "claim":"a^2 - 1 >= 0", "variables":["a"],
       "hypotheses":[{"poly":"a - 1","kind":"zero"}],
       "certificate":{"base":[],
         "products":[{"kind":"zero","multiplier":"a + 2","constraint":"a - 1"}]} }|}
  in
  match Constrained.of_string src with
  | Error m -> Alcotest.fail ("should parse (shape is valid): " ^ m)
  | Ok p -> Alcotest.(check bool) "corrupted certificate rejected" false (checks p)
;;

let test_of_string_malformed () =
  (* An unknown hypothesis kind is a shape error: [Error], never an exception. *)
  let src =
    {|{ "claim":"a >= 0", "variables":["a"],
       "hypotheses":[{"poly":"a","kind":"bogus"}],
       "certificate":{"base":[],"products":[]} }|}
  in
  match Constrained.of_string src with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected Error for unknown hypothesis kind"
;;

let test_of_string_missing_certificate () =
  (* No 'certificate' field: must be an Error, never a raised exception. *)
  let src = {|{ "claim":"a >= 0", "variables":["a"], "hypotheses":[] }|} in
  match Constrained.of_string src with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected Error for a missing 'certificate' field"
;;

let test_any_non_object () =
  (* A non-object top-level JSON must be an Error, never a raised exception. *)
  List.iter
    (fun src ->
       match Constrained.of_string_any src with
       | Error _ -> ()
       | Ok _ -> Alcotest.failf "expected Error for non-object JSON %S" src)
    [ "[1, 2, 3]"; {|"hello"|}; "42"; "null" ]
;;

let test_any_dispatch () =
  (* of_string_any routes a "sos" doc to Unconstrained and a "certificate" doc
     to Constrained; both then check out. *)
  let plain =
    {|{ "claim":"a^2 >= 0", "variables":["a"], "sos":[{"coeff":"1","poly":"a"}] }|}
  in
  let constrained =
    {|{ "claim":"a^2 - 1 >= 0", "variables":["a"],
       "hypotheses":[{"poly":"a - 1","kind":"zero"}],
       "certificate":{"base":[],
         "products":[{"kind":"zero","multiplier":"a + 1","constraint":"a - 1"}]} }|}
  in
  (match Constrained.of_string_any plain with
   | Ok (Constrained.Unconstrained { target; certificate; _ }) ->
     Alcotest.(check bool) "plain checks" true (Checker.check_sos target certificate)
   | _ -> Alcotest.fail "expected an Unconstrained certificate");
  match Constrained.of_string_any constrained with
  | Ok (Constrained.Constrained p) ->
    Alcotest.(check bool) "constrained checks" true (checks p)
  | _ -> Alcotest.fail "expected a Constrained certificate"
;;

(* --- parsing side conditions end-to-end --- *)

(* Parse [src], normalize it, and check [cert] against the resulting target and
   hypotheses — exercising Parser -> Normalizer -> Constrained -> Checker. *)
let parsed_checks src cert =
  match Parser.parse src with
  | Error m -> Alcotest.failf "parse %S failed: %s" src m
  | Ok claim ->
    let ctx, target = Normalizer.poly_of_claim claim in
    let hypotheses = Constrained.hypotheses_of_claim ctx claim in
    Checker.check_constrained_ok ~hypotheses target cert
;;

let test_given_nonneg () =
  Alcotest.(check bool)
    "a^3 >= 0 given a >= 0 parses and checks"
    true
    (parsed_checks "a^3 >= 0 given a >= 0" cube_cert)
;;

let test_given_equality () =
  Alcotest.(check bool)
    "a^2 >= 1 given a = 1 parses and checks"
    true
    (parsed_checks "a^2 >= 1 given a = 1" eq_cert)
;;

let test_given_le_normalizes () =
  (* `0 <= a` is the same Nonneg(a) hypothesis as `a >= 0`. *)
  Alcotest.(check bool)
    "a^3 >= 0 given 0 <= a parses and checks"
    true
    (parsed_checks "a^3 >= 0 given 0 <= a" cube_cert)
;;

let () =
  Alcotest.run
    "constrained"
    [ ( "accept"
      , [ Alcotest.test_case "nonneg hypothesis" `Quick test_accepts_nonneg
        ; Alcotest.test_case "zero hypothesis" `Quick test_accepts_zero
        ; Alcotest.test_case "product of hypotheses" `Quick test_accepts_product
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
        ; Alcotest.test_case
            "undeclared product factor"
            `Quick
            test_rejects_product_undeclared_factor
        ; Alcotest.test_case
            "zero hyp as a product factor"
            `Quick
            test_rejects_product_zero_factor
        ] )
    ; ( "json"
      , [ Alcotest.test_case "round-trip" `Quick test_json_roundtrip
        ; Alcotest.test_case "product round-trip" `Quick test_json_product_roundtrip
        ; Alcotest.test_case "parse a valid certificate" `Quick test_of_string_valid
        ; Alcotest.test_case
            "parse then reject a corrupted one"
            `Quick
            test_of_string_corrupted
        ; Alcotest.test_case "malformed input is an Error" `Quick test_of_string_malformed
        ; Alcotest.test_case
            "missing 'certificate' is an Error"
            `Quick
            test_of_string_missing_certificate
        ; Alcotest.test_case "non-object JSON is an Error" `Quick test_any_non_object
        ; Alcotest.test_case
            "of_string_any dispatches both shapes"
            `Quick
            test_any_dispatch
        ] )
    ; ( "given"
      , [ Alcotest.test_case "nonneg side condition" `Quick test_given_nonneg
        ; Alcotest.test_case "equality side condition" `Quick test_given_equality
        ; Alcotest.test_case "<= normalizes to nonneg" `Quick test_given_le_normalizes
        ] )
    ]
;;
