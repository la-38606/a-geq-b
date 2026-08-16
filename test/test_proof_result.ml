(* Tests for the structured pipeline record (Proof_result): the statuses, the
   route metadata, and above all the trust boundary -- no path through the
   record may reach PROVED without the exact checker accepting. *)

open A_geq_b

let status = Alcotest.testable (Fmt.of_to_string Proof_result.string_of_status) ( = )

(* --- straightforward routes -------------------------------------------- *)

let proves_simple_sos_with_exact_search () =
  let r = Proof_result.prove "a^2 + b^2 >= 2*a*b" in
  Alcotest.check status "status" Proof_result.Proved r.status;
  (match r.search with
   | Some Proof_result.Exact_gram -> ()
   | _ -> Alcotest.fail "expected the exact Gram route");
  (match r.certificate with
   | Some (Proof_result.Sos _) -> ()
   | _ -> Alcotest.fail "expected a sum-of-squares certificate");
  (* The last trace step must be the trusted check, and it must have passed. *)
  match List.rev r.trace with
  | last :: _ -> Alcotest.(check bool) "final step trusted" true (last.trusted && last.ok)
  | [] -> Alcotest.fail "empty trace"
;;

let constrained_route_reports_its_strategy () =
  let r = Proof_result.prove "a^3 >= b^3 given a = b" in
  Alcotest.check status "status" Proof_result.Proved r.status;
  (match r.search with
   | Some (Proof_result.Constrained_search Prover.Equality_reduction) -> ()
   | _ -> Alcotest.fail "expected the equality-reduction strategy");
  Alcotest.(check int) "one hypothesis" 1 (List.length r.hypotheses)
;;

let motzkin_is_no_certificate_not_false () =
  (* The Motzkin polynomial is nonnegative but not a sum of squares, so the
     honest answer is NO_CERT_FOUND -- with no error: not finding a certificate
     is not a malfunction, and must never be reported as a disproof. *)
  let r = Proof_result.prove "x^4*y^2 + x^2*y^4 + 1 >= 3*x^2*y^2" in
  Alcotest.check status "status" Proof_result.No_cert_found r.status;
  Alcotest.(check bool) "no certificate" true (r.certificate = None);
  Alcotest.(check bool) "no error" true (r.error = None)
;;

let contradictory_hypotheses_carry_a_vacuity_warning () =
  (* a = 2 and a = 3 cut out the empty region, so the claim is provable but only
     vacuously; the record must say so even when the status is Proved. *)
  let r = Proof_result.prove "a^2 >= 1 given a = 2, a = 3" in
  Alcotest.check status "status" Proof_result.Proved r.status;
  Alcotest.(check bool) "vacuity warning present" true (r.vacuous <> [])
;;

let parse_failure_is_invalid_input () =
  let r = Proof_result.prove "a^2 + >= b" in
  Alcotest.check status "status" Proof_result.Invalid_input r.status;
  match r.error with
  | Some msg ->
    Alcotest.(check bool)
      "error mentions parsing"
      true
      (String.length msg > 0
       && String.sub msg 0 (min 15 (String.length msg)) = "could not parse")
  | None -> Alcotest.fail "expected an error message"
;;

(* --- the numerical SDP hook -------------------------------------------- *)

(* A target the exact search cannot close (its Gram matrix has too many free
   entries for the bounded grid): AM-GM in four variables. *)
let amgm4 = "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d"

let target_of (claim : string) : Polynomial.t =
  match Parser.parse claim with
  | Error m -> Alcotest.failf "test claim does not parse: %s" m
  | Ok c -> snd (Normalizer.poly_of_claim c)
;;

(* Build the float Gram matrix of a known-good certificate over the SDP basis:
   Q = sum_k c_k v_k v_k^T with v_k the coefficient vector of q_k. Feeding this
   "perfect numerical solution" through the hook exercises emit -> round ->
   check without a numerical solver in the loop. *)
let gram_floats_of_certificate (p : Polynomial.t) (cert : Certificate.t)
  : float array array
  =
  let basis = Prover.sdp_basis p in
  let r = Array.length basis in
  let index_of m =
    let rec go i =
      if i = r then Alcotest.fail "certificate monomial outside the SDP basis";
      if Monomial.equal basis.(i) m then i else go (i + 1)
    in
    go 0
  in
  let q = Array.make_matrix r r 0.0 in
  List.iter
    (fun { Certificate.coeff; poly } ->
       let c = Rational.to_float coeff in
       let v = Array.make r 0.0 in
       List.iter
         (fun (m, x) -> v.(index_of m) <- Rational.to_float x)
         (Polynomial.to_list poly);
       for i = 0 to r - 1 do
         for j = 0 to r - 1 do
           q.(i).(j) <- q.(i).(j) +. (c *. v.(i) *. v.(j))
         done
       done)
    cert;
  q
;;

(* The classic AM-GM-4 decomposition, used only to manufacture the numerical
   Gram matrix above: a^4+b^4+c^4+d^4-4abcd
   = (a^2-b^2)^2 + (c^2-d^2)^2 + 2(ab-cd)^2. *)
