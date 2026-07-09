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

let test_rational_base_power () =
  (* (1/2)^2 = 1/4 *)
  parses_to "(1/2)^2" (Polynomial.const (Rational.of_ints 1 4)) ()

let test_const_power () = parses_to "2^3" (Polynomial.of_int 8) ()

let test_double_negation () = parses_to "a - -b" (a +! b) ()

let test_unary_minus_binds_power () =
  (* -a^2 parses as -(a^2), not (-a)^2 *)
  parses_to "-a^2" (Polynomial.neg (Polynomial.pow a 2)) ()

let test_right_assoc_power_rejected () =
  (* the grammar allows a single exponent per factor: a^2^3 is not accepted *)
  expr_rejected "a^2^3" ()

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
    [ "a +"; "a ** b"; "a b"; ""; "("; "a^"; "a^-1"; "*a"; "1/0" ];
  List.iter (fun s -> claim_rejected s ())
    [ "a >= "; "a > b"; "a b >= c"; "a^2 + b^2" (* no relation *) ]

(* --- division / clearing denominators ----------------------------------- *)

(* Division by a constant stays a polynomial. *)
let test_div_by_constant () =
  parses_to "(a + b)/2" (scale 1 2 (a +! b)) ();
  parses_to "a/2 + b/2" (scale 1 2 (a +! b)) ()

(* Division between expressions parses (it is cleared by the normalizer, not the
   parser). *)
let test_div_parses () =
  (match Parser.parse_expr "a/b" with
   | Ok _ -> ()
   | Error m -> Alcotest.failf "a/b should parse: %s" m);
  (match Parser.parse_expr "1/(a + b)" with
   | Ok _ -> ()
   | Error m -> Alcotest.failf "1/(a+b) should parse: %s" m)

(* Reduce a claim to its target polynomial p (where p >= 0 proves the claim). *)
let claim_target (s : string) : Polynomial.t =
  match Parser.parse s with
  | Ok c -> snd (Normalizer.poly_of_claim ~context:ctx c)
  | Error m -> Alcotest.failf "test setup: could not parse %S: %s" s m

let test_clear_reciprocal () =
  (* 1/a >= 0  clears to  a >= 0  (multiply by a^2, i.e. p = 1 * a). *)
  Alcotest.check poly "1/a >= 0 clears to a" a (claim_target "1/a >= 0")

let test_clear_square_over_const () =
  (* (a-b)^2/2 >= 0 clears to 2*(a-b)^2 (numerator times denominator). *)
  Alcotest.check poly "(a-b)^2/2 clears" (scale 2 1 (Polynomial.pow (a -! b) 2))
    (claim_target "(a - b)^2 / 2 >= 0")

let test_clear_common_denominator () =
  (* 1/a >= 1/b  ->  A - B = (b - a)/(ab); p = (b-a)*(ab). *)
  Alcotest.check poly "1/a >= 1/b clears"
    ((b -! a) *! (a *! b))
    (claim_target "1/a >= 1/b")

let test_division_by_zero_rejected () =
  match Parser.parse "1/(a - a) >= 0" with
  | Error m -> Alcotest.failf "should parse (error is at clearing time): %s" m
  | Ok c -> (
      match Normalizer.poly_of_claim ~context:ctx c with
      | _ -> Alcotest.fail "expected a division-by-zero error"
      | exception Invalid_argument _ -> ())

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

let test_json_empty_sos_identity () =
  (* a >= a : target is 0, and the empty sum of squares is a valid proof. *)
  match Certificate.of_string {|{ "claim":"a >= a", "variables":["a"], "sos":[] }|} with
  | Error m -> Alcotest.failf "of_string failed: %s" m
  | Ok { target; certificate; _ } ->
      Alcotest.(check bool) "0 = empty SOS" true (Checker.check_sos target certificate)

let test_json_ignores_metadata () =
  (* The loader must ignore extra fields (id, source, tags, ...). The corpus
     relies on this so its entries double as check-able certificates. *)
  let j =
    {|{ "id":"x", "source":"test", "tags":["a"], "notes":"n",
        "claim":"a^2 >= 0", "variables":["a"], "sos":[{"coeff":"1","poly":"a"}] }|}
  in
  match Certificate.of_string j with
  | Error m -> Alcotest.failf "of_string failed: %s" m
  | Ok { target; certificate; _ } ->
      Alcotest.(check bool) "metadata ignored; a^2 >= 0 checks" true
        (Checker.check_sos target certificate)

let () =
  Alcotest.run "parser"
    [ ( "expressions",
        [ Alcotest.test_case "sum of powers" `Quick test_sum;
          Alcotest.test_case "parenthesised power" `Quick test_paren_power;
          Alcotest.test_case "rational coefficient" `Quick test_rational_coeff;
          Alcotest.test_case "precedence" `Quick test_precedence;
          Alcotest.test_case "unary minus" `Quick test_unary_minus;
          Alcotest.test_case "negative literal" `Quick test_negative_literal;
          Alcotest.test_case "nested" `Quick test_nested;
          Alcotest.test_case "rational-base power" `Quick test_rational_base_power;
          Alcotest.test_case "constant power" `Quick test_const_power;
          Alcotest.test_case "double negation" `Quick test_double_negation;
          Alcotest.test_case "unary minus binds power" `Quick test_unary_minus_binds_power;
          Alcotest.test_case "right-assoc power rejected" `Quick test_right_assoc_power_rejected ] );
      ( "claims",
        [ Alcotest.test_case "A >= B target" `Quick test_claim_ge;
          Alcotest.test_case "A <= B target" `Quick test_claim_le ] );
      ("invalid", [ Alcotest.test_case "malformed inputs rejected" `Quick test_rejections ]);
      ( "division",
        [ Alcotest.test_case "division by a constant" `Quick test_div_by_constant;
          Alcotest.test_case "division parses" `Quick test_div_parses;
          Alcotest.test_case "clear 1/a >= 0" `Quick test_clear_reciprocal;
          Alcotest.test_case "clear (a-b)^2/2" `Quick test_clear_square_over_const;
          Alcotest.test_case "clear common denominator" `Quick test_clear_common_denominator;
          Alcotest.test_case "division by zero rejected" `Quick test_division_by_zero_rejected ] );
      ( "json",
        [ Alcotest.test_case "valid certificate loads and checks" `Quick test_json_valid;
          Alcotest.test_case "wrong coefficient fails check" `Quick test_json_wrong_coeff;
          Alcotest.test_case "malformed rational rejected" `Quick test_json_malformed_rational;
          Alcotest.test_case "unknown variable rejected" `Quick test_json_unknown_variable;
          Alcotest.test_case "missing field rejected" `Quick test_json_missing_field;
          Alcotest.test_case "empty SOS proves identity" `Quick test_json_empty_sos_identity;
          Alcotest.test_case "loader ignores metadata" `Quick test_json_ignores_metadata ] ) ]
