# A≥B (`a-geq-b`)

A≥B proves polynomial inequalities by finding explicit algebraic certificates
and verifying them with exact rational arithmetic. The search side may be
heuristic or numerical; nothing it produces is trusted. A claim is reported
`PROVED` only when a small exact checker accepts the certificate, so a bug in
search can lose a proof but never invent one.

The smallest example: to prove

```
a^2 + b^2 >= 2*a*b
```

A≥B rewrites the difference of the two sides as

```
a^2 - 2*a*b + b^2 = (a - b)^2
```

The right side is visibly nonnegative, and the identity is checked term for
term over exact rationals. That rewriting is the certificate: the proof is an
object you can inspect and re-verify independently, not a solver's yes.

## Try it

Build (needs OCaml, Dune, and `opam install zarith yojson alcotest`; zarith
needs GMP, on macOS `brew install gmp`):

```
dune build
```

The web interface:

```
dune exec a-geq-b-web        # then open http://127.0.0.1:8642
```

Type an inequality and press Prove. Assumptions go after `given`. Every
result offers "How was this proved?" (the actual route, stage by stage, with
trusted and untrusted stages tagged), certificate details (LaTeX and the JSON
file `a-geq-b check` re-verifies), and Lean export. The "How it works" page
is a guided tour of the architecture.

The same prover on the command line:

```
dune exec a-geq-b -- demo
dune exec a-geq-b -- prove "a^2 + b^2 + c^2 >= a*b + b*c + c*a"
dune exec a-geq-b -- prove "a^2 + b^2 >= 2 given a*b = 1"
dune exec a-geq-b -- check examples/hello_world.cert.json
dune exec a-geq-b -- lean "a^2 + b^2 >= 2*a*b"
```

Statuses (also the exit codes): `PROVED` (0), `NO_CERT_FOUND` (2),
`INVALID_INPUT` (3), `CHECK_FAILED` (4).

## Demo

`./scripts/record-demo.sh` records a reproducible 60-second walkthrough of
the web interface (deterministic Playwright script driving the live
application, including the numerical SDP route) into `demo/aeqb-demo.webm`.
The video is not committed; publish it via a GitHub release if you want a
hosted copy.

## Why certificates

A numerical optimizer can sample points and report that an inequality looks
true. That is evidence, not proof. A≥B instead searches for an identity

```
A - B = c1*q1^2 + c2*q2^2 + ...        with rational ci >= 0
```

(a sum-of-squares certificate). If the identity holds exactly, the right side
is nonnegative everywhere, so `A >= B` everywhere. Checking the identity
needs only polynomial expansion and comparison over exact rationals, which is
the entire trusted surface of the system.

This separation is the engineering core of the project: search is allowed to
be complicated, incomplete, and even wrong, because acceptance is small,
exact, and independent of how the candidate was found.

```
UNTRUSTED SEARCH

  exact Gram search (rational LDL^T over candidate bases)
  constrained Positivstellensatz strategies
  numerical SDP in Python (cvxpy, floating point)

  ------------- certificate boundary -------------

TRUSTED CORE

  canonical polynomial arithmetic over exact rationals
  the certificate checker (sole authority on PROVED)
```

## What it supports

- Unconstrained polynomial inequalities over the rationals, proved by exact
  sum-of-squares certificates. Division is allowed in the input; denominators
  are cleared soundly.
- Constrained inequalities via `given` (equalities and inequalities), proved
  by Positivstellensatz certificates: `p = base + sum si*gi + sum lj*hj`
  where the `si` are sums of squares scaling hypotheses `gi >= 0`, and the
  `lj` are arbitrary multipliers on hypotheses `hj = 0`. The search covers
  constant multipliers, polynomial multipliers on equalities (by reduction),
  and products of two nonnegative hypotheses.
- Targets whose Gram matrix has more freedom than the exact search resolves
  are closed by the numerical SDP route below.

