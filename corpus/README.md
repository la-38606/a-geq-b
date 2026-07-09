# A≥B inequality corpus

A curated set of polynomial inequalities for testing the A≥B prover and checker.
The single source of truth is [`inequalities.json`](inequalities.json).

## Why a corpus

- **Regression targets for the checker (now).** Every entry tagged
  `in_scope_sos` carries an exact sum-of-squares certificate over ℚ. These are
  *machine-verified*: [`verify.py`](verify.py) feeds each one to the trusted
  `a-geq-b check` command and confirms `PROVED`. A certificate that verifies is
  a proof that the inequality holds for **all real values** — so the corpus is
  self-checking, not just asserted.
- **Targets for the prover (later).** Once the automatic prover (Milestone 5)
  exists, it should return `PROVED` for the `in_scope_sos` entries and
  `NO_CERT_FOUND` for everything else — never `PROVED` for a `not_sos`,
  `out_of_scope_v1`, or `false` entry (soundness).

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

## Running the verifier

```
dune build
python3 corpus/verify.py
```

It reports the entry counts by category and verifies every certificate. Exit
code is non-zero if any certificate fails to check or any claim fails to parse.

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
