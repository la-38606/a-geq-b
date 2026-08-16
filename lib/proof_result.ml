(** One run of the whole pipeline as data. See the interface for the contract.

    This module orchestrates but decides nothing: [status = Proved] is set in
    exactly one place, after {!Checker} accepts, so every interface built on it
    inherits the trust boundary instead of re-implementing it. *)

type status =
  | Proved
  | No_cert_found
  | Invalid_input
  | Check_failed

type search =
  | Exact_gram
  | Constrained_search of Prover.constrained_strategy
  | Numerical_sdp

type step =
  { title : string
  ; detail : string
  ; trusted : bool
  ; ok : bool
  ; ms : float option
  }

type certificate =
  | Sos of Certificate.t
  | Positivstellensatz of Constrained.t

type t =
  { claim : string
  ; status : status
  ; vars : string list
  ; hypotheses : Constrained.hypothesis list
  ; target : Polynomial.t option
  ; search : search option
  ; certificate : certificate option
  ; error : string option
  ; vacuous : string list
  ; trace : step list
  }

type sdp_solver = Polynomial.t -> (float array array * string, string) result

let string_of_status = function
  | Proved -> "PROVED"
  | No_cert_found -> "NO_CERT_FOUND"
  | Invalid_input -> "INVALID_INPUT"
  | Check_failed -> "CHECK_FAILED"
;;

let search_label = function
  | Exact_gram -> "exact Gram search"
  | Constrained_search Prover.Constant_multipliers ->
    "constrained search: constant multipliers on the hypotheses"
  | Constrained_search Prover.Equality_reduction ->
    "constrained search: reduction modulo the equality hypotheses"
  | Constrained_search Prover.Hypothesis_products ->
    "constrained search: a product of nonnegative hypotheses"
  | Numerical_sdp -> "numerical SDP with exact reconstruction"
;;

let describe_failure ~vars = function
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

(* --- the pipeline -------------------------------------------------------- *)

(* Vacuity warnings, mirroring the CLI's long-standing behaviour: name any
   impossible constant hypothesis specifically; otherwise look for a general
   Positivstellensatz refutation. The refutation calls the untrusted search only
   to decide whether to warn -- never the verdict -- so a failure in it is
   swallowed. *)
let vacuity_warnings ~vars hypotheses =
  let flagged = List.filter Constrained.is_impossible_constant hypotheses in
  match flagged with
  | _ :: _ ->
    List.map
      (fun h ->
         Printf.sprintf
           "the hypothesis '%s' has no solutions, so the claim holds only vacuously."
           (Constrained.string_of_hypothesis vars h))
      flagged
  | [] ->
    let contradictory =
      try Prover.hypotheses_infeasible ~hypotheses with
      | _ -> false
    in
    if contradictory
    then
      [ "the hypotheses are contradictory (they describe an empty region), so the claim \
         holds only vacuously."
      ]
    else []
;;

