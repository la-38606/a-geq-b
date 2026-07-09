# A≥B inequality corpus

A curated set of **119** inequalities for testing the A≥B prover and checker,
including rational-function ones (denominators are cleared). The single source
of truth is [`inequalities.json`](inequalities.json).

| category | count | v1 `expected` |
| --- | --- | --- |
| `in_scope_sos` | 63 (60 with certificates) | `PROVED` |
| `out_of_scope_v1` | 50 | `NO_CERT_FOUND` |
| `not_sos` | 3 | `NO_CERT_FOUND` |
| `false` | 3 | `NO_CERT_FOUND` |

Degrees range from 1 to 8 (rational entries higher after clearing), in 1–8
variables. Two verification passes keep it honest: `verify.py` *proves* the 60
certified entries exactly with the trusted checker, and `sanity_sample.py`
*numerically samples* all 119 on their domains.

## Why a corpus

- **Regression targets for the checker (now).** Every entry tagged
  `in_scope_sos` carries an exact sum-of-squares certificate over ℚ. These are
  *machine-verified*: [`verify.py`](verify.py) feeds each one to the trusted
  `a-geq-b check` command and confirms `PROVED`. A certificate that verifies is
  a proof that the inequality holds for **all real values** — so the corpus is
  self-checking, not just asserted.
- **Targets for the prover.** The automatic prover should return `PROVED` for
  the `in_scope_sos` entries and `NO_CERT_FOUND` for everything else — never
  `PROVED` for a `not_sos`, `out_of_scope_v1`, or `false` entry (soundness).
  [`run_prover.py`](run_prover.py) enforces the soundness half over the whole
  corpus and reports coverage; it currently proves 53 of the 63 `in_scope_sos`
  targets.

## Entry format

```jsonc
{
  "id": "three-var-symmetric",          // unique slug
  "claim": "a^2 + b^2 + c^2 >= a*b + b*c + c*a",  // parser-compatible string
  "variables": ["a", "b", "c"],          // ordering used by the SOS polys
  "degree": 2,                            // total degree of A - B
  "category": "in_scope_sos",             // see below
  "expected": "PROVED",                   // what v1 should output
  "domain": "all reals",                  // where the inequality holds
  "constraints": [],                      // optional side constraints
  "source": "Evan Chen, Ineq handout, Example 1.2",
  "sos": [                                // optional exact certificate
    {"coeff": "1/2", "poly": "a - b"},
    {"coeff": "1/2", "poly": "b - c"},
    {"coeff": "1/2", "poly": "a - c"}
  ],
  "notes": "Half the sum of squared pairwise differences."
}
```

Because the checker's JSON loader ignores unknown fields, any entry with an
`sos` field is itself a valid certificate: `verify.py` just projects out
`{claim, variables, sos}` and runs `check`.

## Categories

| category | meaning | `expected` |
| --- | --- | --- |
| `in_scope_sos` | nonnegative for all reals, SOS-provable over ℚ (has a certificate) | `PROVED` |
| `out_of_scope_v1` | true but needs constraints (positivity, `abc=1`, `a+b+c=k`, triangle sides) — not nonnegative on all of ℝⁿ | `NO_CERT_FOUND` |
| `not_sos` | nonnegative for all reals but **not** a sum of squares (Motzkin / Choi–Lam) | `NO_CERT_FOUND` |
| `false` | deliberately false — a soundness trap | `NO_CERT_FOUND` |

`out_of_scope_v1` and `not_sos` entries are genuinely true (or, for `not_sos`,
nonnegative) statements; they are simply outside what an SOS-over-ℝ engine can
prove. They are kept as aspirational targets and as soundness tests.

## Running the checks

```
dune build
python3 corpus/verify.py         # exact: run every SOS certificate through `a-geq-b check`
python3 corpus/sanity_sample.py  # numeric: sample every entry on its domain
```

- `verify.py` projects each certified entry to `{claim, variables, sos}`, runs
  the trusted `a-geq-b check`, and asserts the expected status. A pass is a
  machine proof over all reals. It also checks the schema and that every claim
  parses.
- `sanity_sample.py` covers what the SOS checker cannot: it evaluates each claim
  at thousands of random points drawn from its domain (nonnegative / positive
  orthant, `sum = k`, `abc = 1`, sphere, triangle sides, …), asserting the
  inequality holds — and, for `false` entries, that a counterexample exists.

Both exit non-zero on any discrepancy. Every entry currently passes both.

## Sources

The corpus is curated from standard olympiad-inequality references and classical
results (full list in `inequalities.json`):

- Evan Chen, *A Brief Introduction to Olympiad Inequalities*.
- Evan Chen, *Supersums of Square-Weights (SOS)*.
- Manfrino, Ortega, Delgado, *Inequalities: A Mathematical Olympiad Approach*.
- Art of Problem Solving archives.
- Classical: AM–GM, Cauchy–Schwarz / Lagrange, Schur, QM–AM (variance).

Every inequality was checked for correctness — the `in_scope_sos` subset
mechanically (via the checker), the rest against their published sources.
