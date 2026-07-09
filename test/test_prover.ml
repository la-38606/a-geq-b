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

let provable (s : string) () =
  let p = target s in
  match Prover.prove p with
  | Prover.Proved cert ->
      (* The returned certificate must independently pass the trusted checker. *)
      Alcotest.(check bool) ("checker accepts prover output for: " ^ s) true
        (Checker.check_sos p cert)
  | Prover.No_certificate_found -> Alcotest.failf "expected to prove: %s" s

let not_provable (s : string) () =
  let p = target s in
  match Prover.prove p with
  | Prover.No_certificate_found -> ()
  | Prover.Proved _ -> Alcotest.failf "prover unsoundly proved: %s" s

(* Targets the prover should handle: degree-<=2 via the {1, x_i} Gram basis,
   and even-power forms via monomial-basis substitution. *)
let provable_cases =
  [ (* degree <= 2 *)
    "a^2 + b^2 >= 2*a*b";
    "a^2 + b^2 + c^2 >= a*b + b*c + c*a";
    "3*(a^2 + b^2 + c^2) >= (a + b + c)^2";
    "a^2 + 1 >= 2*a";
    "a^2 + 5*b^2 + 4*a*b >= 0";
    "x^2 + x*y + y^2 >= 0";
    "a^2 + 9*b^2 + 25*c^2 + 30*b*c >= 6*a*b + 10*a*c";
    "a^2 + b^2 + c^2 + d^2 >= a*b + b*c + c*d + d*a";
    "a^2 + b^2 + 1 >= a*b + a + b";
    "a^2 + b^2 + c^2 >= a*b + a*c";
    "a >= a" (* target 0: the empty SOS is a valid proof *);
    "5 >= 2" (* target 3: a nonnegative constant *);
    (* even-power / monomial-substitution forms *)
    "a^4 + b^4 >= 2*a^2*b^2";
    "a^4 + b^4 + c^4 >= a^2*b^2 + b^2*c^2 + c^2*a^2";
    "a^6 + b^6 >= 2*a^3*b^3";
    "a^8 + b^8 >= 2*a^4*b^4";
    "(a^2 + b^2)*(c^2 + d^2) >= (a*c + b*d)^2" (* Lagrange 2 *);
    "a^2*b^2 + b^2*c^2 + c^2*a^2 >= a^2*b*c + a*b^2*c + a*b*c^2" ]

(* Must NOT be proved: false claims, out-of-scope (needs constraints), and
   higher-degree targets that need Gram freedom (SDP) not yet implemented. *)
let unprovable_cases =
  [ "a^2 + b^2 >= 3*a*b" (* false *);
    "a^2 + b^2 + c^2 >= 2*(a*b + b*c + c*a)" (* false *);
    "a^2 >= 1" (* false for all reals *);
    "a + b + c >= 3" (* out of scope: only true under a constraint *);
    "a >= 0" (* linear: not nonnegative for all reals *);
    "a^3 + b^3 + c^3 >= 3*a*b*c" (* degree 3: needs a >= 0 *);
    "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d" (* needs a non-unique Gram (SDP) *);
    "a^4 + b^4 >= a^3*b + a*b^3" (* cyclic; needs Gram freedom *) ]

let () =
  Alcotest.run "prover"
    [ ( "proves (degree <= 2)",
        List.map (fun s -> Alcotest.test_case s `Quick (provable s)) provable_cases );
      ( "does not prove",
        List.map (fun s -> Alcotest.test_case s `Quick (not_provable s)) unprovable_cases ) ]
