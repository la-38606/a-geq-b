(** Tests for the string -> Ast parser (and, through it, JSON certificate
    loading). *)

open A_geq_b

let ctx = [ "a"; "b"; "c" ]
let a = Polynomial.var 0
let b = Polynomial.var 1
let c = Polynomial.var 2
let ( +! ) = Polynomial.add
let ( -! ) = Polynomial.sub
let ( *! ) = Polynomial.mul
let scale n d = Polynomial.scalar_mul (Rational.of_ints n d)

let poly =
  Alcotest.testable
    (fun fmt p -> Format.fprintf fmt "%s" (Pretty.string_of_poly ctx p))
    Polynomial.equal

(* Parse an expression under [ctx] and compare it to an expected polynomial. *)
let parses_to src expected () =
  match Parser.parse_expr src with
  | Error m -> Alcotest.failf "parse_expr %S failed: %s" src m
  | Ok e -> Alcotest.check poly src expected (Normalizer.poly_of_expr ctx e)

let expr_rejected src () =
  match Parser.parse_expr src with
  | Ok _ -> Alcotest.failf "expected %S to be rejected, but it parsed" src
  | Error _ -> ()

let claim_rejected src () =
  match Parser.parse src with
  | Ok _ -> Alcotest.failf "expected claim %S to be rejected, but it parsed" src
  | Error _ -> ()

(* --- expression parsing ------------------------------------------------- *)

let test_sum () = parses_to "a^2 + b^2" (Polynomial.pow a 2 +! Polynomial.pow b 2) ()

let test_paren_power () =
  (* (a-b)^2 = a^2 - 2ab + b^2 *)
  parses_to "(a-b)^2"
    (Polynomial.pow a 2 -! scale 2 1 (a *! b) +! Polynomial.pow b 2)
    ()

let test_rational_coeff () = parses_to "1/2*a^2" (scale 1 2 (Polynomial.pow a 2)) ()

let test_precedence () =
  (* '*' binds tighter than '+' *)
  parses_to "a + b*c" (a +! (b *! c)) ()

let test_unary_minus () = parses_to "-a + b" (Polynomial.neg a +! b) ()

let test_negative_literal () = parses_to "a - 3" (a -! Polynomial.of_int 3) ()

let test_nested () =
  parses_to "2*(a + b)*c - 1" (scale 2 1 ((a +! b) *! c) -! Polynomial.one) ()

(* --- claim parsing ------------------------------------------------------ *)

let test_claim_ge () =
  match Parser.parse "prove a^2 + b^2 + c^2 >= a*b + b*c + c*a" with
  | Error m -> Alcotest.failf "claim failed to parse: %s" m
  | Ok claim ->
      let vars, target = Normalizer.poly_of_claim ~context:ctx claim in
      Alcotest.(check (list string)) "vars" ctx vars;
      Alcotest.check poly "target = A - B"
        (Prover.hello_world_target ()) target

let test_claim_le () =
  (* 2*a^2 + 2*b^2 <= ... is oriented to prove RHS - LHS >= 0. Use a case where
     A <= B so that B - A = (a+b)^2 - ... ; here: (a+b)^2 <= 2*a^2 + 2*b^2. *)
  match Parser.parse "(a+b)^2 <= 2*a^2 + 2*b^2" with
  | Error m -> Alcotest.failf "claim failed to parse: %s" m
  | Ok claim ->
      let _vars, target = Normalizer.poly_of_claim ~context:ctx claim in
      (* B - A = 2a^2 + 2b^2 - (a+b)^2 = a^2 - 2ab + b^2 *)
      Alcotest.check poly "target = B - A"
        (Polynomial.pow a 2 -! scale 2 1 (a *! b) +! Polynomial.pow b 2)
        target

(* --- invalid input ------------------------------------------------------ *)

