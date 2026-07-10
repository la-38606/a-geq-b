(** Emit a self-contained Lean 4 proof from an SOS certificate.

    The (untrusted) prover finds a certificate [p = sum_i c_i * q_i^2] with
    [c_i >= 0]; the trusted {!Checker} confirms the identity.  This module turns
    that certificate into a Lean theorem asserting [0 <= p] over real variables,
    whose proof

      - rewrites [p] to its sum-of-squares form by [ring] (a polynomial
        identity, which holds precisely because the checker accepted it); then
      - closes [0 <= sum c_i * q_i^2] by [positivity] (nonnegative-rational
        multiples of squares).

    Lean's kernel then checks the result, so each A>=B proof becomes a
    machine-checked Lean theorem.  This is untrusted OUTPUT: a bogus certificate
    would produce a Lean file that simply fails to compile, never a false
    theorem. *)

(* Render `sum_i (c_i) * (q_i)^2` as a Lean real expression. *)
let sos_expr (vars : Pretty.vars) (cert : Certificate.t) : string =
  match cert with
  | [] -> "0"
  | _ ->
    cert
    |> List.map (fun (t : Certificate.term) ->
      Printf.sprintf
        "(%s) * (%s) ^ 2"
        (Rational.to_string t.coeff)
        (Pretty.string_of_poly vars t.poly))
    |> String.concat " + "
;;

(** [theorem ~name ~vars p cert] is a complete Lean 4 source file proving
    [(0 : ℝ) ≤ p], with real variables named by [vars].  [cert] must satisfy
    [p = expand cert] (guaranteed once {!Checker.check_sos} accepts it);
    otherwise the emitted [ring] step fails to compile. *)
let theorem
      ~(name : string)
      ~(vars : Pretty.vars)
      (p : Polynomial.t)
      (cert : Certificate.t)
  : string
  =
  let n = Polynomial.num_vars p in
  let names = List.init n (Pretty.name_of vars) in
  let binder =
    match names with
    | [] -> ""
    | _ -> Printf.sprintf " (%s : ℝ)" (String.concat " " names)
  in
  let p_str = Pretty.string_of_poly vars p in
  let sos = sos_expr vars cert in
  String.concat
    "\n"
    [ "import Mathlib"
    ; ""
    ; Printf.sprintf "theorem %s%s : (0 : ℝ) ≤ %s := by" name binder p_str
    ; Printf.sprintf "  have h : (%s : ℝ) = %s := by ring" p_str sos
    ; "  rw [h]"
    ; "  positivity"
    ; ""
    ]
;;
