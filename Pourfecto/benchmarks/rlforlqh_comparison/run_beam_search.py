#!/usr/bin/env python3
"""Run rlforlqh's beam-search algorithm (ported in beam_search_lib.py) against canonical instances.

Success is defined as an exact match on every grid cell (see beam_search_lib.py's module docstring
for why the `goal` dict passed to BeamSearch must include every column, not just naturally nonzero
ones) -- the same criterion greedy.py and Pourfecto's exact-priority solve use, so success/failure is
comparable across all three solvers.

Metrics logged per instance:
  - n_transfers: number of dispense (op==2) commands in the winning protocol, i.e. the number of
    times liquid was actually delivered somewhere -- the beam-search analogue of greedy's
    pick-up/drop-off count and Pourfecto's active-flow count.
  - distance: the winning beam's `cost`, which under the default cost weights (mc=1, ac=dc=zc=0) is
    exactly the total Manhattan distance the pipette head traveled.

Beam search's per-iteration cost is O(n^2) candidates per beam (transition_func considers every
grid column), so a per-instance wall-clock budget (--timeout, default 30s) is enforced via
beam_search_lib's `deadline` parameter; instances that hit it are logged as timeouts, not silently
skipped.
"""
import argparse
import csv
import glob
import json
import os
import time

import numpy as np

from beam_search_lib import Machine


def instance_to_start_goal(instance):
    n, _ = instance["grid"]
    k = instance["n_types"]
    start = np.zeros((k, n * n))
    for cell in instance["init"]:
        col = cell["row"] * n + cell["col"]
        start[cell["type"], col] = cell["amount"]

    goal = {col: np.zeros(k) for col in range(n * n)}  # every column, see beam_search_lib docstring
    for cell in instance["goal"]:
        col = cell["row"] * n + cell["col"]
        goal[col][cell["type"]] = cell["amount"]

    return start, goal, n, k


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--instances-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "results", "beam_search.csv"))
    ap.add_argument("--beam-size", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=30.0, help="per-instance wall-clock budget, seconds")
    ap.add_argument("--max-grid-n", type=int, default=None,
                     help="skip instances larger than this grid side length (beam search scales poorly)")
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    paths = sorted(glob.glob(os.path.join(args.instances_dir, "*.json")))

    rows = []
    for path in paths:
        with open(path) as f:
            instance = json.load(f)
        n = instance["grid"][0]
        if args.max_grid_n is not None and n > args.max_grid_n:
            continue

        start, goal, n, k = instance_to_start_goal(instance)
        name = os.path.splitext(os.path.basename(path))[0]

        machine = Machine()
        t0 = time.time()
        deadline = t0 + args.timeout
        machine.BeamSearch(start, goal, beam_size=args.beam_size, N=n, num_sol=k, deadline=deadline)
        elapsed = time.time() - t0

        timed_out = elapsed >= args.timeout
        success = len(machine.solutions) > 0
        n_transfers = distance = ""
        if success:
            best = sorted(machine.solutions, key=lambda b: b.cost)[0]
            n_transfers = sum(1 for op, _, _ in best.protocol if op == 2)
            distance = best.cost

        rows.append({
            "solver": "beam_search", "instance": name, "grid_n": n, "n_types": k,
            "total_units": int(start.sum()), "success": success,
            "n_transfers": n_transfers, "distance": distance,
            "wall_time_s": round(elapsed, 6), "timed_out": timed_out,
        })
        print(f"{name}: success={success} transfers={n_transfers} distance={distance} "
              f"time={elapsed:.2f}s timed_out={timed_out}")

    if not rows:
        print("no instances matched filters; nothing written")
        return

    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
