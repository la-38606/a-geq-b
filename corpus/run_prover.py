#!/usr/bin/env python3
"""Run the automatic prover over the whole corpus and report.

For each entry, runs `a-geq-b prove "<claim>"` and compares the reported status
to the entry's category. Two things are enforced (hard failures):

  * SOUNDNESS: no entry outside `in_scope_sos` may be PROVED. Proving a `false`,
    `out_of_scope_v1`, or `not_sos` claim would be a bug in the trusted path.
  * every claim must parse (never INVALID_INPUT).

Coverage of the `in_scope_sos` entries is reported but NOT required to be
complete: the prover grows stage by stage, so unproved in-scope targets are
listed as "todo", broken down by degree, rather than failed.

Usage:  python3 corpus/run_prover.py
Exit code is non-zero on any soundness violation or parse failure.
"""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "_build", "default", "bin", "main.exe")
CORPUS = os.path.join(ROOT, "corpus", "inequalities.json")


def status_of(output: str) -> str:
    for line in output.splitlines():
        s = line.strip()
        if s.startswith("Status:"):
            return s.split(":", 1)[1].strip()
    return "<no status>"


def main() -> int:
    if not os.path.exists(EXE):
        print(f"error: {EXE} not found. Run `dune build` first.", file=sys.stderr)
        return 2

    with open(CORPUS) as f:
        entries = json.load(f)["inequalities"]

    proved_in_scope = 0
    in_scope_total = 0
    todo = []               # in_scope entries not proved yet
    soundness_failures = []  # non-in_scope entries that got PROVED
    parse_failures = []

    for e in entries:
        out = subprocess.run([EXE, "prove", e["claim"]], capture_output=True, text=True)
        status = status_of(out.stdout + out.stderr)

        if status == "INVALID_INPUT":
            parse_failures.append(f"{e['id']}: {e['claim']}")
            continue

        if e["category"] == "in_scope_sos":
            in_scope_total += 1
            if status == "PROVED":
                proved_in_scope += 1
            else:
                todo.append((e.get("degree", "?"), e["id"]))
        else:
            # out_of_scope_v1 / not_sos / false must never be proved.
            if status == "PROVED":
                soundness_failures.append(f"{e['id']} [{e['category']}]: {e['claim']}")

    # --- report ---
    print(f"in_scope_sos proved: {proved_in_scope}/{in_scope_total}")
    if todo:
        by_deg = {}
        for deg, _ in todo:
            by_deg[deg] = by_deg.get(deg, 0) + 1
        print("  still todo by degree: "
              + ", ".join(f"deg {d}: {n}" for d, n in sorted(by_deg.items(), key=str)))
    print("soundness (no non-in-scope entry proved): "
          + ("OK" if not soundness_failures else "VIOLATED"))

    ok = True
    if soundness_failures:
        ok = False
        print("\nSOUNDNESS VIOLATIONS (prover proved something it must not):")
        for m in soundness_failures:
            print("  " + m)
    if parse_failures:
        ok = False
        print("\nPARSE FAILURES:")
        for m in parse_failures:
            print("  " + m)

    if ok:
        print("\nOK: prover is sound over the corpus; all claims parse.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
