(** The (untrusted) search engine.

    The prover looks for a sum-of-squares certificate for a target polynomial
    [p >= 0].  It is allowed to be heuristic, incomplete, and clever; anything
    it returns MUST still be validated by the trusted {!Checker} before the
    system claims [PROVED].

    {b STATUS: mostly a stub.}  Automatic search (quadratic-form / Gram matrix,
    pairwise-difference patterns, SDP) is future work — see CLAUDE.md,
    "Automatic prover stages".  For now {!prove} always reports
    {!No_certificate_found}, and this module additionally provides the
    hand-written "hello world" example used by the [demo] command and the
    checker tests. *)

type result =
  | Proved of Certificate.t
  | No_certificate_found  (** not disproof — just "this prover found nothing" *)

(** Attempt to find an SOS certificate for [p >= 0].  TODO: implement Stages
    A-D from the design.  Always {!No_certificate_found} for now. *)
let prove (_p : Polynomial.t) : result = No_certificate_found

(* ---------------------------------------------------------------------- *)
(* Built-in "hello world" example:                                         *)
(*     a^2 + b^2 + c^2 >= a*b + b*c + c*a                                   *)
(* with the classic certificate                                            *)
(*     = 1/2 (a-b)^2 + 1/2 (b-c)^2 + 1/2 (a-c)^2.                           *)
(* Everything is built with the variable order [a; b; c] so the target and *)
(* the certificate share the same monomial indices.                        *)
(* ---------------------------------------------------------------------- *)

let hello_world_vars : string list = [ "a"; "b"; "c" ]

let hello_world_claim_string : string = "a^2 + b^2 + c^2 >= a*b + b*c + c*a"

(** The target polynomial [p = A - B], built through the {!Ast} + {!Normalizer}
    pipeline to exercise that path. *)
let hello_world_target () : Polynomial.t =
  let open Ast in
  let claim =
    { lhs = Add (Add (Pow (var "a", 2), Pow (var "b", 2)), Pow (var "c", 2));
      op = Ge;
      rhs = Add (Add (Mul (var "a", var "b"), Mul (var "b", var "c")), Mul (var "c", var "a")) }
  in
  snd (Normalizer.poly_of_claim ~context:hello_world_vars claim)

(** The classic three-square certificate. Note [(a-c)^2 = (c-a)^2]; we use
    [a-c] so it prints nicely. *)
let hello_world_certificate () : Certificate.t =
  let a = Polynomial.var 0 and b = Polynomial.var 1 and c = Polynomial.var 2 in
  let half = Rational.of_ints 1 2 in
  Certificate.make
    [ Certificate.term half (Polynomial.sub a b);
      Certificate.term half (Polynomial.sub b c);
      Certificate.term half (Polynomial.sub a c) ]
