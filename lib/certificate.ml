(** Sum-of-squares certificates.

    A certificate for [p >= 0] is a list of terms, each term standing for
    [coeff * poly^2].  The certificate {i claims}

    {[ p = sum_i coeff_i * poly_i^2 ,   with every coeff_i >= 0. ]}

    This module only holds the {i data} and knows how to render / serialise it.
    Deciding whether the claim is actually true is the job of the {b trusted}
    {!Checker} — never trust a certificate until the checker has accepted it. *)

(** One summand: represents [coeff * poly^2]. *)
type term = { coeff : Rational.t; poly : Polynomial.t }

type t = term list

let term (coeff : Rational.t) (poly : Polynomial.t) : term = { coeff; poly }

let make (terms : term list) : t = terms

(* --- rendering ---------------------------------------------------------- *)

let string_of_term (vars : Pretty.vars) (t : term) : string =
  let square = Printf.sprintf "(%s)^2" (Pretty.string_of_poly vars t.poly) in
  if Rational.equal t.coeff Rational.one then square
  else Printf.sprintf "%s*%s" (Rational.to_string t.coeff) square

(** Render a certificate as ["c1*(q1)^2 + c2*(q2)^2 + ..."]. *)
let to_string (vars : Pretty.vars) (cert : t) : string =
  match cert with
  | [] -> "0"
  | _ -> String.concat " + " (List.map (string_of_term vars) cert)

let latex_of_term (vars : Pretty.vars) (t : term) : string =
  let square = Printf.sprintf "\\left(%s\\right)^{2}" (Pretty.latex_of_poly vars t.poly) in
  if Rational.equal t.coeff Rational.one then square
  else Printf.sprintf "%s%s" (Rational.to_latex t.coeff) square

let to_latex (vars : Pretty.vars) (cert : t) : string =
  match cert with
  | [] -> "0"
  | _ -> String.concat " + " (List.map (latex_of_term vars) cert)

(* --- JSON --------------------------------------------------------------- *)

(** Serialise to the JSON certificate format (see examples/).  [claim] and
    [vars] are recorded alongside the sum-of-squares terms. *)
let to_json ~(claim : string) ~(vars : Pretty.vars) (cert : t) : Yojson.Safe.t =
  let term_json t =
    `Assoc
      [ ("coeff", `String (Rational.to_string t.coeff));
        ("poly", `String (Pretty.string_of_poly vars t.poly)) ]
  in
  `Assoc
    [ ("claim", `String claim);
      ("variables", `List (List.map (fun v -> `String v) vars));
      ("sos", `List (List.map term_json cert)) ]

(** Load a certificate from JSON.

    {b STATUS: stub.}  Reading a certificate requires turning the ["poly"]
    strings (e.g. ["a - b"]) into polynomials, which needs {!Parser} — the next
    milestone.  Until then this returns an [Error].  The in-memory checker path
    (used by [demo] and the tests) does not need this. *)
let of_json (_json : Yojson.Safe.t) : (t, string) result =
  Error "Certificate.of_json: needs the expression parser (TODO: Milestone 2)"
