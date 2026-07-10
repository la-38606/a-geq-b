(** Positivstellensatz certificates for {i constrained} inequalities.

    An unconstrained certificate ({!Certificate}) proves [p >= 0] everywhere by
    writing [p] as a sum of squares.  Many olympiad inequalities instead hold
    only on a region cut out by hypotheses — [a >= 0], [a + b + c = 1],
    [abc = 1], … .  There we prove [p >= 0] on

    {[ { x | g_1(x) >= 0, …, h_1(x) = 0, … } ]}

    with a certificate of the Positivstellensatz shape

    {[ p = sigma_0 + sum_i sigma_i * g_i + sum_j lambda_j * h_j ]}

    where each [sigma] is a sum of squares (so [>= 0]) and each [lambda_j] is an
    arbitrary polynomial.  On the feasible set every [g_i >= 0] and every
    [h_j = 0], so [sigma_i g_i >= 0] and [lambda_j h_j = 0]; hence [p >= 0]
    there.  This module holds the {i data}; the trusted {!Checker} decides
    whether the claimed identity and sign conditions actually hold. *)

(** A hypothesis constraining the domain. *)
type hypothesis =
  | Nonneg of Polynomial.t (** [g >= 0] *)
  | Zero of Polynomial.t (** [h = 0] *)

(** One product term of the certificate.  Its kind is matched to the kind of
    hypothesis it may use, so the two cannot be confused. *)
type product =
  | Times_nonneg of
      { multiplier : Certificate.t (** an SOS [sigma], hence [>= 0] *)
      ; nonneg : Polynomial.t (** the [Nonneg] hypothesis [g] it scales *)
      } (** contributes [sigma * g], which is [>= 0] on the domain *)
  | Times_zero of
      { multiplier : Polynomial.t (** any polynomial [lambda] *)
      ; zero : Polynomial.t (** the [Zero] hypothesis [h] it scales *)
      } (** contributes [lambda * h], which is [0] on the domain *)

(** A certificate that [p >= 0] on the set cut out by the hypotheses:
    [p = base + sum (sigma_i * g_i) + sum (lambda_j * h_j)].  [base] and every
    {!Times_nonneg} multiplier are sums of squares. *)
type t =
  { base : Certificate.t (** the unconstrained SOS part [sigma_0] *)
  ; products : product list
  }

let nonneg (g : Polynomial.t) : hypothesis = Nonneg g
let zero (h : Polynomial.t) : hypothesis = Zero h

let times_nonneg ~(multiplier : Certificate.t) ~(nonneg : Polynomial.t) : product =
  Times_nonneg { multiplier; nonneg }
;;

let times_zero ~(multiplier : Polynomial.t) ~(zero : Polynomial.t) : product =
  Times_zero { multiplier; zero }
;;

let make ~(base : Certificate.t) ~(products : product list) : t = { base; products }

(** Normalize a claim's side conditions into hypotheses under the variable
    context [ctx].  [a >= b] and [a <= b] become [Nonneg] hypotheses (of [a - b]
    and [b - a] respectively); [a = b] becomes [Zero (a - b)].  Raises
    [Invalid_argument] (via {!Normalizer.poly_of_expr}) on an unknown variable or
    a non-polynomial (non-constant division) side condition. *)
let hypotheses_of_claim (ctx : Normalizer.context) (claim : Ast.claim) : hypothesis list =
  let sub a b = Normalizer.poly_of_expr ctx (Ast.Sub (a, b)) in
  List.map
    (fun (h : Ast.hyp) ->
       match h.hyp_op with
       | Ast.Hyp_ge -> Nonneg (sub h.hyp_lhs h.hyp_rhs)
       | Ast.Hyp_le -> Nonneg (sub h.hyp_rhs h.hyp_lhs)
       | Ast.Hyp_eq -> Zero (sub h.hyp_lhs h.hyp_rhs))
    claim.hyps
;;

(* --- rendering ---------------------------------------------------------- *)

let string_of_hypothesis (vars : Pretty.vars) : hypothesis -> string = function
  | Nonneg g -> Printf.sprintf "%s >= 0" (Pretty.string_of_poly vars g)
  | Zero h -> Printf.sprintf "%s = 0" (Pretty.string_of_poly vars h)
;;

