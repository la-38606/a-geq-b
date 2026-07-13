#!/usr/bin/env python3
"""Run the numerical SDP prover over the corpus and report combined coverage.

For each `in_scope_sos` target the exact prover (`a-geq-b prove`) misses, try the
numerical SDP route (`sdp/prove.py`: emit -> solve with cvxpy -> round -> trusted
check) and report how many the two paths prove together.

Two things are enforced as hard failures:

  * COVERAGE: with the SDP path, every in_scope_sos target should be proved.
  * SOUNDNESS: the SDP path must NOT prove any `not_sos` or `false` target. The
    not-SOS traps (Motzkin, Choi-Lam) are nonnegative but not sums of squares, so
    their Gram SDP is infeasible; a numerical solver that fudges one must still be
    caught when OCaml rounds and the trusted checker verifies. This is the key
    soundness test for the numerical path.

Run with the interpreter that has cvxpy (the project venv):
    .venv/bin/python corpus/run_sdp.py
Exit code is non-zero on any soundness violation (or missing coverage).
"""
import json
import os
import sys
import tempfile
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "_build", "default", "bin", "main.exe")
CORPUS = os.path.join(ROOT, "corpus", "inequalities.json")
sys.path.insert(0, os.path.join(ROOT, "sdp"))


def status_of(output):
    for line in output.splitlines():
        s = line.strip()
        if s.startswith("Status:"):
            return s.split(":", 1)[1].strip()
    return "<no status>"


def exact_status(claim):
    out = subprocess.run([EXE, "prove", claim], capture_output=True, text=True)
    return status_of(out.stdout + out.stderr)


def sdp_status(claim, solve):
    """Run the full emit -> solve -> check pipeline; return the reported status."""
    emit = subprocess.run([EXE, "sdp-emit", claim], capture_output=True, text=True)
    if emit.returncode != 0:
        return "INVALID_INPUT"
    try:
        solution = solve(json.loads(emit.stdout))
    except Exception as exc:  # a solver failure is a miss, never a false proof
        return f"solver-error({type(exc).__name__})"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(solution, f)
        path = f.name
    try:
        out = subprocess.run([EXE, "sdp-check", claim, path], capture_output=True, text=True)
    finally:
        os.unlink(path)
    return status_of(out.stdout + out.stderr)


def main():
    if not os.path.exists(EXE):
        print(f"error: {EXE} not found. Run `dune build` first.", file=sys.stderr)
        return 2
    try:
        import solve_sdp
    except ImportError:
        print("error: cvxpy not available. Install sdp/requirements.txt into a venv "
              "and run this with that interpreter.", file=sys.stderr)
        return 2

    with open(CORPUS) as f:
        entries = json.load(f)["inequalities"]

    in_scope = [e for e in entries if e["category"] == "in_scope_sos"]
    traps = [e for e in entries if e["category"] in ("not_sos", "false")]

    # --- coverage: exact first, SDP for the misses ---
    proved, via_sdp, still_missing = 0, [], []
    for e in in_scope:
        if exact_status(e["claim"]) == "PROVED":
            proved += 1
        elif sdp_status(e["claim"], solve_sdp.solve) == "PROVED":
            proved += 1
            via_sdp.append(e["claim"])
        else:
            still_missing.append(e["claim"])

    print(f"in_scope_sos proved (exact + SDP): {proved}/{len(in_scope)}"
          f"  ({len(via_sdp)} newly closed by the SDP path)")
    for c in via_sdp:
        print(f"  + {c}")
    for c in still_missing:
        print(f"  ! still unproved: {c}")

    # --- soundness: the SDP path must never prove a not-SOS or false target ---
    violations = []
    for e in traps:
        if sdp_status(e["claim"], solve_sdp.solve) == "PROVED":
            violations.append(f"{e['id']} [{e['category']}]: {e['claim']}")
    print(f"SDP soundness on {len(traps)} not-SOS / false traps: "
          + ("OK" if not violations else "VIOLATED"))

    ok = not violations and not still_missing
    if violations:
        print("\nSOUNDNESS VIOLATIONS (SDP path proved a non-SOS target):")
        for v in violations:
            print("  " + v)
    if still_missing:
        print(f"\n{len(still_missing)} in-scope target(s) still unproved (coverage gap).")
    print("\n" + ("OK: SDP path closes the in-scope corpus and stays sound."
                  if ok else "FAILED."))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