let prove ?(sdp : sdp_solver option) ?clock (claim_text : string) : t =
  let steps = ref [] in
  let push ?ms ~trusted ~ok title detail =
    steps := { title; detail; trusted; ok; ms } :: !steps
  in
  (* Wall time of [f ()], only when a clock was supplied. *)
  let timed f =
    match clock with
    | None -> None, f ()
    | Some now ->
      let t0 = now () in
      let r = f () in
      Some ((now () -. t0) *. 1000.), r
  in
  let base =
    { claim = claim_text
    ; status = No_cert_found
    ; vars = []
    ; hypotheses = []
    ; target = None
    ; search = None
    ; certificate = None
    ; error = None
    ; vacuous = []
    ; trace = []
    }
  in
  let return (r : t) = { r with trace = List.rev !steps } in
  let invalid partial msg = return { partial with status = Invalid_input; error = Some msg } in
  match Parser.parse claim_text with
  | Error msg ->
    push ~trusted:true ~ok:false "Parse" msg;
    invalid base ("could not parse the inequality: " ^ msg)
  | Ok claim ->
    let side =
      match claim.Ast.hyps with
      | [] -> ""
      | [ _ ] -> " with 1 side condition"
      | hs -> Printf.sprintf " with %d side conditions" (List.length hs)
    in
    push ~trusted:true ~ok:true "Parse" ("recognised an inequality" ^ side);
    (match Normalizer.poly_of_claim claim with
     | exception Invalid_argument msg ->
       push ~trusted:true ~ok:false "Normalize" msg;
       invalid base ("could not reduce the inequality: " ^ msg)
     | vars, target ->
       push
         ~trusted:true
         ~ok:true
         "Normalize"
         (Printf.sprintf "%s  >=  0" (Pretty.string_of_poly vars target));
       let base = { base with vars; target = Some target } in
       (* The trusted check is the single gate to [Proved], for either
          certificate shape and whatever search produced the candidate. [sofar]
          is the record built up to this point (hypotheses, vacuity warnings). *)
       let checked (sofar : t) ~search (cert : certificate) : t =
         let hypotheses = sofar.hypotheses in
         let ms, outcome =
           timed (fun () ->
             match cert with
             | Sos c -> Checker.check target c
             | Positivstellensatz c -> Checker.check_constrained ~hypotheses target c)
         in
         match outcome with
         | Checker.Verified ->
           let detail =
             match cert with
             | Sos _ ->
               "the certificate expands to the target exactly, and every coefficient \
                is nonnegative"
             | Positivstellensatz _ ->
               "the certificate expands to the target exactly, every sum of squares \
                has nonnegative coefficients, and every scaled polynomial is a \
                declared hypothesis"
           in
           push ?ms ~trusted:true ~ok:true "Exact check" detail;
           return
             { sofar with status = Proved; search = Some search; certificate = Some cert }
         | Checker.Rejected failure ->
           let why = describe_failure ~vars failure in
           push ?ms ~trusted:true ~ok:false "Exact check" why;
           return
             { sofar with
               status = Check_failed
             ; error = Some ("the trusted checker rejected the certificate: " ^ why)
             }
       in
       (match claim.Ast.hyps with
        | _ :: _ ->
          (match Constrained.hypotheses_of_claim vars claim with
           | exception Invalid_argument msg ->
             push ~trusted:true ~ok:false "Side conditions" msg;
             invalid base ("could not reduce a side condition: " ^ msg)
           | hypotheses ->
             push
               ~trusted:true
               ~ok:true
               "Side conditions"
               (String.concat
                  "\n"
                  (List.map (Constrained.string_of_hypothesis vars) hypotheses));
             let vacuous = vacuity_warnings ~vars hypotheses in
             let base = { base with hypotheses; vacuous } in
             let ms, result =
               timed (fun () -> Prover.prove_constrained ~hypotheses target)
             in
             (match result with
              | Prover.Proved_constrained (strategy, cert) ->
                push
                  ?ms
                  ~trusted:false
                  ~ok:true
                  "Constrained search"
                  (search_label (Constrained_search strategy));
                checked
                  base
                  ~search:(Constrained_search strategy)
                  (Positivstellensatz cert)
              | Prover.No_constrained_certificate ->
                push
                  ?ms
                  ~trusted:false
                  ~ok:false
                  "Constrained search"
                  "no supported Positivstellensatz certificate found";
                return base))
        | [] ->
          let ms, result = timed (fun () -> Prover.prove target) in
          (match result with
           | Prover.Proved cert ->
             push
               ?ms
               ~trusted:false
               ~ok:true
               "Exact search"
               "found a sum-of-squares certificate (Gram matrix, rational LDL^T)";
             checked base ~search:Exact_gram (Sos cert)
           | Prover.No_certificate_found ->
             push
               ?ms
               ~trusted:false
               ~ok:false
               "Exact search"
               "no certificate over the candidate monomial bases";
             (match sdp with
              | None -> return base
              | Some solve ->
                let ms, solved = timed (fun () -> solve target) in
                (match solved with
                 | Error msg ->
                   push ?ms ~trusted:false ~ok:false "Numerical SDP" msg;
                   return base
                 | Ok (q, note) ->
                   push ?ms ~trusted:false ~ok:true "Numerical SDP" note;
                   let ms, rounded =
                     timed (fun () -> Sdp.certificate_of_solution target q)
                   in
                   (match rounded with
                    | None ->
                      push
                        ?ms
                        ~trusted:false
                        ~ok:false
                        "Rational reconstruction"
                        "no rounding of the numerical Gram matrix gives a certificate \
                         the exact checker accepts";
                      return base
                    | Some cert ->
                      push
                        ?ms
                        ~trusted:false
                        ~ok:true
                        "Rational reconstruction"
                        "rounded the numerical Gram matrix to exact rationals and read \
                         off the squares (LDL^T)";
                      checked base ~search:Numerical_sdp (Sos cert)))))))
