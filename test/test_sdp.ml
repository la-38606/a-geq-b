(** Tests for the untrusted numerical SDP path ({!Sdp}).

    The Python solver is exercised end-to-end by [sdp/] and the corpus; here we
    test the OCaml half -- emitting the problem and, above all, rounding a
    numerical Gram matrix back to an exact certificate -- WITHOUT invoking Python,
    by feeding in a Gram matrix directly. Soundness is structural: the only way
    {!Sdp.certificate_of_solution} returns [Some] is if {!Checker.check_sos}
    accepted the rounded certificate, so no numerical input can yield a false
    proof. The tests make that explicit. *)

open A_geq_b

let target (s : string) : Polynomial.t =
  match Parser.parse s with
  | Ok c -> snd (Normalizer.poly_of_claim c)
  | Error m -> Alcotest.failf "test setup: could not parse %S: %s" s m
;;

let index_of (basis : Monomial.t array) (m : Monomial.t) : int =
  let r = ref (-1) in
  Array.iteri (fun i x -> if Monomial.equal x m then r := i) basis;
  if !r < 0 then Alcotest.failf "monomial not in sdp_basis";
  !r
;;

(* Build a numerical Gram matrix over [sdp_basis p] from entries given by
   monomial pair, so the test does not depend on the basis ordering. *)
let gram (p : Polynomial.t) (entries : (Monomial.t * Monomial.t * float) list)
  : float array array
  =
  let basis = Prover.sdp_basis p in
  let r = Array.length basis in
  let q = Array.make_matrix r r 0.0 in
  List.iter
    (fun (m1, m2, v) ->
       let i = index_of basis m1
       and j = index_of basis m2 in
       q.(i).(j) <- v;
       q.(j).(i) <- v)
    entries;
  q
;;

let mono es = Monomial.canonical es

(* A valid numerical Gram rounds to a checker-accepted certificate. p =
   (a^2 - b^2)^2 = a^4 - 2 a^2 b^2 + b^4; over {a^2, ab, b^2} the Gram is the
   rank-one matrix with 1, 1 on the a^2/b^2 diagonal and -1 coupling them. *)
let test_round_trip () =
  let p = target "a^4 + b^4 >= 2*a^2*b^2" in
  let a2 = mono [ 2; 0 ]
  and b2 = mono [ 0; 2 ] in
  let q = gram p [ a2, a2, 1.0; b2, b2, 1.0; a2, b2, -1.0 ] in
  match Sdp.certificate_of_solution p q with
  | Some cert ->
    Alcotest.(check bool)
      "checker accepts the rounded certificate"
      true
      (Checker.check_sos p cert)
  | None -> Alcotest.fail "expected a certificate from the exact Gram"
;;

(* A slightly perturbed numerical Gram (as a real solver would return) must still
   round to an exact certificate. *)
let test_round_trip_noisy () =
  let p = target "a^4 + b^4 >= 2*a^2*b^2" in
  let a2 = mono [ 2; 0 ]
  and b2 = mono [ 0; 2 ] in
  let q = gram p [ a2, a2, 1.0000004; b2, b2, 0.9999997; a2, b2, -1.0000002 ] in
  match Sdp.certificate_of_solution p q with
  | Some cert ->
    Alcotest.(check bool) "noisy Gram still checks" true (Checker.check_sos p cert)
  | None -> Alcotest.fail "expected rounding to recover the certificate"
;;

(* A garbage Gram cannot produce a false proof: whatever it returns, if it is
   [Some] the checker must have accepted it (structural soundness), and here the
   rounding simply fails to find a PSD completion, so it is [None]. *)
let test_garbage_is_safe () =
  let p = target "a^4 + b^4 >= 2*a^2*b^2" in
  let basis = Prover.sdp_basis p in
  let r = Array.length basis in
  let q = Array.make_matrix r r 5.0 in
  (* all 5.0: not a PSD Gram of p *)
  match Sdp.certificate_of_solution p q with
  | None -> ()
  | Some cert ->
    (* If it ever returns a certificate, it MUST be a real one. *)
    Alcotest.(check bool)
      "any returned certificate is checker-verified"
      true
      (Checker.check_sos p cert)
;;

(* A wrong-dimension matrix is rejected, not a crash. *)
let test_bad_dimension () =
  let p = target "a^4 + b^4 >= 2*a^2*b^2" in
  Alcotest.(check bool)
    "1x1 matrix for a larger basis -> None"
    true
    (Sdp.certificate_of_solution p [| [| 1.0 |] |] = None)
;;

(* The emitted problem has one constraint per product monomial and the right
   dimension. *)
let test_problem_shape () =
  let p = target "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d" in
  let json = Sdp.problem_json p in
  let dim = Yojson.Safe.Util.(member "dim" json |> to_int) in
  let ncons = Yojson.Safe.Util.(member "constraints" json |> to_list |> List.length) in
  Alcotest.(check int) "basis dimension" 10 dim;
  Alcotest.(check bool) "at least one constraint per p-monomial" true (ncons >= 5)
;;

let () =
  Alcotest.run
    "sdp"
    [ ( "round-trip"
      , [ Alcotest.test_case "exact Gram -> certificate" `Quick test_round_trip
        ; Alcotest.test_case "noisy Gram -> certificate" `Quick test_round_trip_noisy
        ] )
    ; ( "soundness"
      , [ Alcotest.test_case "garbage Gram is safe" `Quick test_garbage_is_safe
        ; Alcotest.test_case "wrong dimension rejected" `Quick test_bad_dimension
        ] )
    ; "emit", [ Alcotest.test_case "problem shape" `Quick test_problem_shape ]
    ]
;;
