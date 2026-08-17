(** One run of the whole pipeline -- parse, normalize, search, check -- as data.

    The CLI and the web interface consume this record instead of each
    re-implementing the pipeline: the CLI formats it for the terminal, the web
    layer serialises it with {!to_json}. The {!trace} records the route actually
    taken (which searches ran, what the trusted checker decided), so an
    interface can answer "how was this proved?" without reverse-engineering
    printed output.

    The soundness rule is unchanged: {!status} is [Proved] only after the
    trusted {!Checker} accepts the certificate, whatever search produced it. *)

type status =
  | Proved (** the trusted checker accepted a certificate *)
  | No_cert_found (** no supported certificate found -- {b not} a disproof *)
  | Invalid_input (** the claim did not parse or reduce *)
  | Check_failed (** a proposed certificate was rejected by the checker *)

(** The search route that produced the accepted certificate. *)
type search =
  | Exact_gram (** exact Gram matrix + rational LDLᵀ over candidate bases *)
  | Constrained_search of Prover.constrained_strategy
  | Numerical_sdp (** external numerical solver + exact rational reconstruction *)

(** One stage of the run. [trusted] marks stages the final verdict relies on
    (parsing, normalization, the exact check); search stages are untrusted --
    allowed to fail or emit a bad candidate, which the checker then rejects.
    [ms] is wall-clock time, present only when {!prove} was given a clock. *)
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
  { claim : string (** the input text, verbatim *)
  ; claim_latex : string option
    (** purely syntactic LaTeX of the parsed claim ({!Pretty.latex_of_claim});
        [None] when the input did not parse *)
  ; status : status
  ; vars : string list (** variable context (empty if the input was invalid) *)
  ; hypotheses : Constrained.hypothesis list
  ; target : Polynomial.t option (** the reduced target [p], to prove [p >= 0] *)
  ; search : search option (** the route that produced the certificate *)
  ; certificate : certificate option
  ; error : string option (** why the input was invalid / the check failed *)
  ; vacuous : string list (** warnings: the hypotheses cut out an empty region *)
  ; trace : step list
  }

(** An external numerical Gram solver for [p >= 0]: returns the approximate
    matrix and a short description of how it was obtained, or an explanation of
    why not. Untrusted -- its output is only a candidate for exact
    reconstruction and the trusted check. *)
type sdp_solver = Polynomial.t -> (float array array * string, string) result

(** Run the pipeline on a claim string. When the exact search finds nothing for
    an unconstrained target and [sdp] is given, the numerical route is tried:
    solve, round to exact rationals, and hand the result to the trusted checker.
    Pass [clock] (e.g. [Unix.gettimeofday]) to record per-stage wall time. *)
val prove : ?sdp:sdp_solver -> ?clock:(unit -> float) -> string -> t

(** ["PROVED"], ["NO_CERT_FOUND"], ["INVALID_INPUT"], ["CHECK_FAILED"] -- the
    names shared by the CLI status line and the JSON encoding. *)
val string_of_status : status -> string

(** Short human name for a search route, e.g. ["exact Gram search"]. *)
val search_label : search -> string

(** Human-readable reason a certificate was rejected. *)
val describe_failure : vars:Pretty.vars -> Checker.failure -> string

(** Warnings that the hypotheses cut out an empty region, so any claim under
    them holds only vacuously; empty when no contradiction was shown. Uses the
    untrusted search for the general refutation (and swallows its failures), so
    it can miss contradictions -- it never affects a verdict. *)
val vacuity_warnings
  :  vars:Pretty.vars
  -> Constrained.hypothesis list
  -> string list

val to_json : t -> Yojson.Safe.t
