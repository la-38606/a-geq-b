(** The web server's hook into the numerical SDP route.

    Pipes the Gram program emitted by {!A_geq_b.Sdp.problem_json} into
    [sdp/solve_sdp.py] (stdin/stdout JSON, the same contract [sdp/prove.py]
    uses) and reads the approximate matrix back. Untrusted like every solver:
    the caller hands the matrix to exact reconstruction and the trusted
    checker, so a wrong answer here costs a missed proof, never a false one.

    The solver needs the project virtualenv (see [sdp/README.md]); when it is
    absent the hook reports that instead of failing, and the interface degrades
    to the exact search alone. *)

open A_geq_b

let script = Filename.concat "sdp" "solve_sdp.py"

(** [true] iff the Python interpreter and the solver script both exist, so the
    SDP route can be offered at all. *)
let available ~python = Sys.file_exists python && Sys.file_exists script

(* All of the subprocess's stdout. *)
let read_all (ic : in_channel) : string =
  let buf = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_channel buf ic 4096
     done
   with
   | End_of_file -> ());
  Buffer.contents buf
;;

let float_of_json = function
  | `Float f -> Some f
  | `Int i -> Some (float_of_int i)
  | _ -> None
;;

(* Decode the solver's {"status", "min_eig", "Q"} reply into the matrix and a
   one-line description for the proof trace. *)
let decode (raw : string) : (float array array * string, string) result =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error m -> Error ("the solver returned malformed JSON: " ^ m)
  | json ->
    let member k = Yojson.Safe.Util.member k json in
    let status =
      match member "status" with
      | `String s -> s
      | _ -> "unknown"
    in
    (match member "Q" with
     | `List rows ->
       (try
          let q =
            Array.of_list
              (List.map
                 (fun row ->
                    Array.of_list
                      (List.map
                         (fun v ->
                            match float_of_json v with
                            | Some f -> f
                            | None -> raise Exit)
                         (Yojson.Safe.Util.to_list row)))
                 rows)
          in
          let eig =
            match float_of_json (member "min_eig") with
            | Some e -> Printf.sprintf ", min eigenvalue %.3g" e
            | None -> ""
          in
          Ok
            ( q
            , Printf.sprintf
                "external solver returned an approximate PSD Gram matrix (status %s%s)"
                status
                eig )
        with
        | Exit | Yojson.Safe.Util.Type_error _ ->
          Error "the solver returned a non-numeric matrix")
     | _ -> Error (Printf.sprintf "the solver found no matrix (status: %s)" status))
;;

(** The {!Proof_result.sdp_solver} hook: emit the Gram SDP for the target, run
    the external solver on it, decode the reply. *)
let solver ~(python : string) : Proof_result.sdp_solver =
  fun target ->
  if not (available ~python)
  then
    Error
      "the numerical solver is not available (create the virtualenv described in \
       sdp/README.md to enable the SDP route)"
  else (
    let problem = Yojson.Safe.to_string (Sdp.problem_json target) in
    let cmd =
      Printf.sprintf "%s %s" (Filename.quote python) (Filename.quote script)
    in
    let ic, oc = Unix.open_process cmd in
    let reply =
      try
        output_string oc problem;
        close_out oc;
        Ok (read_all ic)
      with
      | Sys_error m -> Error ("could not talk to the numerical solver: " ^ m)
    in
    match Unix.close_process (ic, oc), reply with
    | _, Error m -> Error m
    | Unix.WEXITED 0, Ok raw -> decode raw
    | (Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _), Ok _ ->
      Error "the numerical solver exited abnormally")
;;
