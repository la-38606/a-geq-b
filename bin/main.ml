(** A>=B command-line entry point.

    Commands:
    - [--help]            usage
    - [demo]              the built-in hardcoded proof
    - [prove "<ineq>"]    parse + (attempt to) auto-prove an inequality
    - [check <file.json>] load and check a JSON certificate (plain or constrained)
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
  let heading s = Style.label s in
  (* Command reference, aligned so every description starts in the same column. *)
  let command name desc = Printf.sprintf "  %-22s%s" name desc in
  print_string
    (String.concat
       "\n"
       [ "A>=B - a sum-of-squares prover for polynomial inequalities."
       ; ""
       ; description
       ; ""
       ; heading "Usage"
       ; "  a-geq-b <command> [arguments]"
       ; ""
       ; heading "Commands"
       ; command "demo" "Run the built-in worked example"
       ; command "prove \"<inequality>\"" "Search for a certificate and report the result"
       ; command "check <file.json>" "Verify a certificate (plain or constrained)"
       ; command "lean \"<inequality>\"" "Emit a machine-checkable Lean proof to stdout"
       ; command "--help" "Show this message"
       ; ""
       ; heading "Side conditions"
       ; "  Attach hypotheses with `given`, e.g."
       ; "    a-geq-b prove \"a*b >= 0 given a >= 0, b >= 0\""
       ; ""
       ; heading "Exit status"
       ; "  0 PROVED    2 NO_CERT_FOUND    3 INVALID_INPUT    4 CHECK_FAILED"
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
  (* The label and format stay exactly "Status: <NAME>" so tools that read the
     result back keep working; only the name is coloured, and only on a terminal
     (never under capture, so the parsed text is unchanged). *)
  let shown =
    match status with
    | Proved -> Style.ok name
    | Invalid_input | Check_failed -> Style.bad name
    | No_cert_found -> name
  in
  Printf.printf "Status: %s\n" shown;
  exit (code_of_status status)
;;

(* --- presentation ------------------------------------------------------- *)

(* A labelled section: a faint label, then the content indented under it. Every
   part of a report (claim, hypotheses, target, certificate, export) is printed
   this way, which gives the output a single, consistent structure. *)
let section (label : string) (content : string) : unit =
  Printf.printf "%s\n%s\n\n" (Style.label label) (Style.indent content)
;;

(* A faint, indented secondary note. The caller supplies the line breaks. *)
let note (text : string) : unit =
  List.iter
    (fun line -> Printf.printf "  %s\n" (Style.label line))
    (String.split_on_char '\n' text);
  print_newline ()
;;

(* Claim + reduced target: the input and the intermediate step, shared by the
   proved and not-proved reports. *)
let preamble ~claim ~vars ~target =
  section "Claim" claim;
  section "Reduces to" (Printf.sprintf "%s  >= 0" (Pretty.string_of_poly vars target))
;;

(* As {!preamble}, but listing the hypotheses of a constrained claim first. *)
let preamble_constrained ~claim ~vars ~hypotheses ~target =
  section "Claim" claim;
  (match hypotheses with
   | [] -> ()
   | _ ->
     section
       "Assuming"
       (String.concat "\n" (List.map (Constrained.string_of_hypothesis vars) hypotheses)));
  let domain =
    match hypotheses with
    | [] -> ""
    | _ -> "   (on the domain above)"
  in
  section
    "Reduces to"
    (Printf.sprintf "%s  >= 0%s" (Pretty.string_of_poly vars target) domain)
;;

(* Full report for an accepted (unconstrained) certificate. *)
let print_proved ~claim ~vars ~target ~cert =
  preamble ~claim ~vars ~target;
  section
    "Certificate"
    (Printf.sprintf
       "%s\n  = %s"
       (Pretty.string_of_poly vars target)
       (Certificate.to_string vars cert));
  note
    (String.concat
       "\n"
       [ "Each summand is a nonnegative rational multiple of a square, so the sum"
       ; "is nonnegative for all real inputs; the checker verified the identity."
       ]);
  section
    "LaTeX"
    (Printf.sprintf
       "%s = %s"
       (Pretty.latex_of_poly vars target)
       (Certificate.to_latex vars cert))
;;

(* Full report for an accepted constrained (Positivstellensatz) certificate. *)
let print_proved_constrained ~claim ~vars ~hypotheses ~target ~cert =
  preamble_constrained ~claim ~vars ~hypotheses ~target;
  section
    "Certificate"
    (Printf.sprintf
       "%s\n  = %s"
       (Pretty.string_of_poly vars target)
       (Constrained.to_string vars cert));
  note
    (String.concat
       "\n"
       [ "On that domain each term is a square, a square times a nonnegative"
       ; "hypothesis, or a multiple of a vanishing one; the identity was verified."
       ]);
  section
    "LaTeX"
    (Printf.sprintf
       "%s = %s"
       (Pretty.latex_of_poly vars target)
       (Constrained.to_latex vars cert))
;;

(* Warn (to stderr) about any hypothesis with an empty solution set: a claim
   "proved" under it holds only vacuously. *)
let warn_vacuous ~vars hypotheses =
  List.iter
    (fun h ->
       if Constrained.is_impossible_constant h
       then
         Printf.eprintf
           "warning: the hypothesis '%s' has no solutions, so the claim holds only \
            vacuously.\n"
           (Constrained.string_of_hypothesis vars h))
    hypotheses
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
    Printf.eprintf "error: could not parse the inequality: %s\n" msg;
    finish Invalid_input
  | Ok claim ->
    (match Normalizer.poly_of_claim claim with
     | exception Invalid_argument msg ->
       Printf.eprintf "error: could not reduce the inequality: %s\n" msg;
       finish Invalid_input
     | vars, target ->
       (match claim.Ast.hyps with
        | _ :: _ ->
          (* Constrained claim: search for a Positivstellensatz certificate. *)
          (match Constrained.hypotheses_of_claim vars claim with
           | exception Invalid_argument msg ->
             Printf.eprintf "error: could not reduce a side condition: %s\n" msg;
             finish Invalid_input
           | hypotheses ->
             warn_vacuous ~vars hypotheses;
             (match Prover.prove_constrained ~hypotheses target with
              | Prover.Proved_constrained cert ->
                (* Untrusted output MUST pass the trusted checker before PROVED. *)
                if Checker.check_constrained_ok ~hypotheses target cert
                then (
                  print_proved_constrained ~claim:input ~vars ~hypotheses ~target ~cert;
                  finish Proved)
                else (
                  preamble_constrained ~claim:input ~vars ~hypotheses ~target;
                  note
                    "The prover proposed a certificate, but the trusted checker rejected \
                     it.";
                  finish Check_failed)
              | Prover.No_constrained_certificate ->
                preamble_constrained ~claim:input ~vars ~hypotheses ~target;
                note
                  (String.concat
                     "\n"
                     [ "No supported Positivstellensatz certificate was found. This is \
                        not a"
                     ; "disproof: the constrained search does not yet cover every case (a"
                     ; "non-constant square multiplier, or a product of three or more"
                     ; "hypotheses, needs the semidefinite step)."
                     ]);
                finish No_cert_found))
        | [] ->
          (match Prover.prove target with
           | Prover.Proved cert ->
             (* Untrusted output MUST pass the trusted checker before PROVED. *)
             if Checker.check_sos target cert
             then (
               print_proved ~claim:input ~vars ~target ~cert;
               finish Proved)
             else (
               preamble ~claim:input ~vars ~target;
               note
                 "The prover proposed a certificate, but the trusted checker rejected it.";
               finish Check_failed)
           | Prover.No_certificate_found ->
             preamble ~claim:input ~vars ~target;
             note
               (String.concat
                  "\n"
                  [ "No supported sum-of-squares certificate was found. This is not a"
                  ; "disproof: the target may be true but need a certificate this prover"
                  ; "cannot yet build (e.g. one requiring the semidefinite step)."
                  ]);
             finish No_cert_found)))
;;

let run_check (path : string) =
  match Constrained.load_any path with
  | Error msg ->
    Printf.eprintf "error: could not load certificate: %s\n" msg;
    finish Invalid_input
  | Ok (Constrained.Unconstrained { claim_text; vars; target; certificate }) ->
    (match Checker.check target certificate with
     | Checker.Verified ->
       print_proved ~claim:claim_text ~vars ~target ~cert:certificate;
       finish Proved
     | Checker.Rejected failure ->
       preamble ~claim:claim_text ~vars ~target;
       section "Rejected" (string_of_failure ~vars failure);
       finish Check_failed)
  | Ok (Constrained.Constrained { claim_text; vars; target; hypotheses; certificate }) ->
    warn_vacuous ~vars hypotheses;
    (match Checker.check_constrained ~hypotheses target certificate with
     | Checker.Verified ->
       print_proved_constrained
         ~claim:claim_text
         ~vars
         ~hypotheses
         ~target
         ~cert:certificate;
       finish Proved
     | Checker.Rejected failure ->
       preamble_constrained ~claim:claim_text ~vars ~hypotheses ~target;
       section "Rejected" (string_of_failure ~vars failure);
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
