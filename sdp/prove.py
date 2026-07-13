#!/usr/bin/env python3
"""Numerical SDP prover for A>=B: the orchestrator that closes targets the exact
OCaml search cannot.

Pipeline (each step is a plain subprocess call, like the corpus scripts):

    1. `a-geq-b sdp-emit "<ineq>"`   -- OCaml emits the Gram SDP as JSON
    2. solve_sdp.solve(...)          -- cvxpy finds an approximate PSD Gram Q
    3. `a-geq-b sdp-check "<ineq>"`  -- OCaml rounds Q to exact rationals and the
                                        trusted checker confirms (or rejects)

Only step 3's checker decides PROVED, so steps 1-2 are fully untrusted: a wrong
numerical answer yields NO_CERT_FOUND, never a false proof.

Usage:
    python sdp/prove.py "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d"

Run it with the interpreter that has cvxpy installed (e.g. the project venv):
    .venv/bin/python sdp/prove.py "<inequality>"
"""
import os
import sys
import json
import tempfile
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import solve_sdp  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "_build", "default", "bin", "main.exe")


def main(argv):
    if len(argv) != 2:
        print('usage: prove.py "<inequality>"', file=sys.stderr)
        return 3
    claim = argv[1]

    if not os.path.exists(EXE):
        print(f"error: {EXE} not found; run `dune build` first.", file=sys.stderr)
        return 3

    # 1. emit the Gram SDP
    emit = subprocess.run([EXE, "sdp-emit", claim], capture_output=True, text=True)
    if emit.returncode != 0:
        sys.stderr.write(emit.stderr)
        return emit.returncode
    problem = json.loads(emit.stdout)

    # 2. solve it numerically
    solution = solve_sdp.solve(problem)
    if solution.get("Q") is None:
        print(f"solver returned no matrix (status: {solution.get('status')}).",
              file=sys.stderr)

    # 3. round + trusted check (write the solution to a temp file for sdp-check)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(solution, f)
        sol_path = f.name
    try:
        check = subprocess.run([EXE, "sdp-check", claim, sol_path])
    finally:
        os.unlink(sol_path)
    return check.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
