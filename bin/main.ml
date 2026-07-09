(** A>=B command-line entry point.

    Commands:
    - [--help]            usage
    - [demo]              the built-in hardcoded proof
    - [prove "<ineq>"]    parse + (attempt to) auto-prove an inequality
    - [check <file.json>] load and check a JSON certificate

    Exit statuses mirror the reported [Status:] line:
    PROVED=0, NO_CERT_FOUND=2, INVALID_INPUT=3, CHECK_FAILED=4. *)

open A_geq_b

let description =
  String.concat "\n"
    [ "A>=B proves polynomial inequalities A >= B by rewriting them as p = A - B >= 0";
      "and verifying a sum-of-squares certificate p = sum_i c_i * q_i^2 (c_i >= 0)";
      "using exact rational arithmetic." ]

let usage () =
  print_string
    (String.concat "\n"
       [ "A>=B (a-geq-b) - sum-of-squares inequality prover";
         "";
         description;
         "";
         "Usage:";
         "  a-geq-b --help                     Show this message";
         "  a-geq-b demo                       Run the built-in hello-world proof";
         "  a-geq-b prove \"a^2+b^2 >= 2*a*b\"    Parse and try to prove an inequality";
         "  a-geq-b check cert.json            Load and check a JSON certificate";
         "" ])

(* --- shared printing ---------------------------------------------------- *)

(* The common "Claim / Equivalent to proving" preamble. *)
let print_preamble ~claim ~vars ~target =
  Printf.printf "Claim:\n  %s\n\n" claim;
  Printf.printf "Equivalent to proving:\n  %s >= 0\n\n" (Pretty.string_of_poly vars target)

(* Full proof output for an accepted certificate. *)
let print_proved ~claim ~vars ~target ~cert =
  print_preamble ~claim ~vars ~target;
  Printf.printf "Certificate:\n  %s\n  = %s\n\n"
    (Pretty.string_of_poly vars target)
    (Certificate.to_string vars cert);
  print_string
    "Reason:\n\
    \  Each summand is a nonnegative rational multiple of a square, so the\n\
    \  right-hand side is >= 0 for all real values. The checker verified the\n\
    \  identity between the two sides exactly.\n\n";
  Printf.printf "LaTeX:\n  %s = %s\n\n"
    (Pretty.latex_of_poly vars target)
    (Certificate.to_latex vars cert);
  print_string "Status: PROVED\n"

let string_of_failure ~vars = function
  | Checker.Negative_coefficient q ->
      Printf.sprintf "a certificate coefficient is negative: %s" (Rational.to_string q)
  | Checker.Mismatch { target; got } ->
      Printf.sprintf
        "the certificate does not expand to the target polynomial:\n\
        \  expected: %s\n\
        \  got:      %s"
        (Pretty.string_of_poly vars target)
        (Pretty.string_of_poly vars got)

(* --- commands ----------------------------------------------------------- *)

let run_demo () =
  let vars = Prover.hello_world_vars in
  let target = Prover.hello_world_target () in
  let cert = Prover.hello_world_certificate () in
  if Checker.check_sos target cert then
    (print_proved ~claim:Prover.hello_world_claim_string ~vars ~target ~cert; exit 0)
  else (print_string "Status: CHECK_FAILED\n"; exit 4)

let run_prove (input : string) =
  match Parser.parse input with
  | Error msg ->
      Printf.eprintf "Could not parse the inequality: %s\n" msg;
      print_string "Status: INVALID_INPUT\n";
      exit 3
  | Ok claim ->
      let vars, target = Normalizer.poly_of_claim claim in
      (match Prover.prove target with
       | Prover.Proved cert ->
           (* Untrusted output MUST pass the trusted checker before PROVED. *)
           if Checker.check_sos target cert then
             (print_proved ~claim:input ~vars ~target ~cert; exit 0)
           else begin
             print_preamble ~claim:input ~vars ~target;
             print_string
               "The prover proposed a certificate, but the checker rejected it.\n\n";
             print_string "Status: CHECK_FAILED\n";
             exit 4
           end
       | Prover.No_certificate_found ->
           print_preamble ~claim:input ~vars ~target;
           print_string
             (String.concat "\n"
                [ "No supported sum-of-squares certificate was found. The automatic";
                  "prover is not implemented yet (Milestone 5); this is not a disproof.";
                  ""; "" ]);
           print_string "Status: NO_CERT_FOUND\n";
           exit 2)

let run_check (path : string) =
  match Certificate.load_file path with
  | Error msg ->
      Printf.eprintf "Could not load certificate: %s\n" msg;
      print_string "Status: INVALID_INPUT\n";
      exit 3
  | Ok { claim_text; vars; target; certificate } -> (
      match Checker.check target certificate with
      | Checker.Verified ->
          print_proved ~claim:claim_text ~vars ~target ~cert:certificate;
          exit 0
      | Checker.Rejected failure ->
          print_preamble ~claim:claim_text ~vars ~target;
          Printf.printf "Certificate rejected: %s\n\n" (string_of_failure ~vars failure);
          print_string "Status: CHECK_FAILED\n";
          exit 4)

let () =
  match Array.to_list Sys.argv with
  | _ :: "demo" :: [] -> run_demo ()
  | _ :: "prove" :: [ input ] -> run_prove input
  | _ :: "check" :: [ path ] -> run_check path
  | [ _ ] | _ :: ("--help" | "-h" | "help") :: [] -> usage ()
  | _ :: cmd :: _ ->
      Printf.eprintf "Unknown or malformed command: %s\n\n" cmd;
      usage ();
      exit 1
  | [] -> usage () (* unreachable: argv always has the program name *)
