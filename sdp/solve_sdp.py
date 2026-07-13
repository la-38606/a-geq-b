"""Numerical SDP solver for the Gram feasibility problem emitted by `a-geq-b
sdp-emit`.

This is the untrusted, numerical half of the prover. It reads the Gram
semidefinite program as JSON, finds an approximate positive-semidefinite Gram
matrix Q with cvxpy, and writes Q back as JSON. OCaml then rounds Q to exact
rationals and the trusted checker has the final say, so nothing here needs to be
correct for soundness -- only for the prover to succeed.

Problem JSON (from `sdp-emit`):
    { "dim": r,
      "basis": [[e, ..], ..],                       # for reference only
      "constraints": [ { "terms": [[i, j], ..], "rhs": "p/q" }, .. ] }
where each constraint means  sum_{(i,j) in terms} w_ij * Q[i][j] = rhs, with
w_ij = 1 on the diagonal and 2 off it (since Q is symmetric).

Solution JSON (to stdout):
    { "status": "...", "min_eig": t, "Q": [[..r floats..], .. r rows ..] }
"""
import sys
import json
from fractions import Fraction

import numpy as np
import cvxpy as cp


def solve(problem):
    r = problem["dim"]
    Q = cp.Variable((r, r), symmetric=True)
    t = cp.Variable()

    # Q - t*I >= 0 with t maximized pushes the solution to the interior of the
    # PSD cone when possible, which rounds to an exact rational matrix far more
    # reliably than a solution sitting on the boundary.
    cons = [Q - t * np.eye(r) >> 0]
    for c in problem["constraints"]:
        expr = 0
        for (i, j) in c["terms"]:
            expr = expr + (Q[i, j] if i == j else 2 * Q[i, j])
        cons.append(expr == float(Fraction(c["rhs"])))

    prob = cp.Problem(cp.Maximize(t), cons)
    # CLARABEL (shipped with cvxpy) is a solid interior-point conic solver; fall
    # back to SCS if it is unavailable or errors on a particular instance.
    for solver in (cp.CLARABEL, cp.SCS):
        try:
            prob.solve(solver=solver)
            if Q.value is not None:
                break
        except (cp.error.SolverError, Exception):
            continue

    if Q.value is None:
        return {"status": str(prob.status), "min_eig": None, "Q": None}
    return {
        "status": str(prob.status),
        "min_eig": None if t.value is None else float(t.value),
        "Q": np.asarray(Q.value).tolist(),
    }


def main():
    problem = json.load(sys.stdin)
    json.dump(solve(problem), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
