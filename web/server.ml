(** A>=B local web interface.

    A single-user, localhost-only HTTP listener over the same prover library
    the CLI uses. The browser talks to two JSON endpoints and gets everything
    else as static files:

    - [POST /api/prove] {"claim": "..."} -> the {!A_geq_b.Proof_result} record
      as JSON (status, certificate, trace, timings);
    - [POST /api/lean]  {"claim": "...", "name": "..."} -> a self-contained
      Lean proof of the claim, or an explanation of why not.

    Design note: this is a hand-written HTTP/1.1 subset (GET/POST, headers,
    Content-Length), not a framework. The tool is local and single-user, the
    request grammar needed is tiny, and keeping the dependency surface at
    zarith + yojson means the trusted core's build is unchanged by the web
    layer. Requests are served one at a time; every proof search the corpus
    exercises answers in milliseconds, and the SDP route in about a second.

    No mathematics lives here. Proving and checking happen in {!Proof_result}
    (which gates PROVED on the trusted checker); the numerical solver hook is
    {!Sdp_bridge}. *)

open A_geq_b

(* --- HTTP plumbing ------------------------------------------------------ *)

type request =
  { meth : string
  ; path : string (* origin-form, query string stripped *)
  ; body : string
  }

let max_body = 65536

exception Bad_request of string

(* Read one CRLF-terminated line, without the \r. *)
let read_line_crlf (ic : in_channel) : string =
  let line = input_line ic in
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line
;;

let read_request (ic : in_channel) : request =
  let request_line = read_line_crlf ic in
  let meth, target =
    match String.split_on_char ' ' request_line with
    | [ m; t; _version ] -> m, t
    | _ -> raise (Bad_request "malformed request line")
  in
  (* Headers: we only need Content-Length. *)
  let content_length = ref 0 in
  let rec headers () =
    match read_line_crlf ic with
    | "" -> ()
    | line ->
      (match String.index_opt line ':' with
       | Some i ->
         let name = String.lowercase_ascii (String.trim (String.sub line 0 i)) in
         let value =
           String.trim (String.sub line (i + 1) (String.length line - i - 1))
         in
         if name = "content-length"
         then (
           match int_of_string_opt value with
           | Some n when n >= 0 && n <= max_body -> content_length := n
           | Some _ -> raise (Bad_request "request body too large")
           | None -> raise (Bad_request "malformed Content-Length"))
       | None -> ());
      headers ()
  in
  headers ();
  let body =
    if !content_length = 0
    then ""
    else (
      let buf = Bytes.create !content_length in
      really_input ic buf 0 !content_length;
      Bytes.to_string buf)
  in
  let path =
    match String.index_opt target '?' with
    | Some i -> String.sub target 0 i
    | None -> target
  in
  { meth; path; body }
;;

let reason_of_code = function
  | 200 -> "OK"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | _ -> "Internal Server Error"
;;

let respond (oc : out_channel) ~(code : int) ~(content_type : string) (body : string)
  : unit
  =
  Printf.fprintf
    oc
    "HTTP/1.1 %d %s\r\n\
     Content-Type: %s\r\n\
     Content-Length: %d\r\n\
     Cache-Control: no-store\r\n\
     Connection: close\r\n\
     \r\n"
    code
    (reason_of_code code)
    content_type
    (String.length body);
  output_string oc body;
  flush oc
;;

let respond_json oc ~code body = respond oc ~code ~content_type:"application/json" body

let json_error (msg : string) : string =
  Yojson.Safe.to_string (`Assoc [ "error", `String msg ])
;;

(* --- static files ------------------------------------------------------- *)

(* Exact-path whitelist: nothing outside this table is ever read, so there is
   no path to traverse. Files are re-read per request (local tool; editing the
   UI and refreshing should just work). *)
let static_routes : (string * string * string) list =
  [ "/", "index.html", "text/html; charset=utf-8"
  ; "/how-it-works", "how-it-works.html", "text/html; charset=utf-8"
  ; "/style.css", "style.css", "text/css; charset=utf-8"
  ; "/app.js", "app.js", "application/javascript; charset=utf-8"
  ; "/examples.json", "examples.json", "application/json"
  ]
;;

let serve_static (oc : out_channel) ~(static_dir : string) (path : string) : unit =
  match List.find_opt (fun (route, _, _) -> route = path) static_routes with
  | None -> respond oc ~code:404 ~content_type:"text/plain" "not found\n"
  | Some (_, file, content_type) ->
    let full = Filename.concat static_dir file in
    (match In_channel.with_open_bin full In_channel.input_all with
     | body -> respond oc ~code:200 ~content_type body
     | exception Sys_error _ ->
       respond
         oc
         ~code:404
         ~content_type:"text/plain"
         (Printf.sprintf "missing static file: %s\n" full))
;;

(* --- API ---------------------------------------------------------------- *)

