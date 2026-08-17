#!/bin/sh
# Regenerate lean/Proofs.lean.
#
# For each inequality below, `a-geq-b lean` parses it, auto-proves it, re-checks
# the certificate with the TRUSTED OCaml checker, and emits a Lean proof. We
# concatenate the theorems under a single `import Mathlib` and let `lake build`
# have Lean's kernel check them. So every theorem here is machine-checked twice:
# once by the OCaml checker (exact rational identity) and once by Lean.
#
# Run from anywhere:  sh lean/regen.sh   (then: cd lean && lake build)
set -eu
cd "$(dirname "$0")/.."
OUT=lean/Proofs.lean

dune build bin/main.exe

{
  cat <<'HEADER'
/-
  A>=B machine-generated Lean proofs.  DO NOT EDIT BY HAND.

  Each theorem is the verbatim output of `a-geq-b lean "<inequality>" <name>`:
  the untrusted prover finds an SOS certificate, the trusted OCaml checker
  confirms the exact rational identity p = sum c_i q_i^2, and the emitter turns
  it into a Lean proof (`ring` for the identity, `positivity` for the nonnegative
  sum of squares).  `lake build` then has Lean's kernel check every one.

  Regenerate with: sh lean/regen.sh
-/
import Mathlib
HEADER
  echo
  # name|inequality, one theorem each.  Redirect dune's stdin so it does not
  # consume the here-doc that feeds the loop.
  while IFS='|' read -r name ineq; do
    [ -z "$name" ] && continue
    dune exec --no-build a-geq-b -- lean "$ineq" "$name" </dev/null | sed '/^import Mathlib$/d'
  done <<'CASES'
aeqb_shift|a^2 >= 2*a - 1
aeqb_sq_diff|a^2 + b^2 >= 2*a*b
aeqb_amgm3|a^2 + b^2 + c^2 >= a*b + b*c + c*a
aeqb_quartic|a^4 + b^4 >= 2*a^2*b^2
aeqb_quartic1|a^4 + 1 >= 2*a^2
CASES
} > "$OUT"

echo "wrote $OUT"
