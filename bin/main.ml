(** A>=B command-line entry point.

    Commands:
    - [--help]            usage
    - [demo]              the built-in hardcoded proof
    - [prove "<ineq>"]    parse + (attempt to) auto-prove an inequality
    - [check <file.json>] load and check a JSON certificate
    - [lean "<ineq>"]     prove, then emit a checkable Lean proof to stdout

    Exit statuses mirror the reported [Status:] line:
    PROVED=0, NO_CERT_FOUND=2, INVALID_INPUT=3, CHECK_FAILED=4. *)

open A_geq_b

let description =
  String.concat
    "\n"
    [ "A>=B proves polynomial inequalities A >= B by rewriting them as p = A - B >= 0"
    ; "and verifying a sum-of-squares certificate p = sum_i c_i * q_i^2 (c_i >= 0)"
    ; "using exact rational arithmetic."
    ]
;;

let usage () =
  print_string
    (String.concat
       "\n"
       [ "A>=B (a-geq-b) - sum-of-squares inequality prover"
       ; ""
       ; description
       ; ""
       ; "Usage:"
       ; "  a-geq-b --help                     Show this message"
       ; "  a-geq-b demo                       Run the built-in hello-world proof"
       ; "  a-geq-b prove \"a^2+b^2 >= 2*a*b\"    Parse and try to prove an inequality"
       ; "  a-geq-b check cert.json            Load and check a JSON certificate"
       ; "  a-geq-b lean \"a^2 >= 2*a-1\" [name]  Emit a checkable Lean proof to stdout"
       ; ""
       ])
;;

(* --- exit status -------------------------------------------------------- *)

(* The four outcomes the CLI can report. Keeping the status -> (line, exit code)
   mapping in a single total function makes it impossible to pair, say, PROVED
   with the wrong exit code. *)
type status =
  | Proved
  | No_cert_found
  | Invalid_input
  | Check_failed

let code_of_status = function
  | Proved -> 0
  | No_cert_found -> 2
  | Invalid_input -> 3
  | Check_failed -> 4
;;

let finish (status : status) =
  let name =
    match status with
    | Proved -> "PROVED"
    | No_cert_found -> "NO_CERT_FOUND"
    | Invalid_input -> "INVALID_INPUT"
    | Check_failed -> "CHECK_FAILED"
  in
  Printf.printf "Status: %s\n" name;
  exit (code_of_status status)
;;

(* --- shared printing ---------------------------------------------------- *)

(* The common "Claim / Equivalent to proving" preamble. *)
let print_preamble ~claim ~vars ~target =
  Printf.printf "Claim:\n  %s\n\n" claim;
  Printf.printf
    "Equivalent to proving:\n  %s >= 0\n\n"
    (Pretty.string_of_poly vars target)
;;

(* Full proof output for an accepted certificate. *)
let print_proved ~claim ~vars ~target ~cert =
  print_preamble ~claim ~vars ~target;
  Printf.printf
    "Certificate:\n  %s\n  = %s\n\n"
    (Pretty.string_of_poly vars target)
    (Certificate.to_string vars cert);
  print_string
    "Reason:\n\
    \  Each summand is a nonnegative rational multiple of a square, so the\n\
    \  right-hand side is >= 0 for all real values. The checker verified the\n\
    \  identity between the two sides exactly.\n\n";
  Printf.printf
    "LaTeX:\n  %s = %s\n\n"
    (Pretty.latex_of_poly vars target)
    (Certificate.to_latex vars cert)
;;

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
  | Checker.Unknown_constraint g ->
    Printf.sprintf
      "the certificate scales %s, which is not a declared hypothesis"
      (Pretty.string_of_poly vars g)
;;

(* --- commands ----------------------------------------------------------- *)

let run_demo () =
  let vars = Prover.hello_world_vars in
  let target = Prover.hello_world_target () in
  let cert = Prover.hello_world_certificate () in
  if Checker.check_sos target cert
  then (
    print_proved ~claim:Prover.hello_world_claim_string ~vars ~target ~cert;
    finish Proved)
  else finish Check_failed
