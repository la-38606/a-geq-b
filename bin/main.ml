(** A>=B command-line entry point.

    For this skeleton the CLI supports [--help] and [demo].  The [prove] /
    [check] subcommands from the design are stubbed until the parser and JSON
    loader land. *)

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
         "  a-geq-b --help        Show this message";
         "  a-geq-b demo          Run the built-in hello-world proof";
         "";
         "Planned (not yet implemented):";
         "  a-geq-b prove \"a^2+b^2 >= 2*a*b\"   Parse and auto-prove an inequality";
         "  a-geq-b check cert.json              Check a JSON certificate";
         "" ])

(* Run the hardcoded hello-world proof, sending the certificate through the
   trusted checker before printing a status. *)
let run_demo () =
  let vars = Prover.hello_world_vars in
  let p = Prover.hello_world_target () in
  let cert = Prover.hello_world_certificate () in
  let verified = Checker.check_sos p cert in
  Printf.printf "Claim:\n  %s\n\n" Prover.hello_world_claim_string;
  Printf.printf "Equivalent to proving:\n  %s >= 0\n\n" (Pretty.string_of_poly vars p);
  Printf.printf "Certificate:\n  %s\n  = %s\n\n"
    (Pretty.string_of_poly vars p)
    (Certificate.to_string vars cert);
  print_string
    "Reason:\n\
    \  Each summand is a nonnegative rational multiple of a square, so the\n\
    \  right-hand side is >= 0 for all real values. The checker verified the\n\
    \  identity between the two sides exactly.\n\n";
  Printf.printf "LaTeX:\n  %s = %s\n\n"
    (Pretty.latex_of_poly vars p)
    (Certificate.to_latex vars cert);
  if verified then (print_string "Status: PROVED\n"; exit 0)
  else (print_string "Status: CHECK_FAILED\n"; exit 1)

let () =
  match Array.to_list Sys.argv with
  | _ :: "demo" :: [] -> run_demo ()
  | [ _ ] | _ :: ("--help" | "-h" | "help") :: [] -> usage ()
  | _ :: cmd :: _ ->
      Printf.eprintf "Unknown or unsupported command: %s\n\n" cmd;
      usage ();
      exit 1
  | [] -> usage () (* unreachable: argv always has the program name *)
