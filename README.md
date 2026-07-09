# A≥B (`a-geq-b`)

**A≥B** (pronounced "A-geq-B") is a standalone OCaml prover for polynomial
inequalities. Given a claim `A >= B`, it rewrites it as `p = A - B >= 0` and
proves `p >= 0` by finding and verifying a **sum-of-squares (SOS) certificate**

```
p = Σ_i c_i · q_i²      with c_i ∈ ℚ, c_i ≥ 0, q_i ∈ ℚ[x₁,…,xₙ].
```

Because each `q_i²` is a square and each `c_i` is a nonnegative rational, the
right-hand side is `≥ 0` everywhere; if it equals `p` *exactly*, then `p ≥ 0`
and the inequality is proven. The result is both machine-checkable and
human-readable — the system prints the explicit algebraic identity.

**Example**

```
a^2 + b^2 + c^2 >= a*b + b*c + c*a
```

becomes

```
a^2 + b^2 + c^2 - a*b - b*c - c*a
  = 1/2·(a - b)^2 + 1/2·(b - c)^2 + 1/2·(a - c)^2.
```

Since the right-hand side is a sum of nonnegative squares, the inequality holds.

## Architecture: untrusted engine, trusted checker

A≥B follows the **LCF / certificate style**:

- The **prover** (search engine) is *untrusted*. It may use any heuristic,
  pattern, or numerical solver.
- The **checker** is *trusted* and *exact*. It re-verifies the certificate with
  exact rational arithmetic and is the only thing that can license the word
  `PROVED`.
- `NO_CERT_FOUND` ≠ *false*: it only means the current prover found no supported
  certificate.

```
Rational → Monomial → Polynomial → { Ast, Pretty }
                                  → { Parser, Normalizer, Certificate }
                                  → Checker → Prover → CLI
```

## What is implemented in this skeleton

| Area | Status |
| --- | --- |
| `Rational` — exact ℚ (thin wrapper over Zarith; the *only* arithmetic dependency) | ✅ done |
| `Monomial` — exponent vectors in canonical form (trailing zeros stripped) | ✅ done |
| `Polynomial` — map monomial→coeff; `zero/one/const/var`, `add/neg/sub/scalar_mul/mul/pow`, `normalize`, `equal`, `degree` | ✅ done |
| `Ast` — expression + claim tree | ✅ done |
| `Parser` — string → `Ast` (recursive descent, incl. division) | ✅ done |
| `Normalizer` — `Ast → Polynomial`; claim `A ⋛ B` → `p ≥ 0`, clearing denominators | ✅ done |
| `Pretty` — readable + LaTeX rendering of polynomials/certificates | ✅ done |
| `Certificate` — SOS term data, rendering, JSON read + write | ✅ done |
| `Checker` — `check_sos : poly → certificate → bool`, exact | ✅ done (trusted core) |
| `Prover` — SOS search (Gram + rational LDLᵀ over a monomial basis, bounded grid search) | 🚧 proves 49/58 corpus targets; wide multi-var SDP case pending |
| CLI — `--help`, `demo`, `prove`, `check` | ✅ done |
| Tests — `test_polynomial`, `test_parser`, `test_checker`, `test_prover` | ✅ 79 cases |

### Canonical form (the key invariant)

A polynomial is a `Map` from **monomials** to **nonzero** rational
coefficients. Monomials are exponent vectors with **trailing zeros stripped**,
so `a²` is `[2]` regardless of how many variables are in play and the constant
monomial is `[]`. Every constructor and operation preserves this, which makes
polynomial equality just structural equality of normal forms — exactly what the
checker relies on.

## Build

Requires OCaml + Dune and these opam packages:

```
opam install zarith yojson alcotest
```

`zarith` needs GMP and a C compiler (on macOS: `brew install gmp`). Then:

```
dune build
```

## Run the tests

```
dune runtest
```

Covers polynomial arithmetic laws (`p+0=p`, `p·1=p`, commutativity,
associativity, distributivity, …) and normalisation; the parser (expressions,
precedence, rationals, division / denominator-clearing, malformed-input
rejection) and JSON certificate loading; the checker (accepts the classic
three-variable certificate; rejects negative coefficients, wrong expansions,
missing terms, extra terms); and the prover (degree-≤2 and even-power targets
proved and re-checked, false / out-of-scope targets not proved).

## Run it

```
dune exec a-geq-b -- demo
```

Proves `a² + b² + c² ≥ a·b + b·c + c·a` via the built-in certificate, runs it
through the trusted checker, and prints a readable proof (plus LaTeX) ending in
`Status: PROVED`.

```
dune exec a-geq-b -- check examples/hello_world.cert.json   # -> PROVED
dune exec a-geq-b -- check examples/corrupted.cert.json     # -> CHECK_FAILED
dune exec a-geq-b -- prove "a^2 + b^2 >= 2*a*b"             # -> NO_CERT_FOUND (no prover yet)
dune exec a-geq-b -- --help
```

`prove` parses the inequality (division allowed — denominators are cleared),
reduces it to `p ≥ 0`, and runs the automatic prover (Gram matrix + exact
rational LDLᵀ over a monomial basis, with a bounded rational grid search for
under-determined cases). E.g. `a^2+b^2 >= 2*a*b` now prints `PROVED` with the
certificate `(a-b)^2`, found automatically, and rational inputs like
`(a-b)^2/2 >= 0` work too. Targets that need a wider (multi-variable)
semidefinite search still report `NO_CERT_FOUND` — which is *not* a disproof.
`check` loads a certificate and runs the trusted checker. Statuses: `PROVED`
(0), `NO_CERT_FOUND` (2), `INVALID_INPUT` (3), `CHECK_FAILED` (4).

## Test corpus

[`corpus/`](corpus/) holds **119 inequalities** for exercising the checker and
the prover — classic AM–GM / Cauchy–Schwarz / Schur forms, olympiad problems
(IMO 1964/1984/1995/1999/2000, APMO 2004, Iran 1996, Japan 1997, and problems
from Manfrino–Ortega–Delgado, *Inequalities: A Mathematical Olympiad Approach*),
rational inequalities (denominators cleared), and soundness traps (Motzkin /
Choi–Lam non-SOS forms and deliberately false claims). Each is tagged by
category and by the status v1 should return. The 60 sum-of-squares certificates
are machine-verified by the checker (`python3 corpus/verify.py`); all 119 are
numerically sanity-checked on their domains (`python3 corpus/sanity_sample.py`).
See [corpus/README.md](corpus/README.md).

## Deliberately not implemented yet

Per the implementation brief, these are **stretch goals, not foundations**, and
are intentionally left for later prompts:

- the **rest of the automatic prover** — the remaining ~13 in-scope corpus
  targets need a monomial basis whose Gram matrix is not uniquely determined
  (an SDP feasibility problem); that stage is not built yet;
- **SDP** integration, **Coq/Lean** extraction, and a **web frontend**.

See [`CLAUDE.md`](CLAUDE.md) for the working rules and the next implementation
step.