let test_rejections () =
  List.iter (fun s -> expr_rejected s ())
    [ "a +"; "a ** b"; "a b"; "a/b"; ""; "("; "a^"; "a^-1"; "*a"; "1/0" ];
  List.iter (fun s -> claim_rejected s ())
    [ "a >= "; "a > b"; "a b >= c"; "a^2 + b^2" (* no relation *) ]

(* --- JSON certificate loading ------------------------------------------- *)

let hello_json =
  {|{ "claim": "a^2+b^2+c^2 >= a*b+b*c+c*a", "variables": ["a","b","c"],
      "sos": [ {"coeff":"1/2","poly":"a-b"}, {"coeff":"1/2","poly":"b-c"},
               {"coeff":"1/2","poly":"a-c"} ] }|}

let test_json_valid () =
  match Certificate.of_string hello_json with
  | Error m -> Alcotest.failf "of_string failed: %s" m
  | Ok { target; certificate; _ } ->
      Alcotest.(check bool) "loaded certificate checks out" true
        (Checker.check_sos target certificate)

let test_json_wrong_coeff () =
  (* 1/3 instead of 1/2 on the middle term: parses fine, fails the check. *)
  let json =
    {|{ "claim": "a^2+b^2+c^2 >= a*b+b*c+c*a", "variables": ["a","b","c"],
        "sos": [ {"coeff":"1/2","poly":"a-b"}, {"coeff":"1/3","poly":"b-c"},
                 {"coeff":"1/2","poly":"a-c"} ] }|}
  in
  match Certificate.of_string json with
  | Error m -> Alcotest.failf "of_string failed: %s" m
  | Ok { target; certificate; _ } ->
      Alcotest.(check bool) "wrong coefficient is rejected by checker" false
        (Checker.check_sos target certificate)

let test_json_malformed_rational () =
  match Certificate.of_string
          {|{ "claim":"a>=b", "variables":["a","b"],
              "sos":[{"coeff":"1/","poly":"a-b"}] }|}
  with
  | Ok _ -> Alcotest.fail "expected a malformed-rational error"
  | Error _ -> ()

let test_json_unknown_variable () =
  (* 'z' is not in the declared variable context. *)
  match Certificate.of_string
          {|{ "claim":"a>=b", "variables":["a","b"], "sos":[{"coeff":"1","poly":"a-z"}] }|}
  with
  | Ok _ -> Alcotest.fail "expected an unknown-variable error"
  | Error _ -> ()

let test_json_missing_field () =
  match Certificate.of_string {|{ "variables":["a"], "sos":[] }|} with
  | Ok _ -> Alcotest.fail "expected a missing-'claim' error"
  | Error _ -> ()

let () =
  Alcotest.run "parser"
    [ ( "expressions",
        [ Alcotest.test_case "sum of powers" `Quick test_sum;
          Alcotest.test_case "parenthesised power" `Quick test_paren_power;
          Alcotest.test_case "rational coefficient" `Quick test_rational_coeff;
          Alcotest.test_case "precedence" `Quick test_precedence;
          Alcotest.test_case "unary minus" `Quick test_unary_minus;
          Alcotest.test_case "negative literal" `Quick test_negative_literal;
          Alcotest.test_case "nested" `Quick test_nested ] );
      ( "claims",
        [ Alcotest.test_case "A >= B target" `Quick test_claim_ge;
          Alcotest.test_case "A <= B target" `Quick test_claim_le ] );
      ("invalid", [ Alcotest.test_case "malformed inputs rejected" `Quick test_rejections ]);
      ( "json",
        [ Alcotest.test_case "valid certificate loads and checks" `Quick test_json_valid;
          Alcotest.test_case "wrong coefficient fails check" `Quick test_json_wrong_coeff;
          Alcotest.test_case "malformed rational rejected" `Quick test_json_malformed_rational;
          Alcotest.test_case "unknown variable rejected" `Quick test_json_unknown_variable;
          Alcotest.test_case "missing field rejected" `Quick test_json_missing_field ] ) ]
