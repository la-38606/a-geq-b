/-
  A>=B — machine-generated Lean proofs.  DO NOT EDIT BY HAND.

  Each theorem is the verbatim output of `a-geq-b lean "<inequality>" <name>`:
  the untrusted prover finds an SOS certificate, the trusted OCaml checker
  confirms the exact rational identity p = sum c_i q_i^2, and the emitter turns
  it into a Lean proof (`ring` for the identity, `positivity` for the nonnegative
  sum of squares).  `lake build` then has Lean's kernel check every one.

  Regenerate with: sh lean/regen.sh
-/
import Mathlib


theorem aeqb_shift (a : ℝ) : (0 : ℝ) ≤ a^2 - 2*a + 1 := by
  have h : (a^2 - 2*a + 1 : ℝ) = (1) * (-a + 1) ^ 2 := by ring
  rw [h]
  positivity

theorem aeqb_sq_diff (a b : ℝ) : (0 : ℝ) ≤ a^2 - 2*a*b + b^2 := by
  have h : (a^2 - 2*a*b + b^2 : ℝ) = (1) * (a - b) ^ 2 := by ring
  rw [h]
  positivity

theorem aeqb_amgm3 (a b c : ℝ) : (0 : ℝ) ≤ a^2 - a*b - a*c + b^2 - b*c + c^2 := by
  have h : (a^2 - a*b - a*c + b^2 - b*c + c^2 : ℝ) = (1) * (a - 1/2*b - 1/2*c) ^ 2 + (3/4) * (b - c) ^ 2 := by ring
  rw [h]
  positivity

theorem aeqb_quartic (a b : ℝ) : (0 : ℝ) ≤ a^4 - 2*a^2*b^2 + b^4 := by
  have h : (a^4 - 2*a^2*b^2 + b^4 : ℝ) = (1) * (-a^2 + b^2) ^ 2 := by ring
  rw [h]
  positivity

theorem aeqb_quartic1 (a : ℝ) : (0 : ℝ) ≤ a^4 - 2*a^2 + 1 := by
  have h : (a^4 - 2*a^2 + 1 : ℝ) = (1) * (-a^2 + 1) ^ 2 := by ring
  rw [h]
  positivity
