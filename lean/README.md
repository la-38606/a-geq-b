# A≥B — formally verified checker (Lean 4)

This directory upgrades A≥B's trusted core from *small and audited* to
*machine-verified*: a reimplementation of the certificate checker in **Lean 4 /
Mathlib**, with a **proved soundness theorem**.

The whole system reports `PROVED` only when the trusted OCaml checker
([`lib/checker.ml`](../lib/checker.ml)) accepts a certificate. That checker is
tiny and audited. Here we re-express the same check over Mathlib's
`MvPolynomial (Fin n) ℚ` and prove — in the Lean kernel — that it can never
accept a certificate for a polynomial that is negative somewhere.

## The theorem

[`AeqbCheck.lean`](AeqbCheck.lean) defines

```lean
def expand   (cert)   := (cert.map fun (c, q) => C c * q ^ 2).sum
def checkSOS (p) (cert) : Bool :=
  (cert.all fun (c, _) => decide (0 ≤ c)) && decide (p = expand cert)
```

and proves

```lean
theorem checkSOS_sound (p : MvPolynomial (Fin n) ℚ) (cert)
    (h : checkSOS p cert = true) (x : Fin n → ℝ) :
    0 ≤ aeval x p
```

“If the checker accepts, the target is nonnegative at every real point” — exactly
the guarantee `Checker.check_sos` is trusted to provide. The proof mirrors the
informal one: a nonnegative-coefficient sum of squares is `≥ 0`
(`sq_nonneg`, `mul_nonneg`, `List.sum_nonneg`), once the checker has established
the polynomial identity `p = ∑ cᵢ qᵢ²`.

The proof is complete and axiom-clean:

```
#print axioms checkSOS_sound
-- 'checkSOS_sound' depends on axioms: [propext, Classical.choice, Quot.sound]
```

i.e. only the three standard Mathlib axioms — no `sorry`.

## Emitting checkable Lean proofs

Beyond verifying the *checker*, A≥B can export each individual proof as a Lean
theorem. `a-geq-b lean "<inequality>" [name]` auto-proves the inequality,
re-checks the certificate with the trusted OCaml checker, and writes a
self-contained Lean file to stdout:

```
$ a-geq-b lean "a^2 + b^2 >= 2*a*b" aeqb_sq_diff
import Mathlib

theorem aeqb_sq_diff (a b : ℝ) : (0 : ℝ) ≤ a^2 - 2*a*b + b^2 := by
  have h : (a^2 - 2*a*b + b^2 : ℝ) = (1) * (a - b) ^ 2 := by ring
  rw [h]
  positivity
```

The proof rewrites `p` into its sum-of-squares form by `ring` — an identity that
holds *because* the checker already verified `p = ∑ cᵢ qᵢ²` — and closes
`0 ≤ ∑ cᵢ qᵢ²` by `positivity`. This is untrusted OUTPUT: a bogus certificate
would yield a Lean file that fails to compile, never a false theorem.

[`Proofs.lean`](Proofs.lean) collects such proofs for a spread of inequalities
(1–3 variables, degree 2 and 4, rational coefficients); `lake build` has Lean's
kernel check every one. Regenerate it straight from the prover with
[`regen.sh`](regen.sh). Each theorem is thus machine-checked twice: the exact
rational identity in OCaml, then `ring` / `positivity` in Lean.

## Build

```
cd lean
lake exe cache get   # fetch prebuilt Mathlib (first time)
lake build           # AeqbCheck.lean (~70s) + Proofs.lean (~250s, imports Mathlib)
```

Pinned to `leanprover/lean4:v4.31.0` (see `lean-toolchain`); the exact Mathlib
revision is locked in `lake-manifest.json`. Build artifacts and the fetched
Mathlib live under `.lake/` (git-ignored).

## Relation to the OCaml checker

`AeqbCheck.checkSOS` is the specification of `Checker.check_sos`: the same two
conditions (every coefficient `≥ 0`; `p` equals the sum-of-squares expansion),
over exact rationals. The OCaml version is the fast executable used in the tool;
this Lean version is the *proof* that the specification is sound. The prover now
also emits a Lean proof per certificate (see above), so each `A≥B` proof can
become a machine-checked Lean theorem. A further step would be to run this Lean
checker as an independent oracle beside the OCaml one.