let string_of_product (vars : Pretty.vars) : product -> string = function
  | Times_nonneg { multiplier; nonneg } ->
    Printf.sprintf
      "(%s)*(%s)"
      (Certificate.to_string vars multiplier)
      (Pretty.string_of_poly vars nonneg)
  | Times_zero { multiplier; zero } ->
    Printf.sprintf
      "(%s)*(%s)"
      (Pretty.string_of_poly vars multiplier)
      (Pretty.string_of_poly vars zero)
;;

(** Render the certificate's right-hand side [base + sum products]. *)
let to_string (vars : Pretty.vars) (cert : t) : string =
  let parts =
    (match cert.base with
     | [] -> []
     | base -> [ Certificate.to_string vars base ])
    @ List.map (string_of_product vars) cert.products
  in
  match parts with
  | [] -> "0"
  | _ -> String.concat " + " parts
;;

let latex_of_product (vars : Pretty.vars) : product -> string = function
  | Times_nonneg { multiplier; nonneg } ->
    Printf.sprintf
      "\\left(%s\\right)\\left(%s\\right)"
      (Certificate.to_latex vars multiplier)
      (Pretty.latex_of_poly vars nonneg)
  | Times_zero { multiplier; zero } ->
    Printf.sprintf
      "\\left(%s\\right)\\left(%s\\right)"
      (Pretty.latex_of_poly vars multiplier)
      (Pretty.latex_of_poly vars zero)
;;

let to_latex (vars : Pretty.vars) (cert : t) : string =
  let parts =
    (match cert.base with
     | [] -> []
     | base -> [ Certificate.to_latex vars base ])
    @ List.map (latex_of_product vars) cert.products
  in
  match parts with
  | [] -> "0"
  | _ -> String.concat " + " parts
;;

(* --- JSON --------------------------------------------------------------- *)

let term_json (vars : Pretty.vars) (t : Certificate.term) : Yojson.Safe.t =
  `Assoc
    [ "coeff", `String (Rational.to_string t.coeff)
    ; "poly", `String (Pretty.string_of_poly vars t.poly)
    ]
;;

let sos_json (vars : Pretty.vars) (sos : Certificate.t) : Yojson.Safe.t =
  `List (List.map (term_json vars) sos)
;;

let hypothesis_json (vars : Pretty.vars) : hypothesis -> Yojson.Safe.t = function
  | Nonneg g ->
    `Assoc [ "poly", `String (Pretty.string_of_poly vars g); "kind", `String "nonneg" ]
  | Zero h ->
    `Assoc [ "poly", `String (Pretty.string_of_poly vars h); "kind", `String "zero" ]
;;

let product_json (vars : Pretty.vars) : product -> Yojson.Safe.t = function
  | Times_nonneg { multiplier; nonneg } ->
    `Assoc
      [ "kind", `String "nonneg"
      ; "multiplier", sos_json vars multiplier
      ; "constraint", `String (Pretty.string_of_poly vars nonneg)
      ]
  | Times_zero { multiplier; zero } ->
    `Assoc
      [ "kind", `String "zero"
      ; "multiplier", `String (Pretty.string_of_poly vars multiplier)
      ; "constraint", `String (Pretty.string_of_poly vars zero)
      ]
;;

(** Serialise to the constrained JSON format (see [examples/]).  The hypotheses
    are carried explicitly, so the [claim] string is just the ["A >= B"]
    inequality. *)
let to_json
      ~(claim : string)
      ~(vars : Pretty.vars)
      ~(hypotheses : hypothesis list)
      (cert : t)
  : Yojson.Safe.t
  =
  `Assoc
    [ "claim", `String claim
    ; "variables", `List (List.map (fun v -> `String v) vars)
    ; "hypotheses", `List (List.map (hypothesis_json vars) hypotheses)
    ; ( "certificate"
      , `Assoc
          [ "base", sos_json vars cert.base
          ; "products", `List (List.map (product_json vars) cert.products)
          ] )
    ]
;;

(** A constrained certificate loaded from JSON, with the claim, the target
    polynomial [A - B], and the hypotheses cutting out the domain.  All
    polynomials are built in the [vars] context so their indices line up. *)
type parsed =
  { claim_text : string
  ; vars : string list
  ; target : Polynomial.t
  ; hypotheses : hypothesis list
  ; certificate : t
  }

(** Load from a parsed JSON value.  Returns [Error msg] — never raises — on any
    malformation.  Validates {i shape} only; the caller must still run the
    trusted {!Checker.check_constrained} on the result. *)
let of_json (json : Yojson.Safe.t) : (parsed, string) result =
  let module U = Yojson.Safe.Util in
  let exception Bad of string in
  let string_field j name =
    try j |> U.member name |> U.to_string with
    | _ -> raise (Bad (Printf.sprintf "missing or non-string field %S" name))
  in
  let poly_of_string ~vars src =
    match Parser.parse_expr src with
    | Error m -> raise (Bad (Printf.sprintf "cannot parse polynomial %S: %s" src m))
    | Ok e ->
      (try Normalizer.poly_of_expr vars e with
       | Invalid_argument m -> raise (Bad m))
  in
  try
    let claim_text = string_field json "claim" in
    let vars =
      try json |> U.member "variables" |> U.to_list |> List.map U.to_string with
      | _ -> raise (Bad "missing or invalid field 'variables'")
    in
    let target =
      match Parser.parse claim_text with
      | Error m -> raise (Bad ("cannot parse claim: " ^ m))
      | Ok c ->
        (try snd (Normalizer.poly_of_claim ~context:vars c) with
         | Invalid_argument m -> raise (Bad m))
    in
    let parse_term j =
      let coeff_s = string_field j "coeff" in
      let coeff =
        match Rational.of_string_opt coeff_s with
        | Some q -> q
        | None -> raise (Bad (Printf.sprintf "malformed rational coefficient %S" coeff_s))
      in
      Certificate.term coeff (poly_of_string ~vars (string_field j "poly"))
    in
    let parse_sos j =
      try List.map parse_term (U.to_list j) with
      | U.Type_error _ -> raise (Bad "an SOS field is not a list of terms")
    in
    let parse_hypothesis j =
      let poly = poly_of_string ~vars (string_field j "poly") in
      match string_field j "kind" with
      | "nonneg" -> Nonneg poly
      | "zero" -> Zero poly
      | k -> raise (Bad (Printf.sprintf "unknown hypothesis kind %S" k))
    in
    let parse_product j =
      match string_field j "kind" with
      | "nonneg" ->
        times_nonneg
          ~multiplier:(parse_sos (U.member "multiplier" j))
          ~nonneg:(poly_of_string ~vars (string_field j "constraint"))
      | "zero" ->
        times_zero
          ~multiplier:(poly_of_string ~vars (string_field j "multiplier"))
          ~zero:(poly_of_string ~vars (string_field j "constraint"))
      | k -> raise (Bad (Printf.sprintf "unknown product kind %S" k))
    in
    let hypotheses =
      try json |> U.member "hypotheses" |> U.to_list |> List.map parse_hypothesis with
      | U.Type_error _ -> raise (Bad "missing or invalid field 'hypotheses'")
    in
    let cert_json = U.member "certificate" json in
    let base = parse_sos (U.member "base" cert_json) in
    let products =
      try U.member "products" cert_json |> U.to_list |> List.map parse_product with
      | U.Type_error _ -> raise (Bad "missing or invalid certificate field 'products'")
    in
    Ok { claim_text; vars; target; hypotheses; certificate = make ~base ~products }
  with
  | Bad m -> Error m
;;

(** Parse from a JSON string. Wraps JSON-syntax errors into [Error]. *)
let of_string (s : string) : (parsed, string) result =
  match Yojson.Safe.from_string s with
  | json -> of_json json
  | exception Yojson.Json_error m -> Error ("JSON syntax error: " ^ m)
;;

(** Read and parse a JSON file. Wraps I/O and JSON-syntax errors into [Error]. *)
let load_file (path : string) : (parsed, string) result =
  match Yojson.Safe.from_file path with
  | json -> of_json json
  | exception Sys_error m -> Error m
  | exception Yojson.Json_error m -> Error ("JSON syntax error: " ^ m)
;;

(** The two certificate file shapes: an unconstrained sum-of-squares
    ({!Certificate}) or a constrained Positivstellensatz certificate. *)
type any =
  | Unconstrained of Certificate.parsed
  | Constrained of parsed

(** Load a certificate file of {i either} shape, detected by the presence of a
    ["certificate"] object (constrained) versus a ["sos"] list (unconstrained).
    Returns [Error msg] (never raises) on any malformation. *)
let load_any (path : string) : (any, string) result =
  match Yojson.Safe.from_file path with
  | exception Sys_error m -> Error m
  | exception Yojson.Json_error m -> Error ("JSON syntax error: " ^ m)
  | json ->
    if Yojson.Safe.Util.member "certificate" json = `Null
    then Result.map (fun p -> Unconstrained p) (Certificate.of_json json)
    else Result.map (fun p -> Constrained p) (of_json json)
;;
