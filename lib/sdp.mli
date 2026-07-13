(** Untrusted numerical SDP path (see the [sdp/] directory).

    OCaml emits a Gram semidefinite program for a target [p >= 0], an external
    numerical solver finds an approximate positive-semidefinite Gram matrix, and
    OCaml rounds it back to an exact rational SOS certificate. This closes the
    targets whose Gram matrix has more freedom than {!Prover.prove}'s bounded
    grid search can explore.

    Untrusted, like the rest of the prover: a numerically wrong Gram matrix
    rounds to something that is not PSD, or yields a certificate the trusted
    {!Checker} rejects. The result is then [None] -- never a false proof. *)

(** The Gram SDP for [p >= 0] as JSON (dimension, monomial basis, and the linear
    coefficient constraints) for the external solver to feed to its SDP backend. *)
val problem_json : Polynomial.t -> Yojson.Safe.t

(** Exact SOS certificate rounded from a numerical Gram matrix [q], which must be
    indexed by {!Prover.sdp_basis} of the same [p] (the basis {!problem_json}
    emitted). [None] if no rounding yields a certificate the trusted {!Checker}
    accepts. *)
val certificate_of_solution : Polynomial.t -> float array array -> Certificate.t option