(* Extract the string field [key] from a JSON request body. *)
let string_field (body : string) (key : string) : string option =
  match Yojson.Safe.from_string body with
  | exception Yojson.Json_error _ -> None
  | json ->
    (match Yojson.Safe.Util.member key json with
     | `String s -> Some s
     | _ -> None)
;;

let handle_prove (oc : out_channel) ~(sdp : Proof_result.sdp_solver) (body : string)
  : unit
  =
  match string_field body "claim" with
  | None ->
    respond_json oc ~code:400 (json_error "expected a JSON object with a string 'claim'")
  | Some claim ->
    let result = Proof_result.prove ~sdp ~clock:Unix.gettimeofday claim in
    respond_json oc ~code:200 (Yojson.Safe.to_string (Proof_result.to_json result))
;;

(* Prove, then emit the Lean theorem for the accepted certificate. Mirrors the
   CLI `lean` command: unconstrained sum-of-squares proofs only (the emitted
   proof is `ring` + `positivity`). App-level failures are 200s with an
   "error" field -- they are answers, not protocol errors. *)
let handle_lean (oc : out_channel) ~(sdp : Proof_result.sdp_solver) (body : string)
  : unit
  =
  match string_field body "claim" with
  | None ->
    respond_json oc ~code:400 (json_error "expected a JSON object with a string 'claim'")
  | Some claim ->
    let name =
      match string_field body "name" with
      | Some n when n <> "" -> n
      | _ -> "aeqb"
    in
    let r = Proof_result.prove ~sdp claim in
    let app_error msg =
      respond_json
        oc
        ~code:200
        (Yojson.Safe.to_string
           (`Assoc
              [ "error", `String msg
              ; "status", `String (Proof_result.string_of_status r.status)
              ]))
    in
    (match r.status, r.certificate, r.target with
     | Proof_result.Proved, Some (Proof_result.Sos cert), Some target ->
       let lean = Lean_export.theorem ~name ~vars:r.vars target cert in
       respond_json
         oc
         ~code:200
         (Yojson.Safe.to_string (`Assoc [ "lean", `String lean ]))
     | Proof_result.Proved, Some (Proof_result.Positivstellensatz _), _ ->
       app_error
         "Lean export covers unconstrained sum-of-squares proofs only; this proof \
          uses side conditions."
     | _ ->
       app_error
         (match r.error with
          | Some e -> e
          | None -> "no supported certificate was found (this is not a disproof)"))
;;

(* --- server ------------------------------------------------------------- *)

let handle_connection ~static_dir ~sdp (fd : Unix.file_descr) : unit =
  let ic = Unix.in_channel_of_descr fd in
  let oc = Unix.out_channel_of_descr fd in
  (try
     let req = read_request ic in
     match req.meth, req.path with
     | "POST", "/api/prove" -> handle_prove oc ~sdp req.body
     | "POST", "/api/lean" -> handle_lean oc ~sdp req.body
     | "GET", path -> serve_static oc ~static_dir path
     | _, ("/api/prove" | "/api/lean") ->
       respond_json oc ~code:405 (json_error "use POST")
     | _ -> respond oc ~code:405 ~content_type:"text/plain" "method not allowed\n"
   with
   | Bad_request msg -> (try respond_json oc ~code:400 (json_error msg) with _ -> ())
   | End_of_file | Sys_error _ -> ()
   | e ->
     (try respond_json oc ~code:500 (json_error (Printexc.to_string e)) with
      | _ -> ()));
  try Unix.close fd with
  | _ -> ()
;;

let usage () =
  print_string
    (String.concat
       "\n"
       [ "a-geq-b-web - the A>=B prover in a local browser page."
       ; ""
       ; "Options:"
       ; "  --port <n>      listen on 127.0.0.1:<n> (default 8642)"
       ; "  --static <dir>  static UI files (default web/static)"
       ; "  --python <exe>  interpreter with cvxpy for the SDP route"
       ; "                  (default .venv/bin/python; the route is skipped"
       ; "                  when the interpreter is missing)"
       ; ""
       ; "Run from the repository root, e.g.:  dune exec a-geq-b-web"
       ; ""
       ])
;;

let () =
  let port = ref 8642 in
  let static_dir = ref (Filename.concat "web" "static") in
  let python = ref (Filename.concat ".venv" (Filename.concat "bin" "python")) in
  let rec parse_args = function
    | [] -> ()
    | "--port" :: v :: rest ->
      (match int_of_string_opt v with
       | Some p when p > 0 && p < 65536 -> port := p
       | _ ->
         prerr_endline "error: --port expects a port number";
         exit 2);
      parse_args rest
    | "--static" :: v :: rest ->
      static_dir := v;
      parse_args rest
    | "--python" :: v :: rest ->
      python := v;
      parse_args rest
    | ("--help" | "-h") :: _ ->
      usage ();
      exit 0
    | arg :: _ ->
      Printf.eprintf "error: unknown argument %s (try --help)\n" arg;
      exit 2
  in
  parse_args (List.tl (Array.to_list Sys.argv));
  if not (Sys.file_exists (Filename.concat !static_dir "index.html"))
  then
    Printf.eprintf
      "warning: %s/index.html not found; run from the repository root or pass --static.\n"
      !static_dir;
  (* A client hanging up mid-response must not kill the server. *)
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  (* Localhost only: this is a local tool, never a network service. *)
  (try Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, !port)) with
   | Unix.Unix_error (Unix.EADDRINUSE, _, _) ->
     Printf.eprintf "error: port %d is already in use (try --port).\n" !port;
     exit 1);
  Unix.listen sock 16;
  let sdp = Sdp_bridge.solver ~python:!python in
  Printf.printf "A>=B web interface: http://127.0.0.1:%d\n" !port;
  Printf.printf
    "numerical SDP route: %s\n"
    (if Sdp_bridge.available ~python:!python
     then "available (" ^ !python ^ ")"
     else "unavailable (see sdp/README.md); exact search only");
  print_string "Press Ctrl-C to stop.\n";
  flush stdout;
  while true do
    let fd, _addr = Unix.accept sock in
    handle_connection ~static_dir:!static_dir ~sdp fd
  done
;;