let amgm4_certificate () : Certificate.t =
  let p s =
    match Parser.parse_expr s with
    | Error m -> Alcotest.failf "bad test polynomial: %s" m
    | Ok e -> Normalizer.poly_of_expr [ "a"; "b"; "c"; "d" ] e
  in
  Certificate.make
    [ Certificate.term Rational.one (p "a^2 - b^2")
    ; Certificate.term Rational.one (p "c^2 - d^2")
    ; Certificate.term (Rational.of_int 2) (p "a*b - c*d")
    ]
;;

let numerically_correct_gram_reconstructs_exactly () =
  let target = target_of amgm4 in
  let q = gram_floats_of_certificate target (amgm4_certificate ()) in
  let sdp _p = Ok (q, "handcrafted Gram matrix (test)") in
  let r = Proof_result.prove ~sdp amgm4 in
  Alcotest.check status "status" Proof_result.Proved r.status;
  match r.search with
  | Some Proof_result.Numerical_sdp -> ()
  | _ -> Alcotest.fail "expected the numerical SDP route"
;;

let sdp_candidate_cannot_bypass_exact_checker () =
  (* A wrong "solution" (the identity matrix satisfies none of the coefficient
     constraints' rounding targets) must die in reconstruction; the worst
     possible outcome is NO_CERT_FOUND, never PROVED. *)
  let sdp p =
    let n = Array.length (Prover.sdp_basis p) in
    Ok (Array.init n (fun i -> Array.init n (fun j -> if i = j then 1.0 else 0.0)),
        "identity matrix (deliberately wrong)")
  in
  let r = Proof_result.prove ~sdp amgm4 in
  Alcotest.check status "status" Proof_result.No_cert_found r.status;
  Alcotest.(check bool) "no certificate" true (r.certificate = None)
;;

let sdp_solver_failure_is_reported_not_raised () =
  let sdp _p = Error "the numerical solver is not available" in
  let r = Proof_result.prove ~sdp amgm4 in
  Alcotest.check status "status" Proof_result.No_cert_found r.status;
  Alcotest.(check bool)
    "trace records the solver failure"
    true
    (List.exists
       (fun (s : Proof_result.step) -> s.title = "Numerical SDP" && not s.ok)
       r.trace)
;;

(* --- JSON encoding ------------------------------------------------------ *)

let json_certificate_file_round_trips () =
  (* The "file" field of the JSON encoding must itself be a loadable
     certificate that the trusted checker accepts -- including for constrained
     claims, where the recorded claim must be the bare inequality (the
     hypotheses are carried separately). *)
  let r = Proof_result.prove "a^2 + b^2 >= 2 given a*b = 1" in
  Alcotest.check status "status" Proof_result.Proved r.status;
  let file =
    Proof_result.to_json r
    |> Yojson.Safe.Util.member "certificate"
    |> Yojson.Safe.Util.member "file"
  in
  match Constrained.of_string_any (Yojson.Safe.to_string file) with
  | Error m -> Alcotest.failf "emitted certificate file does not load: %s" m
  | Ok (Constrained.Unconstrained _) -> Alcotest.fail "expected a constrained file"
  | Ok (Constrained.Constrained { target; hypotheses; certificate; _ }) ->
    Alcotest.(check bool)
      "checker accepts the reloaded certificate"
      true
      (Checker.check_constrained_ok ~hypotheses target certificate)
;;

let json_reports_status_and_trace () =
  let r = Proof_result.prove "a^2 + b^2 >= 2*a*b" in
  let json = Proof_result.to_json r in
  let member k = Yojson.Safe.Util.member k json in
  Alcotest.(check string)
    "status"
    "PROVED"
    (Yojson.Safe.Util.to_string (member "status"));
  Alcotest.(check bool)
    "trace is non-empty"
    true
    (Yojson.Safe.Util.to_list (member "trace") <> [])
;;

let () =
  Alcotest.run
    "proof_result"
    [ ( "routes"
      , [ Alcotest.test_case "simple SOS, exact route" `Quick
            proves_simple_sos_with_exact_search
        ; Alcotest.test_case "constrained strategy reported" `Quick
            constrained_route_reports_its_strategy
        ; Alcotest.test_case "Motzkin: no cert, not false" `Quick
            motzkin_is_no_certificate_not_false
        ; Alcotest.test_case "vacuous hypotheses flagged" `Quick
            contradictory_hypotheses_carry_a_vacuity_warning
        ; Alcotest.test_case "parse failure invalid" `Quick
            parse_failure_is_invalid_input
        ] )
    ; ( "sdp-hook"
      , [ Alcotest.test_case "correct Gram reconstructs" `Quick
            numerically_correct_gram_reconstructs_exactly
        ; Alcotest.test_case "bad Gram cannot bypass checker" `Quick
            sdp_candidate_cannot_bypass_exact_checker
        ; Alcotest.test_case "solver failure reported" `Quick
            sdp_solver_failure_is_reported_not_raised
        ] )
    ; ( "json"
      , [ Alcotest.test_case "certificate file round-trips" `Quick
            json_certificate_file_round_trips
        ; Alcotest.test_case "status and trace present" `Quick
            json_reports_status_and_trace
        ] )
    ]
;;
