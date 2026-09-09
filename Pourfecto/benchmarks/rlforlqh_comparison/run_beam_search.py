#!/usr/bin/env python3
"""Run rlforlqh's beam-search algorithm (ported in beam_search_lib.py) against canonical instances,
with N randomized restarts per instance to measure the heuristic's run-to-run variance.

Success is defined as an exact match on every grid cell (see beam_search_lib.py's module docstring
for why the `goal` dict passed to BeamSearch must include every column, not just naturally nonzero
ones) -- the same criterion greedy.py and Pourfecto's exact-priority solve use, so success/failure is
comparable across all three solvers.

Metrics logged per instance (aggregated over --restarts seeds, default 100):
  - success_rate / n_success: fraction / count of restarts that found a solution.
  - mean_transfers / std_transfers, mean_distance / std_distance: over the successful restarts only.
    n_transfers per restart is the number of dispense (op==2) commands in the winning protocol --
    the beam-search analogue of greedy's pick-up/drop-off count and Pourfecto's active-flow count.
    distance per restart is the winning beam's `cost`, which under the default cost weights
    (mc=1, ac=dc=zc=0) is exactly the total Manhattan distance the pipette head traveled.
  - mean_wall_time_s / total_wall_time_s.

Beam search's per-iteration cost is O(n^2) candidates per beam (transition_func considers every
grid column), so a per-restart wall-clock budget (--timeout, default 2s) is enforced via
beam_search_lib's `deadline` parameter; restarts that hit it count as failures, not silently skipped
(tracked separately in n_timed_out). At 270 instances x 100 restarts, a single process is far too
slow for instances that fail most restarts (each can take close to the full timeout x100) -- work is
split across instances using a process pool (--workers, default: all cores) instead.
"""
import argparse
import csv
import glob
import json
import os
import random
import statistics
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

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


def run_restarts(start, goal, n, k, beam_size, timeout, n_restarts, base_seed):
    successes = []
    transfers_list = []
    distance_list = []
    times = []
    n_timed_out = 0
    for seed in range(n_restarts):
        rng = random.Random((base_seed, seed))
        machine = Machine()
        t0 = time.time()
        deadline = t0 + timeout
        machine.BeamSearch(start, goal, beam_size=beam_size, N=n, num_sol=k, deadline=deadline, rng=rng)
        elapsed = time.time() - t0
        times.append(elapsed)

        if elapsed >= timeout:
            n_timed_out += 1

        success = len(machine.solutions) > 0
        successes.append(success)
        if success:
            best = sorted(machine.solutions, key=lambda b: b.cost)[0]
            transfers_list.append(sum(1 for op, _, _ in best.protocol if op == 2))
            distance_list.append(best.cost)

    return successes, transfers_list, distance_list, times, n_timed_out


def process_instance(path, beam_size, timeout, n_restarts):
    with open(path) as f:
        instance = json.load(f)
    start, goal, n, k = instance_to_start_goal(instance)
    name = os.path.splitext(os.path.basename(path))[0]

    t0 = time.time()
    successes, transfers_list, distance_list, times, n_timed_out = run_restarts(
        start, goal, n, k, beam_size, timeout, n_restarts, base_seed=name)
    wall = time.time() - t0

    n_success = sum(successes)
    success_rate = n_success / n_restarts
    row = {
        "solver": "beam_search", "instance": name, "grid_n": n, "n_types": k,
        "total_units": int(start.sum()), "restarts": n_restarts,
        "n_success": n_success, "success_rate": round(success_rate, 4),
        "mean_transfers": round(statistics.mean(transfers_list), 3) if transfers_list else "",
        "std_transfers": round(statistics.pstdev(transfers_list), 3) if len(transfers_list) > 1 else (0 if transfers_list else ""),
        "mean_distance": round(statistics.mean(distance_list), 3) if distance_list else "",
        "std_distance": round(statistics.pstdev(distance_list), 3) if len(distance_list) > 1 else (0 if distance_list else ""),
        "mean_wall_time_s": round(statistics.mean(times), 6),
        "total_wall_time_s": round(sum(times), 6),
        "n_timed_out": n_timed_out,
    }
    return row, wall


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--instances-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "results", "beam_search.csv"))
    ap.add_argument("--beam-size", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=2.0, help="per-restart wall-clock budget, seconds")
    ap.add_argument("--restarts", type=int, default=100)
    ap.add_argument("--workers", type=int, default=os.cpu_count(),
                     help="instances processed in parallel (default: all cores)")
    ap.add_argument("--max-grid-n", type=int, default=None,
                     help="skip instances larger than this grid side length (beam search scales poorly)")
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    paths = sorted(glob.glob(os.path.join(args.instances_dir, "*.json")))
    if args.max_grid_n is not None:
        kept = []
        for path in paths:
            with open(path) as f:
                if json.load(f)["grid"][0] <= args.max_grid_n:
                    kept.append(path)
        paths = kept

    rows = []
    n_done = 0
    t_start = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(process_instance, path, args.beam_size, args.timeout, args.restarts): path
            for path in paths
        }
        for fut in as_completed(futures):
            row, wall = fut.result()
            rows.append(row)
            n_done += 1
            elapsed = time.time() - t_start
            print(f"[{n_done}/{len(paths)}, {elapsed:.0f}s elapsed] {row['instance']}: "
                  f"success_rate={row['success_rate']:.2f} ({row['n_success']}/{args.restarts}) "
                  f"mean_transfers={row['mean_transfers']} mean_distance={row['mean_distance']} "
                  f"instance_time={wall:.2f}s timed_out={row['n_timed_out']}", flush=True)

    if not rows:
        print("no instances matched filters; nothing written")
        return

    rows.sort(key=lambda r: r["instance"])
    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
