(** Emit a self-contained Lean 4 proof from an SOS certificate.

    Turns a certificate for [p >= 0] into a Lean theorem [(0 : ℝ) ≤ p] over real
    variables, proved by [ring] (the polynomial identity [p = sum c_i q_i^2],
    which holds because the trusted {!Checker} accepted the certificate) followed
    by [positivity] (a sum of nonnegative-rational multiples of squares).  Lean's
    kernel then checks it, so each A>=B proof becomes a machine-checked Lean
    theorem.  The emitter is untrusted output: a bogus certificate yields a Lean
    file that fails to compile, never a false theorem. *)

(** [theorem ~name ~vars p cert] is a complete Lean 4 source file proving
    [(0 : ℝ) ≤ p]. [cert] must satisfy [p = expand cert] (as {!Checker.check_sos}
    guarantees). *)
val theorem : name:string -> vars:Pretty.vars -> Polynomial.t -> Certificate.t -> string
