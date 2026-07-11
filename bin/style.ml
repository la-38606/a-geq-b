(** Restrained terminal styling for the CLI.

    The command-line output is the tool's user interface, so it follows a small,
    consistent presentation system: faint labels for structure, near-default text
    for content, and a single colour cue on the final result.

    ANSI colour is emitted only when standard output is an interactive terminal
    and the [NO_COLOR] environment variable is unset. Redirected or captured
    output (pipes, files, and the corpus harnesses, which read the exact
    [Status:] line back) therefore stays plain and machine-readable. *)

let colour : bool Lazy.t =
  lazy (Unix.isatty Unix.stdout && Sys.getenv_opt "NO_COLOR" = None)
;;

(* Wrap [s] in the SGR sequence [code], but only when colour is enabled. *)
let paint (code : string) (s : string) : string =
  if Lazy.force colour then Printf.sprintf "\027[%sm%s\027[0m" code s else s
;;

let label (s : string) : string = paint "2" s (* faint: structural labels *)
let ok (s : string) : string = paint "32" s (* green: a positive result *)
let bad (s : string) : string = paint "31" s (* red: a failure or invalid input *)

(** Indent every non-empty line of [s] by two spaces. *)
let indent (s : string) : string =
  String.split_on_char '\n' s
  |> List.map (fun line -> if String.equal line "" then "" else "  " ^ line)
  |> String.concat "\n"
;;
