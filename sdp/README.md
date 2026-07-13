# Numerical SDP prover

The untrusted, numerical half of A>=B. It closes the targets whose sum-of-squares
certificate needs a Gram matrix with more freedom than the exact OCaml search
(`a-geq-b prove`) explores by hand.

## Why it exists

Proving `p >= 0` by sum of squares means finding a positive-semidefinite Gram
matrix `Q` with `p = z^T Q z` over a monomial basis `z`. When `Q` is uniquely
determined (or nearly so) the OCaml prover solves it exactly. When it is not,
finding a PSD `Q` in the affine family `{Q : z^T Q z = p}` is a genuine
**semidefinite program** best handed to a numerical solver. This directory is
that solver, plus the glue.

## How it stays sound

The numerical result is never trusted. The pipeline is:

1. `a-geq-b sdp-emit "<ineq>"` — OCaml emits the Gram SDP as JSON.
2. `solve_sdp.py` — cvxpy (CLARABEL) finds an approximate PSD `Q`.
3. `a-geq-b sdp-check "<ineq>" <solution>` — OCaml **rounds `Q` to exact
   rationals**, completes it so `z^T Q z = p` holds exactly, and the **trusted
   checker** verifies the resulting certificate.

Only step 3's checker decides `PROVED`. A wrong or imprecise numerical answer
rounds to a matrix that is not PSD, or to a certificate the checker rejects, so
the outcome is `NO_CERT_FOUND` — never a false proof. The floating-point code
is quarantined outside the trust boundary.

## Setup

```
python3 -m venv .venv
.venv/bin/python -m pip install -r sdp/requirements.txt
dune build            # the a-geq-b binary the scripts call
```

## Use

```
.venv/bin/python sdp/prove.py "a^4 + b^4 + c^4 + d^4 >= 4*a*b*c*d"
```

prints the certificate and a `Status: PROVED` line, exactly like `a-geq-b prove`.

## Files

- `prove.py` — the orchestrator: runs `sdp-emit`, solves, runs `sdp-check`.
- `solve_sdp.py` — reads the Gram SDP on stdin, writes a numerical `Q` on stdout;
  usable standalone or imported by `prove.py`.
- `requirements.txt` — cvxpy / numpy / scipy.

Together with the exact prover this proves all 63 in-scope sum-of-squares targets
in the corpus (`corpus/run_sdp.py`).
