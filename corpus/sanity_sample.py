#!/usr/bin/env python3
"""Numerically sanity-check every corpus inequality on its domain.

This complements corpus/verify.py. Where verify.py *proves* the in_scope_sos
entries exactly (via the trusted checker), this script samples many random
points on each entry's stated domain and checks the inequality numerically. It
covers the entries the SOS checker cannot reason about -- the constrained
out_of_scope_v1 ones, the not_sos forms, and the deliberately false traps -- so
the whole corpus stays trustworthy, not just the certified part.

For each entry:
  in_scope_sos / not_sos : sample all reals, assert the inequality holds.
  out_of_scope_v1        : sample the constrained domain, assert it holds.
  false                  : sample, assert a counterexample EXISTS (else it is
                           not actually false and we flag it).

Domains are inferred from the "constraints" list. Recognised surfaces:
nonnegative / positive orthant, sum = k, product abc = 1, sphere
sum(x^2) = k, triangle sides, and "x + y >= 0". Anything unrecognised is
reported as SKIP rather than silently passing.

Usage:  python3 corpus/sanity_sample.py
Exit code is non-zero if any entry violates its expected behaviour.
"""

import json
import math
import os
import random
import re
import sys

random.seed(1234)
N = 20000
TOL = 1e-6

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "corpus", "inequalities.json")


def to_py(expr: str) -> str:
    return expr.replace("^", "**")


def ev(expr: str, ns: dict) -> float:
    return eval(to_py(expr), {"__builtins__": {}}, ns)  # noqa: S307 (trusted corpus data)


def split_rel(claim: str):
    for op in (">=", "<="):
        if op in claim:
            lhs, rhs = claim.split(op, 1)
            return lhs, op, rhs
    raise ValueError(f"no relation in {claim!r}")


def constraint_holds(con: str, ns: dict) -> bool:
    for op in (">=", "<=", ">", "<"):
        if op in con:
            lhs, rhs = con.split(op, 1)
            l, r = ev(lhs, ns), ev(rhs, ns)
            return {">=": l >= r - TOL, "<=": l <= r + TOL,
                    ">": l > r - TOL, "<": l < r - TOL}[op]
    return True  # equality constraints are realised by the sampler, not filtered


def make_sampler(entry):
    """Return (sampler, label) or (None, reason) if the domain is unrecognised.

    The sampler yields points that exactly satisfy any equality constraint;
    inequality constraints are enforced by rejection in `draw`.
    """
    V = entry["variables"]
    cons = entry.get("constraints", [])
    nonneg = any(re.fullmatch(r"[a-z]\s*>=?\s*0", c.strip()) for c in cons)
    strict = any(re.fullmatch(r"[a-z]\s*>\s*0", c.strip()) for c in cons)

    prod_eq = [c for c in cons if "=" in c and "*" in c and "^" not in c]
    sphere_eq = [c for c in cons if "=" in c and "^2" in c]
    sum_eq = [c for c in cons if "=" in c and "*" not in c and "^" not in c]
    tri = len(V) == 3 and any(re.search(r"[a-z]\s*\+\s*[a-z]\s*>\s*[a-z]", c) for c in cons)

    if prod_eq:  # e.g. a*b*c = 1  (positive reals)
        def s():
            xs = [random.uniform(0.2, 5) for _ in V[:-1]]
            p = 1.0
            for x in xs:
                p *= x
            xs.append(1.0 / p)
            return xs
        return s, "product=1"
    if sphere_eq:  # e.g. a^2+b^2+c^2 = k
        k = float(sphere_eq[0].split("=")[1])
        def s():
            xs = [random.uniform(-3, 3) for _ in V]
            n = math.sqrt(sum(x * x for x in xs)) or 1.0
            return [x * math.sqrt(k) / n for x in xs]
        return s, "sphere"
    if sum_eq:  # e.g. a+b+c = k
        k = float(sum_eq[0].split("=")[1])
        if nonneg:
            def s():
                xs = [random.uniform(0, 1) for _ in V]
                t = sum(xs) or 1.0
                return [x * k / t for x in xs]
        else:
            def s():
                xs = [random.uniform(-3, 3) for _ in V]
                d = (sum(xs) - k) / len(V)
                return [x - d for x in xs]
        return s, "sum=%g" % k
    if tri:  # sides of a triangle
        def s():
            x, y, z = (random.uniform(1e-2, 3) for _ in range(3))
            return [y + z, z + x, x + y]
        return s, "triangle"
    if any("+" in c and "0" in c for c in cons):  # e.g. a + b >= 0
        return (lambda: [random.uniform(-4, 4) for _ in V]), "reals+ineq"
    if nonneg:
        lo = 1e-2 if strict else 0.0
        return (lambda: [random.uniform(lo, 4) for _ in V]), "positive" if strict else "nonneg"
    if not cons:
        return (lambda: [random.uniform(-4, 4) for _ in V]), "reals"
    return None, "unrecognised constraints: " + "; ".join(cons)


def draw(sampler, entry, ns_vars):
    cons = entry.get("constraints", [])
    for _ in range(200):
        vals = sampler()
        ns = dict(zip(ns_vars, vals))
        if all(constraint_holds(c, ns) for c in cons):
            return ns
    return None  # gave up finding an in-domain point


def main() -> int:
    with open(CORPUS) as f:
        entries = json.load(f)["inequalities"]

    ok = True
    counts = {"OK": 0, "FAIL": 0, "SKIP": 0}
    for e in entries:
        V = e["variables"]
        lhs, op, rhs = split_rel(e["claim"])
        sampler, label = make_sampler(e)
        if sampler is None:
            counts["SKIP"] += 1
            print(f"SKIP {e['id']}: {label}")
            continue

        # margin(point) = lhs - rhs, oriented so the claim asserts margin >= 0.
        def margin(ns):
            m = ev(lhs, ns) - ev(rhs, ns)
            return m if op == ">=" else -m

        worst = None
        found_false = False
        for _ in range(N):
            ns = draw(sampler, e, V)
            if ns is None:
                break
            try:
                m = margin(ns)
            except ZeroDivisionError:
                continue  # a zero denominator; just try another point
            if m < -TOL:
                found_false = True
                if worst is None or m < worst[0]:
                    worst = (m, ns)

        if e["category"] == "false":
            # A false claim SHOULD be violated somewhere.
            if found_false:
                counts["OK"] += 1
            else:
                counts["FAIL"] += 1
                ok = False
                print(f"FAIL {e['id']}: expected a counterexample but none found")
        else:
            if not found_false:
                counts["OK"] += 1
            else:
                counts["FAIL"] += 1
                ok = False
                pt = {k: round(v, 3) for k, v in worst[1].items()}
                print(f"FAIL {e['id']} [{label}]: violated by {worst[0]:.4g} at {pt}")

    print(f"\nsampled {len(entries)} entries: "
          f"{counts['OK']} OK, {counts['FAIL']} FAIL, {counts['SKIP']} SKIP")
    if ok and counts["SKIP"] == 0:
        print("OK: every inequality behaves as its category claims on its domain.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
