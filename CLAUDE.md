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
- **Milestone 5** (automatic prover) — 🚧 in progress. `Prover.prove` proves via
  a Gram matrix + exact rational LDLᵀ over a chosen monomial basis:
  - degree-≤2 targets (basis `{1, x_i}` — the unique Gram);
  - even-power / product forms via monomial-substitution bases, and a full
    degree-`d` basis for homogeneous targets;
  - under-determined Gram matrices resolved by a bounded rational grid search
    (≤2 free entries) — `gram_candidates` in `lib/prover.ml`.
  It proves **53 of the 63** `in_scope_sos` corpus targets and is sound over all
  119 (`python3 corpus/run_prover.py`). Every candidate is re-checked by the
  trusted checker, so the search cannot produce a false `PROVED`.
- The normalizer also **clears denominators**, so rational-function inequalities
  (`a/(b+c) + ... >= 3/2`) parse and reduce to a polynomial target.
- **Lean 4 formally verified checker** (`lean/`) — ✅ the trusted core's soundness
  is machine-proved: `checkSOS_sound : checkSOS p cert = true -> forall x,
  0 <= aeval x p`, axiom-clean (no `sorry`). See `lean/README.md`.

## Roadmap to the finished version

Ordered; each keeps the checker as the sole authority.

1. **Wide (multi-variable) SDP prover — finish Milestone 5.** The remaining ~9
   in-scope targets need a monomial basis with MORE than 2 free Gram entries
   (`a^4+b^4+c^4+d^4 >= 4abcd`, `a^4+b^4+c^4 >= abc(a+b+c)`, the 3/4-variable
   cyclic quartics, `a^6+b^6+c^6 >= 3a^2b^2c^2`, APMO 2004). The bounded grid
   search caps at 2 free entries; these need a real rational SDP feasibility
   step. Natural split: OCaml emits the Gram SDP (basis + linear constraints) as
   JSON; a **Python** helper (`cvxpy`/`numpy`) solves it numerically; OCaml
   rounds the approximate PSD matrix to exact rationals and re-verifies with the
   checker. This is the brief's Stage D and the principled home for Python.

2. **Constrained inequalities (Positivstellensatz).** Accept side constraints
   (`a >= 0`, `abc = 1`, triangle, …) and search for certificates
   `p = sigma_0 + sum_i sigma_i * g_i` (each `sigma` an SOS, `g_i` a constraint).
   Unlocks the 50 `out_of_scope_v1` corpus targets (AM-GM, Schur, Nesbitt, the
   IMO/Iran/Japan/book problems). Largest capability jump.

3. **Formally verified checker in Lean 4** — 🚧 in progress; first direction
   done. Upgrade the trusted core from "small and audited" to "machine-verified."
   Note: Lean is not "extracted" like Coq — the analog is a *verified
   reimplementation* (Lean compiles to native code and `#eval`s), plus optionally
   emitting Lean-checkable proofs. Two directions:
   - **Verified checker** — ✅ done. `lean/AeqbCheck.lean` reimplements
     `check_sos` over `MvPolynomial (Fin n) Rat` and proves
     `checkSOS_sound : checkSOS p cert = true -> forall x : Fin n -> Real,
     0 <= aeval x p`. Complete and axiom-clean (`#print axioms` =
     `[propext, Classical.choice, Quot.sound]`, no `sorry`); pinned to
     `leanprover/lean4:v4.31.0` + Mathlib. See `lean/README.md`. Could run as an
     independent oracle beside the OCaml checker.
   - **Lean-checkable proof output** — remaining. Have the (untrusted) OCaml
     prover emit, per certificate, a Lean proof term / script that Lean's kernel
     checks, so every A>=B proof becomes a machine-checked Lean theorem — the
     strongest possible trust reduction.

4. **UI (optional, Milestone 6).** Because the engine is pure OCaml, the clean
   option is **js_of_ocaml**: compile the lib to run `prove`/`check`
   in-browser (needs `zarith_stubs_js`, or swap the isolated `Rational` module
   for a pure-OCaml bignum), with a `--json` output seam feeding a page that
   renders the existing LaTeX via KaTeX. No server.

Tri-language boundary once (1)+(3) land: **OCaml** = exact symbolic + trust,
**Python** = numerical SDP (untrusted), **Lean** = formal proof of the trusted
core.
