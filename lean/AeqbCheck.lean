import Mathlib.Data.Real.Basic

/-- Scaffold sanity check: Mathlib is available and a real square is nonnegative. -/
example (x : ℝ) : 0 ≤ x ^ 2 := sq_nonneg x
