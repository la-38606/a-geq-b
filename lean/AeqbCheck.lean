import Mathlib.Algebra.MvPolynomial.Eval
import Mathlib.Data.Real.Basic
import Mathlib.Data.Rat.Cast.Order
import Mathlib.Algebra.Order.BigOperators.Group.List
import Mathlib.Tactic

/-!
# A formally verified sum-of-squares checker

A machine-verified reimplementation of A≥B's trusted checker (`lib/checker.ml`).

`checkSOS p cert` decides whether `cert` is a valid sum-of-squares certificate
for `p ≥ 0`, over the rationals and exactly.  `checkSOS_sound` proves that a
`true` answer entails that `p` is nonnegative at *every* real point, precisely
the guarantee the OCaml checker is trusted to provide, here discharged by the
Lean kernel.
-/

namespace AeqbCheck

open MvPolynomial

variable {n : ℕ}

/-- A certificate: a list of `(coefficient, polynomial)` pairs over `ℚ`, each
    standing for `coeff • poly²`. -/
abbrev Cert (n : ℕ) : Type := List (ℚ × MvPolynomial (Fin n) ℚ)

/-- The polynomial `∑ᵢ cᵢ · qᵢ²` denoted by a certificate. -/
noncomputable def expand (cert : Cert n) : MvPolynomial (Fin n) ℚ :=
  (cert.map fun cq => C cq.1 * cq.2 ^ 2).sum

/-- The checker: every coefficient is nonnegative and `p` equals the expansion.
    The direct analogue of `Checker.check_sos`. -/
noncomputable def checkSOS (p : MvPolynomial (Fin n) ℚ) (cert : Cert n) : Bool :=
  (cert.all fun cq => decide (0 ≤ cq.1)) && decide (p = expand cert)

/-- **Soundness of the checker.** If `checkSOS p cert` returns `true`, then `p`
    evaluates to a nonnegative real at every point.  A nonnegative-coefficient
    sum of squares is `≥ 0`; the checker having established the polynomial
    identity `p = ∑ cᵢ qᵢ²`, evaluation preserves it. -/
theorem checkSOS_sound (p : MvPolynomial (Fin n) ℚ) (cert : Cert n)
    (h : checkSOS p cert = true) (x : Fin n → ℝ) :
    0 ≤ aeval x p := by
  simp only [checkSOS, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
  obtain ⟨hpos, rfl⟩ := h
  rw [expand, map_list_sum, List.map_map]
  apply List.sum_nonneg
  intro y hy
  rw [List.mem_map] at hy
  obtain ⟨cq, hcq, rfl⟩ := hy
  simp only [Function.comp_apply, map_mul, map_pow, aeval_C]
  have hc : (0 : ℝ) ≤ algebraMap ℚ ℝ cq.1 := by
    rw [eq_ratCast]
    exact_mod_cast hpos cq hcq
  exact mul_nonneg hc (sq_nonneg _)

end AeqbCheck
