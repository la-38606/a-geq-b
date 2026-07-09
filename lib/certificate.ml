(** Sum-of-squares certificates.

    A certificate for [p >= 0] is a list of terms, each term standing for
    [coeff * poly^2].  The certificate {i claims}

    {[ p = sum_i coeff_i * poly_i^2 ,   with every coeff_i >= 0. ]}

    This module only holds the {i data} and knows how to render / serialise it.
    Deciding whether the claim is actually true is the job of the {b trusted}
    {!Checker} — never trust a certificate until the checker has accepted it. *)

(** One summand: represents [coeff * poly^2]. *)
type term =
  { coeff : Rational.t
  ; poly : Polynomial.t
  }

type t = term list

let term (coeff : Rational.t) (poly : Polynomial.t) : term = { coeff; poly }
let make (terms : term list) : t = terms

(* --- rendering ---------------------------------------------------------- *)

let string_of_term (vars : Pretty.vars) (t : term) : string =
  let square = Printf.sprintf "(%s)^2" (Pretty.string_of_poly vars t.poly) in
  if Rational.equal t.coeff Rational.one
  then square
  else Printf.sprintf "%s*%s" (Rational.to_string t.coeff) square
;;

(** Render a certificate as ["c1*(q1)^2 + c2*(q2)^2 + ..."]. *)
let to_string (vars : Pretty.vars) (cert : t) : string =
  match cert with
  | [] -> "0"
  | _ -> String.concat " + " (List.map (string_of_term vars) cert)
;;

let latex_of_term (vars : Pretty.vars) (t : term) : string =
  let square =
    Printf.sprintf "\\left(%s\\right)^{2}" (Pretty.latex_of_poly vars t.poly)
  in
  if Rational.equal t.coeff Rational.one
  then square
  else Printf.sprintf "%s%s" (Rational.to_latex t.coeff) square
;;

let to_latex (vars : Pretty.vars) (cert : t) : string =
  match cert with
  | [] -> "0"
  | _ -> String.concat " + " (List.map (latex_of_term vars) cert)
;;

(* --- JSON --------------------------------------------------------------- *)

(** Serialise to the JSON certificate format (see examples/).  [claim] and
    [vars] are recorded alongside the sum-of-squares terms. *)
let to_json ~(claim : string) ~(vars : Pretty.vars) (cert : t) : Yojson.Safe.t =
  let term_json t =
    `Assoc
      [ "coeff", `String (Rational.to_string t.coeff)
      ; "poly", `String (Pretty.string_of_poly vars t.poly)
      ]
  in
  `Assoc
    [ "claim", `String claim
    ; "variables", `List (List.map (fun v -> `String v) vars)
    ; "sos", `List (List.map term_json cert)
    ]
;;

(** A certificate loaded from JSON, together with the claim it is about and the
    target polynomial [A - B] the checker should verify.  All polynomials are
    built in the [vars] context, so their monomial indices line up. *)
type parsed =
  { claim_text : string (** the original ["A >= B"] claim string *)
  ; vars : string list (** variable ordering, from the JSON *)
  ; target : Polynomial.t (** [A - B], the polynomial to prove [>= 0] *)
  ; certificate : t (** the sum-of-squares terms *)
  }

(** Load a certificate from a parsed JSON value (see [examples/] for the
    format).  Returns [Error msg] — never raises — for any malformation:
    missing/typed-wrong fields, unparsable claim or polynomial, a malformed
    rational coefficient, or a variable outside the declared context.  Note this
    validates {i shape}, not the inequality: the caller must still run the
    trusted {!Checker} on [target] and [certificate]. *)
let of_json (json : Yojson.Safe.t) : (parsed, string) result =
  let module U = Yojson.Safe.Util in
  let exception Bad of string in
  let poly_of_string ~vars src =
    match Parser.parse_expr src with
    | Error m -> raise (Bad (Printf.sprintf "cannot parse polynomial %S: %s" src m))
    | Ok e ->
      (try Normalizer.poly_of_expr vars e with
       | Invalid_argument m -> raise (Bad m))
  in
  try
    let claim_text =
      try json |> U.member "claim" |> U.to_string with
      | _ -> raise (Bad "missing or non-string field 'claim'")
    in
    let vars =
      try json |> U.member "variables" |> U.to_list |> List.map U.to_string with
      | _ -> raise (Bad "missing or invalid field 'variables'")
    in
    let sos =
      try json |> U.member "sos" |> U.to_list with
      | _ -> raise (Bad "missing or invalid field 'sos'")
    in
    let target =
      match Parser.parse claim_text with
      | Error m -> raise (Bad ("cannot parse claim: " ^ m))
      | Ok c ->
        (try snd (Normalizer.poly_of_claim ~context:vars c) with
         | Invalid_argument m -> raise (Bad m))
    in
    let parse_term j =
      let coeff_s =
        try j |> U.member "coeff" |> U.to_string with
        | _ -> raise (Bad "certificate term is missing a string 'coeff'")
      in
      let poly_s =
        try j |> U.member "poly" |> U.to_string with
        | _ -> raise (Bad "certificate term is missing a string 'poly'")
      in
      let coeff =
        match Rational.of_string_opt coeff_s with
        | Some q -> q
        | None -> raise (Bad (Printf.sprintf "malformed rational coefficient %S" coeff_s))
      in
      term coeff (poly_of_string ~vars poly_s)
    in
    Ok { claim_text; vars; target; certificate = List.map parse_term sos }
  with
  | Bad m -> Error m
;;

(** Parse a certificate from a JSON string. Wraps JSON-syntax errors into the
    [Error] channel. *)
let of_string (s : string) : (parsed, string) result =
  match Yojson.Safe.from_string s with
  | json -> of_json json
  | exception Yojson.Json_error m -> Error ("JSON syntax error: " ^ m)
;;

(** Read and parse a certificate JSON file. Wraps I/O and JSON-syntax errors
    into the [Error] channel. *)
let load_file (path : string) : (parsed, string) result =
  match Yojson.Safe.from_file path with
  | json -> of_json json
  | exception Sys_error m -> Error m
  | exception Yojson.Json_error m -> Error ("JSON syntax error: " ^ m)
;;
