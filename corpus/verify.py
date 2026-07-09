#!/usr/bin/env python3
"""Verify the A>=B inequality corpus.

For every corpus entry that carries an ``sos`` certificate, this writes a
temporary certificate JSON and runs the built ``a-geq-b check`` command on it.
An entry whose ``expected`` status is ``PROVED`` must be accepted by the trusted
checker; this is what guarantees that the stated inequality is actually true and
that its recorded SOS decomposition is exact.

For entries without an ``sos`` certificate (constrained/out-of-scope or
not-SOS), it runs ``a-geq-b prove "<claim>"`` and only checks that the claim
*parses* (i.e. the status is not INVALID_INPUT) -- a cheap guard against typos
in the claim strings. It does not attempt to prove them (the automatic prover is
not built yet).

Usage:  python3 corpus/verify.py
Exit code is non-zero if any check fails.
"""

import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "_build", "default", "bin", "main.exe")
CORPUS = os.path.join(ROOT, "corpus", "inequalities.json")

REQUIRED_FIELDS = ("id", "claim", "variables", "category", "expected")
VALID_CATEGORIES = {"in_scope_sos", "out_of_scope_v1", "not_sos", "false"}
VALID_EXPECTED = {"PROVED", "NO_CERT_FOUND"}


def status_of(output: str) -> str:
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Status:"):
            return line.split(":", 1)[1].strip()
    return "<no status>"


def run_cli(*args: str) -> str:
    res = subprocess.run([EXE, *args], capture_output=True, text=True)
    return res.stdout + res.stderr


def main() -> int:
    if not os.path.exists(EXE):
        print(f"error: {EXE} not found. Run `dune build` first.", file=sys.stderr)
        return 2

    with open(CORPUS) as f:
        data = json.load(f)
    entries = data["inequalities"]

    ids: set[str] = set()
    n_total = len(entries)
    n_certified = 0
    failures: list[str] = []
    schema_errors: list[str] = []

    for e in entries:
        # --- schema / metadata sanity ---
        for field in REQUIRED_FIELDS:
            if field not in e:
                schema_errors.append(f"{e.get('id', '?')}: missing field '{field}'")
        eid = e.get("id", "?")
        if eid in ids:
            schema_errors.append(f"duplicate id '{eid}'")
        ids.add(eid)
        if e.get("category") not in VALID_CATEGORIES:
            schema_errors.append(f"{eid}: bad category {e.get('category')!r}")
        if e.get("expected") not in VALID_EXPECTED:
            schema_errors.append(f"{eid}: bad expected {e.get('expected')!r}")

        # --- behavioural check ---
        if "sos" in e:
            n_certified += 1
            cert = {"claim": e["claim"], "variables": e["variables"], "sos": e["sos"]}
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
                json.dump(cert, tf)
                path = tf.name
            try:
                status = status_of(run_cli("check", path))
            finally:
                os.unlink(path)
            if status != e["expected"]:
                failures.append(
                    f"{eid}: check gave {status}, expected {e['expected']}  ({e['claim']})"
                )
        else:
            # No certificate: just make sure the claim parses.
            status = status_of(run_cli("prove", e["claim"]))
            if status == "INVALID_INPUT":
                failures.append(f"{eid}: claim does not parse  ({e['claim']})")

    # --- report ---
    print(f"corpus: {n_total} inequalities, {n_certified} with SOS certificates")
    by_cat: dict[str, int] = {}
    for e in entries:
        by_cat[e.get("category", "?")] = by_cat.get(e.get("category", "?"), 0) + 1
    for cat, n in sorted(by_cat.items()):
        print(f"  {cat:16s} {n}")

    ok = True
    if schema_errors:
        ok = False
        print("\nSCHEMA ERRORS:")
        for m in schema_errors:
            print("  " + m)
    if failures:
        ok = False
        print("\nCHECK FAILURES:")
        for m in failures:
            print("  " + m)

    if ok:
        print("\nOK: all certified inequalities verified by the checker; all claims parse.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
