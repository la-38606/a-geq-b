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
| `Normalizer` — `Ast → Polynomial`, and claim `A ⋛ B` → target `p ≥ 0` | ✅ done |
| `Pretty` — readable + LaTeX rendering of polynomials/certificates | ✅ done |
| `Certificate` — SOS term data, rendering, JSON serialisation | ✅ done (JSON *write* only) |
| `Checker` — `check_sos : poly → certificate → bool`, exact | ✅ done (trusted core) |
| `Prover` — SOS search | 🚧 stub (returns `No_certificate_found`) + hardcoded demo |
| `Parser` — string → `Ast` | 🚧 stub (grammar documented) |
| CLI | ✅ `--help`, `demo` (others stubbed) |
| Tests | ✅ `test_polynomial`, `test_checker` (20 cases) |

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
associativity, distributivity, …), normalisation, and the checker (accepts the
classic three-variable certificate; rejects negative coefficients, wrong
expansions, missing terms, and extra terms).

## Run the demo

```
dune exec a-geq-b -- demo
```

Proves `a² + b² + c² ≥ a·b + b·c + c·a` via the built-in certificate, runs it
through the trusted checker, and prints a readable proof (plus LaTeX) ending in
`Status: PROVED`.

```
dune exec a-geq-b -- --help
```

## Deliberately not implemented yet

Per the implementation brief, these are **stretch goals, not foundations**, and
are intentionally left for later prompts:

- the **parser** (`prove "a^2+b^2 >= 2*a*b"` → `Ast`) — grammar is documented in
  [`lib/parser.ml`](lib/parser.ml);
- **JSON certificate loading** (`Certificate.of_json`) — blocked on the parser
  (turning `"a - b"` back into a polynomial). The example
  [`examples/hello_world.cert.json`](examples/hello_world.cert.json) is a
  reference artifact; the demo/tests build certificates directly in OCaml;
- the **automatic prover** — quadratic-form / Gram-matrix SOS search,
  pairwise-difference patterns;
- **SDP** integration, **Coq/Lean** extraction, a **web frontend**, and any
  olympiad corpus study.

See [`CLAUDE.md`](CLAUDE.md) for the working rules and the next implementation
step.