`NO_CERT_FOUND` is never a disproof. It can mean the claim is false, or true
but not a sum of squares (Motzkin's polynomial is the classic case), or
provable only by a certificate outside the implemented searches. A≥B never
concludes "false".

## The numerical SDP route

Finding a sum-of-squares decomposition is in general a semidefinite
feasibility problem. When the exact search comes up empty, A≥B emits the
Gram program as JSON, lets cvxpy find an approximate positive semidefinite
matrix, rounds that matrix back to exact rationals, reads off the squares by
LDL^T, and hands the result to the same trusted checker. A wrong numerical
answer fails reconstruction or is rejected; it cannot become a proof.

```
python3 -m venv .venv && .venv/bin/python -m pip install -r sdp/requirements.txt
.venv/bin/python sdp/prove.py "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d"   # -> PROVED
```

The web server uses the same virtualenv automatically when it exists, so the
SDP route works from the browser too. With it, all 63 in-scope sum-of-squares
corpus targets are proved (`.venv/bin/python corpus/run_sdp.py`); the exact
search alone closes 53 of them. See [sdp/README.md](sdp/README.md).

## Lean

Two things are machine-checked in Lean 4 / Mathlib, and they are different
things:

- The checker's soundness is proved: [lean/AeqbCheck.lean](lean/AeqbCheck.lean)
  re-expresses the check over `MvPolynomial (Fin n) ℚ` and proves, without
  `sorry`, that an accepted certificate implies the target is nonnegative at
  every real point.
- Each individual proof can be exported as a self-contained Lean theorem
  (`a-geq-b lean "<ineq>"`, or the button in the web UI), closed by `ring`
  and `positivity`. Lean's kernel checks it when you compile the file; A≥B
  does not run Lean itself and never claims a kernel check it did not do.

See [lean/README.md](lean/README.md).

## Three languages

- OCaml: everything that must be exact. Algebra, parser, normalizer,
  certificates, the trusted checker, search, and both interfaces.
- Python: untrusted numerics only (the cvxpy SDP solve).
- Lean: the formal layer (checker soundness, exported theorems).

## Testing

- `dune runtest`: 139 cases across eight suites, covering polynomial
  arithmetic laws and canonicalization, the parser (including
  denominator clearing and malformed-input rejection), the checker against
  adversarial certificates (negative weights, wrong expansions, missing and
  extra terms), prover soundness on false and out-of-scope targets, the
  constrained strategies, Lean export, SDP rounding, and the structured
  pipeline record (including that a wrong numerical Gram matrix cannot bypass
  the checker).
- `cd web/e2e && npx playwright test`: 13 browser tests that drive the real
  server and assert proof semantics, honest failure reporting, trace
  accuracy, and Lean-export honesty.
- `python3 corpus/verify.py`: machine-verifies the 60 stored certificates in
  the [corpus](corpus/README.md) of 119 tagged inequalities (olympiad
  problems, classical forms, non-SOS traps, deliberately false claims).
  `python3 corpus/sanity_sample.py` numerically samples all 119 on their
  domains; sampling is a sanity check only and never counts as proof.

## Repository map

```
lib/       OCaml library: Rational, Monomial, Polynomial, Parser, Normalizer,
           Certificate, Constrained, Checker (trusted), Prover, Sdp,
           Proof_result (one pipeline run as structured data)
bin/       the a-geq-b CLI
web/       a-geq-b-web local server, static UI, browser tests, demo script
sdp/       Python numerical SDP solver (untrusted)
lean/      verified checker soundness + exported proofs
corpus/    119 tagged inequalities and verification tooling
test/      OCaml test suites
doc/       technical report (LaTeX source and PDF)
examples/  certificate files, valid and deliberately corrupted
```

The key invariant behind the checker: polynomials are maps from canonical
monomials (exponent vectors, trailing zeros stripped) to nonzero rational
coefficients. Every operation preserves this normal form, so certificate
verification is structural equality of exact normal forms.

## Technical report

The mathematics (SOS and the Gram reformulation, exact rational LDL^T,
denominator clearing, the Positivstellensatz fragment, SDP rounding) and the
system design are written up in
[doc/aeqb-design.pdf](doc/aeqb-design.pdf)
(source [doc/aeqb-design.tex](doc/aeqb-design.tex), built with
`tectonic doc/aeqb-design.tex`).

## Limitations

- Sum-of-squares is sufficient, not necessary: some true inequalities have no
  such certificate, and A≥B will honestly report `NO_CERT_FOUND` on them.
- The constrained search does not yet cover products of three or more
  hypotheses, or non-constant SOS multipliers on nonnegative hypotheses;
  the checker already accepts those certificate shapes.
- The SDP route uses the full half-degree monomial basis; a Newton polytope
  reduction would shrink the programs.
- The web server is a deliberately small localhost tool, not a network
  service.
