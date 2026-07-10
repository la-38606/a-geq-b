import Lake
open Lake DSL

package «aeqb_check» where
  -- keep the file self-contained and explicit
  leanOptions := #[⟨`autoImplicit, false⟩]

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git" @ "v4.31.0"

@[default_target]
lean_lib «AeqbCheck» where

-- Machine-generated proofs emitted by `a-geq-b lean` (see regen.sh).
@[default_target]
lean_lib «Proofs» where
