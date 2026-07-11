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
  | Mismatch of
      { target : Polynomial.t
      ; got : Polynomial.t
      } (** all coefficients were fine, but [sum c_i q_i^2] did not equal [p] *)
  | Unknown_constraint of Polynomial.t
  (** a constrained certificate scaled a polynomial that is not a declared
      hypothesis of the matching kind, so its sign is not guaranteed *)

type outcome =
  | Verified
  | Rejected of failure

(** The polynomial [sum_i c_i * q_i^2] denoted by a certificate. *)
let expand (cert : Certificate.t) : Polynomial.t =
  cert
  |> List.map (fun (t : Certificate.term) ->
    Polynomial.scalar_mul t.coeff (Polynomial.mul t.poly t.poly))
  |> Polynomial.sum
;;

(** Full check, returning a reason on rejection. *)
let check (target : Polynomial.t) (cert : Certificate.t) : outcome =
  match
    List.find_opt (fun (t : Certificate.term) -> not (Rational.is_nonneg t.coeff)) cert
  with
  | Some t -> Rejected (Negative_coefficient t.coeff)
  | None ->
    let got = expand cert in
    if Polynomial.equal target got then Verified else Rejected (Mismatch { target; got })
;;

(** Boolean form of {!check}: [true] iff the certificate proves [target >= 0].
    This is the predicate the CLI must consult before printing [PROVED]. *)
let check_sos (target : Polynomial.t) (cert : Certificate.t) : bool =
  match check target cert with
  | Verified -> true
  | Rejected _ -> false
;;

(* --- constrained (Positivstellensatz) certificates ---------------------- *)

(** First negative coefficient in a sum-of-squares, if any. *)
let negative_coeff (sos : Certificate.t) : Rational.t option =
  List.find_map
    (fun (t : Certificate.term) ->
       if Rational.is_nonneg t.coeff then None else Some t.coeff)
    sos
;;

(** The polynomial [base + sum_i sigma_i * g_i + sum_j lambda_j * h_j] denoted by
    a constrained certificate. *)
let expand_constrained (cert : Constrained.t) : Polynomial.t =
  let contribution : Constrained.product -> Polynomial.t = function
    | Times_nonneg { multiplier; nonneg } -> Polynomial.mul (expand multiplier) nonneg
    | Times_zero { multiplier; zero } -> Polynomial.mul multiplier zero
    | Times_product { multiplier; factors } ->
      List.fold_left Polynomial.mul (expand multiplier) factors
  in
  Polynomial.sum (expand cert.base :: List.map contribution cert.products)
;;

(** Verify a Positivstellensatz certificate that [target >= 0] on the region cut
    out by [hypotheses].  It checks that

    - every sum-of-squares part ([base] and each {!Constrained.Times_nonneg}
      multiplier) has only nonnegative coefficients;
    - every scaled polynomial is a declared hypothesis of the matching kind — a
      [Nonneg] hypothesis for a [Times_nonneg] term, a [Zero] hypothesis for a
      [Times_zero] term (structural polynomial equality); and
    - [target] equals the certificate's expansion {i exactly}.

    Given those, on any point of the region [base >= 0], each [sigma_i g_i >= 0]
    (nonnegative times a nonnegative hypothesis), and each [lambda_j h_j = 0]
    (anything times a vanishing hypothesis); so [target >= 0] there.  As with
    {!check}, soundness rests only on exact arithmetic and structural equality. *)
let check_constrained
      ~(hypotheses : Constrained.hypothesis list)
      (target : Polynomial.t)
      (cert : Constrained.t)
  : outcome
  =
  let sos_parts =
    cert.base
    :: List.filter_map
         (function
           | Constrained.Times_nonneg { multiplier; _ } -> Some multiplier
           | Times_product { multiplier; _ } -> Some multiplier
           | Times_zero _ -> None)
         cert.products
  in
  match List.find_map negative_coeff sos_parts with
  | Some c -> Rejected (Negative_coefficient c)
  | None ->
    let is_nonneg_hypothesis g =
      List.exists
        (function
          | Constrained.Nonneg g' -> Polynomial.equal g g'
          | Zero _ -> false)
        hypotheses
    in
    let undeclared : Constrained.product -> Polynomial.t option = function
      | Times_nonneg { nonneg; _ } ->
        if is_nonneg_hypothesis nonneg then None else Some nonneg
      | Times_zero { zero; _ } ->
        if
          List.exists
            (function
              | Constrained.Zero h -> Polynomial.equal h zero
              | Nonneg _ -> false)
            hypotheses
        then None
        else Some zero
      | Times_product { factors; _ } ->
        (* Every factor must be a declared nonnegative hypothesis. *)
        List.find_opt (fun g -> not (is_nonneg_hypothesis g)) factors
    in
    (match List.find_map undeclared cert.products with
     | Some g -> Rejected (Unknown_constraint g)
     | None ->
       let got = expand_constrained cert in
       if Polynomial.equal target got
       then Verified
       else Rejected (Mismatch { target; got }))
;;

(** [true] iff the constrained certificate proves [target >= 0] on the region cut
    out by [hypotheses]. The predicate the CLI must consult before [PROVED]. *)
let check_constrained_ok
      ~(hypotheses : Constrained.hypothesis list)
      (target : Polynomial.t)
      (cert : Constrained.t)
  : bool
  =
  match check_constrained ~hypotheses target cert with
  | Verified -> true
  | Rejected _ -> false
;;
