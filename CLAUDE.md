# CLAUDE.md — working rules for A≥B (`a-geq-b`)

Instructions for future Claude Code sessions on this project. Read before making
changes.

## What this project is

A≥B proves polynomial inequalities `A >= B` by rewriting them as `p = A - B >= 0`
and verifying a **sum-of-squares certificate** `p = Σ c_i q_i²` (with `c_i ∈ ℚ`,
`c_i ≥ 0`) using **exact rational arithmetic**. It is built in the LCF /
certificate style: an *untrusted* search engine proposes certificates, and a
small *trusted* checker is the sole authority on whether something is `PROVED`.

## Non-negotiable rules

1. **Exact arithmetic only.** All coefficient arithmetic goes through
   `Rational` (a thin wrapper over Zarith). Never introduce floats into the
   checker or the polynomial core. If a numerical solver is ever added (SDP), it
   lives in the *untrusted* engine and its output must be rounded to exact
   rationals and re-verified.

2. **Keep the checker small and trusted.** `lib/checker.ml` is the heart of the
   system. It must stay short, obviously correct, and dependent only on
   `Polynomial` / `Rational` / `Certificate`. The program must never print
   `PROVED` unless `Checker.check_sos` returns `true`. `NO_CERT_FOUND` is *not*
   the same as *false*.

3. **Respect the ordering: checker first, prover second, SDP/Coq last.** Do
   **not** add an SDP solver, Coq/Lean extraction, or a web frontend before the
   core checker and parser are solid. Those are stretch goals, not foundations.

4. **Every new feature needs tests.** Add cases under `test/` (Alcotest) for any
   new behaviour, and keep the "corrupted certificate must be rejected" tests
   growing alongside the "valid certificate accepted" ones.

## Invariants to preserve

- **Monomial canonical form** (`lib/monomial.ml`): exponent vectors with
  *trailing zeros stripped*; the constant monomial is `[]`. Exponents are
  nonnegative. `Monomial.compare` is a total order used as the polynomial map
  key.
- **Polynomial canonical form** (`lib/polynomial.ml`): a `Map` from canonical
  monomials to **nonzero** rational coefficients. Every operation preserves
  this, so `Polynomial.equal` is structural equality of normal forms. Do not
  store zero coefficients.
- **Shared variable ordering**: monomial indices are positional. The target
  polynomial and every certificate polynomial must be built with the same
  variable `context` (see `Normalizer`).

## Layout

```
lib/
  rational.ml     exact ℚ (only file that touches Zarith's Q/Z)
  monomial.ml     exponent vectors (canonical form)
  polynomial.ml   map monomial → coeff; arithmetic; equality
  ast.ml          expression + claim syntax tree
  parser.ml       string → Ast          (recursive descent)
  normalizer.ml   Ast → Polynomial; claim A⋛B → target p≥0
  pretty.ml       readable + LaTeX rendering
  certificate.ml  SOS term data + rendering + JSON read/write
  checker.ml      TRUSTED exact checker: check_sos
  prover.ml       untrusted search  (STUB) + hardcoded demo
bin/main.ml       CLI (--help, demo, prove, check)
test/             test_polynomial.ml, test_parser.ml, test_checker.ml (Alcotest)
examples/         hello_world.cert.json, corrupted.cert.json
```

## Build / test / run

```
dune build
dune runtest
dune exec a-geq-b -- demo
```

`zarith` needs GMP + a C compiler (macOS: `brew install gmp`; you may need
`C_INCLUDE_PATH=/opt/homebrew/include LIBRARY_PATH=/opt/homebrew/lib` when
installing zarith).

## Status

- **Milestone 1** (exact polynomial core) — ✅ done.
- **Milestone 2** (parser, normalizer, JSON read/write, `prove`/`check` CLI with
  the four statuses) — ✅ done.
- **Milestones 3–4** (checker, pretty/LaTeX proof printer) — ✅ done.

## Next implementation step

**Milestone 5 — the automatic prover.** `Prover.prove` is still a stub returning
`No_certificate_found`; implement real SOS search, in stages, and route every
candidate through `Checker.check_sos` before the CLI prints `PROVED`:

- **Stage B — quadratic forms.** For a homogeneous degree-2 target, build the
  symmetric matrix `A` with `p = xᵀAx`; if `A` is PSD and rationally
  decomposable (e.g. rational LDLᵀ / Cholesky), emit the SOS certificate.
  Targets: `a^2+b^2 >= 2ab`, `x^2+y^2+z^2 >= xy+yz+zx`, `2x^2+2y^2 >= (x+y)^2`.
- **Stage C — pairwise differences.** For `a,b,c`, search certificates built
  from `a-b, b-c, c-a` and simple monomial multiples (helps symmetric
  inequalities tight at `a=b=c`).
- **Stage D — Gram/SDP.** Monomial basis `z`, symbolic `zᵀQz`, match
  coefficients to constrain `Q`, call an external SDP solver, round to rationals,
  and re-verify with the checker. Numerical code stays untrusted.

Exit condition (brief, Milestone 5): at least 10 textbook inequalities prove
automatically, and unsupported ones return `NO_CERT_FOUND`, never `PROVED`. Add
`test/test_prover.ml`. SDP/Coq/frontend remain last.