;;

let run_prove (input : string) =
  match Parser.parse input with
  | Error msg ->
    Printf.eprintf "Could not parse the inequality: %s\n" msg;
    finish Invalid_input
  | Ok claim ->
    (match Normalizer.poly_of_claim claim with
     | exception Invalid_argument msg ->
       Printf.eprintf "Could not reduce the inequality: %s\n" msg;
       finish Invalid_input
     | vars, target ->
       (match Prover.prove target with
        | Prover.Proved cert ->
          (* Untrusted output MUST pass the trusted checker before PROVED. *)
          if Checker.check_sos target cert
          then (
            print_proved ~claim:input ~vars ~target ~cert;
            finish Proved)
          else (
            print_preamble ~claim:input ~vars ~target;
            print_string
              "The prover proposed a certificate, but the checker rejected it.\n\n";
            finish Check_failed)
        | Prover.No_certificate_found ->
          print_preamble ~claim:input ~vars ~target;
          print_string
            (String.concat
               "\n"
               [ "No supported sum-of-squares certificate was found. This is not a"
               ; "disproof: the target may still be true but need a certificate the"
               ; "current prover cannot construct (e.g. one requiring an SDP)."
               ; ""
               ; ""
               ]);
          finish No_cert_found))
;;

let run_check (path : string) =
  match Certificate.load_file path with
  | Error msg ->
    Printf.eprintf "Could not load certificate: %s\n" msg;
    finish Invalid_input
  | Ok { claim_text; vars; target; certificate } ->
    (match Checker.check target certificate with
     | Checker.Verified ->
       print_proved ~claim:claim_text ~vars ~target ~cert:certificate;
       finish Proved
     | Checker.Rejected failure ->
       print_preamble ~claim:claim_text ~vars ~target;
       Printf.printf "Certificate rejected: %s\n\n" (string_of_failure ~vars failure);
       finish Check_failed)
;;

(* Emit a Lean proof to stdout (and nothing else on stdout, so the output can be
   redirected straight into a .lean file). Diagnostics go to stderr; the exit
   code still follows the shared status -> code mapping. *)
let run_lean ~(name : string) (input : string) =
  let fail status msg =
    Printf.eprintf "%s\n" msg;
    exit (code_of_status status)
  in
  match Parser.parse input with
  | Error msg ->
    fail Invalid_input (Printf.sprintf "Could not parse the inequality: %s" msg)
  | Ok claim ->
    (match Normalizer.poly_of_claim claim with
     | exception Invalid_argument msg ->
       fail Invalid_input (Printf.sprintf "Could not reduce the inequality: %s" msg)
     | vars, target ->
       (match Prover.prove target with
        | Prover.Proved cert ->
          (* Untrusted output MUST pass the trusted checker before we emit it. *)
          if Checker.check_sos target cert
          then (
            print_string (Lean_export.theorem ~name ~vars target cert);
            exit (code_of_status Proved))
          else
            fail
              Check_failed
              "The prover proposed a certificate, but the checker rejected it."
        | Prover.No_certificate_found ->
          fail
            No_cert_found
            "No supported sum-of-squares certificate was found (not a disproof)."))
;;

let () =
  match Array.to_list Sys.argv with
  | [ _; "demo" ] -> run_demo ()
  | _ :: "prove" :: [ input ] -> run_prove input
  | _ :: "check" :: [ path ] -> run_check path
  | _ :: "lean" :: [ input ] -> run_lean ~name:"aeqb" input
  | _ :: "lean" :: [ input; name ] -> run_lean ~name input
  | [ _ ] | [ _; ("--help" | "-h" | "help") ] -> usage ()
  | _ :: cmd :: _ ->
    Printf.eprintf "Unknown or malformed command: %s\n\n" cmd;
    usage ();
    exit 1
  | [] -> usage () (* unreachable: argv always has the program name *)
;;
