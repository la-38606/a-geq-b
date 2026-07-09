(** The trusted certificate checker.

    This is the heart of the LCF-style design: the search engine ({!Prover}) is
    untrusted and may use any heuristic it likes, but the system only reports
    [PROVED] when {b this} module accepts the certificate.  It must therefore
    stay small, obviously correct, and use only exact arithmetic.

    Given a target polynomial [p] (already reduced to [A - B]) and a certificate
    [cert = [ (c_i, q_i) ]], the checker verifies:

    1. every coefficient [c_i >= 0]; and
    2. [p] is {i exactly} equal to [sum_i c_i * q_i^2].

    Because each [q_i^2] is a square and each [c_i] is a nonnegative rational,
    the right-hand side is [>= 0] for all real inputs; if it equals [p], then
    [p >= 0], which proves the original inequality. *)

(** Why a certificate was rejected. *)
type failure =
  | Negative_coefficient of Rational.t
      (** some [c_i] was negative, so [c_i * q_i^2] is not guaranteed [>= 0] *)
  | Mismatch of { target : Polynomial.t; got : Polynomial.t }
      (** all coefficients were fine, but [sum c_i q_i^2] did not equal [p] *)

type outcome = Verified | Rejected of failure

(** The polynomial [sum_i c_i * q_i^2] denoted by a certificate. *)
let expand (cert : Certificate.t) : Polynomial.t =
  cert
  |> List.map (fun (t : Certificate.term) ->
         Polynomial.scalar_mul t.coeff (Polynomial.mul t.poly t.poly))
  |> Polynomial.sum

(** Full check, returning a reason on rejection. *)
let check (target : Polynomial.t) (cert : Certificate.t) : outcome =
  match
    List.find_opt
      (fun (t : Certificate.term) -> not (Rational.is_nonneg t.coeff))
      cert
  with
  | Some t -> Rejected (Negative_coefficient t.coeff)
  | None ->
      let got = expand cert in
      if Polynomial.equal target got then Verified
      else Rejected (Mismatch { target; got })

(** Boolean form of {!check}: [true] iff the certificate proves [target >= 0].
    This is the predicate the CLI must consult before printing [PROVED]. *)
let check_sos (target : Polynomial.t) (cert : Certificate.t) : bool =
  match check target cert with Verified -> true | Rejected _ -> false