;;

(* --- JSON ---------------------------------------------------------------- *)

let search_id = function
  | Exact_gram -> "exact_gram"
  | Constrained_search Prover.Constant_multipliers -> "constrained_constant_multipliers"
  | Constrained_search Prover.Equality_reduction -> "constrained_equality_reduction"
  | Constrained_search Prover.Hypothesis_products -> "constrained_hypothesis_products"
  | Numerical_sdp -> "numerical_sdp"
;;

(* The claim recorded in a constrained certificate file must be the bare
   inequality: the hypotheses are carried explicitly, and the loader re-derives
   the target from the claim alone. The parser treats `given` as a keyword (not
   part of an identifier), so the text before its first keyword occurrence is
   exactly the inequality. *)
let bare_claim (r : t) : string =
  match r.hypotheses with
  | [] -> r.claim
  | _ :: _ ->
    let s = r.claim in
    let n = String.length s in
    let ident_char c =
      ('a' <= c && c <= 'z')
      || ('A' <= c && c <= 'Z')
      || ('0' <= c && c <= '9')
      || c = '_'
    in
    let rec find i =
      if i + 5 > n
      then None
      else if
        String.sub s i 5 = "given"
        && (i = 0 || not (ident_char s.[i - 1]))
        && (i + 5 = n || not (ident_char s.[i + 5]))
      then Some i
      else find (i + 1)
    in
    (match find 0 with
     | Some i -> String.trim (String.sub s 0 i)
     | None ->
       (match r.target with
        | Some p -> Pretty.string_of_poly r.vars p ^ " >= 0"
        | None -> r.claim))
;;

let to_json (r : t) : Yojson.Safe.t =
  let vars = r.vars in
  let opt f = function
    | None -> `Null
    | Some v -> f v
  in
  let poly_json p =
    `Assoc
      [ "text", `String (Pretty.string_of_poly vars p)
      ; "latex", `String (Pretty.latex_of_poly vars p)
      ]
  in
  let hyp_json h =
    let kind =
      match h with
      | Constrained.Nonneg _ -> "nonneg"
      | Constrained.Zero _ -> "zero"
    in
    `Assoc
      [ "kind", `String kind
      ; "text", `String (Constrained.string_of_hypothesis vars h)
      ]
  in
  let cert_json = function
    | Sos c ->
      `Assoc
        [ "kind", `String "sos"
        ; "text", `String (Certificate.to_string vars c)
        ; "latex", `String (Certificate.to_latex vars c)
        ; "file", Certificate.to_json ~claim:(bare_claim r) ~vars c
        ]
    | Positivstellensatz c ->
      `Assoc
        [ "kind", `String "positivstellensatz"
        ; "text", `String (Constrained.to_string vars c)
        ; "latex", `String (Constrained.to_latex vars c)
        ; ( "file"
          , Constrained.to_json
              ~claim:(bare_claim r)
              ~vars
              ~hypotheses:r.hypotheses
              c )
        ]
  in
  let step_json (s : step) =
    `Assoc
      [ "title", `String s.title
      ; "detail", `String s.detail
      ; "trusted", `Bool s.trusted
      ; "ok", `Bool s.ok
      ; "ms", opt (fun m -> `Float m) s.ms
      ]
  in
  `Assoc
    [ "claim", `String r.claim
    ; "status", `String (string_of_status r.status)
    ; "vars", `List (List.map (fun v -> `String v) vars)
    ; "hypotheses", `List (List.map hyp_json r.hypotheses)
    ; "target", opt poly_json r.target
    ; "search", opt (fun s -> `String (search_id s)) r.search
    ; "search_label", opt (fun s -> `String (search_label s)) r.search
    ; "certificate", opt cert_json r.certificate
    ; "error", opt (fun e -> `String e) r.error
    ; "vacuous", `List (List.map (fun w -> `String w) r.vacuous)
    ; "trace", `List (List.map step_json r.trace)
    ]
;;
