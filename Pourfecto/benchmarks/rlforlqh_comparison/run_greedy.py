#!/usr/bin/env python3
"""Run rlforlqh's greedy-heuristic algorithm against canonical benchmark instances, with N
randomized restarts per instance to measure the heuristic's run-to-run variance.

The core loop below is a direct, parameterized port of the `greedy()` function in
../../../rlforlqh/Greedy-Heuristic/greedy.py: repeatedly pick up (aspirate) the full contents of
the nearest cell that has an excess of some reagent type relative to its goal, then carry it to the
nearest still-needy cell and drop off (dispense) as much as fits, until the grid matches the goal or
the iteration budget runs out. Ported rather than subprocessed because the original script hardcodes
grid size (`n`), reagent-type count (`k`), and an input filename as module-level globals, so it isn't
directly callable as a function across a size/seed sweep.

Differences from the original:
  - Reads instances from canonical JSON instead of the "STARTING STATE/GOAL STATE/END" text format
    (see to_rlforlqh_format.py for that format, still produced for archival purposes).
  - The iteration cap scales with instance size (3x total unit count) instead of being hardcoded to
    100 (a constant tuned for the original paper's fixed 10x10/4-type scale); the algorithm itself is
    unchanged.
  - When no candidate cell is found (`x, y` stay `-1, -1`), this port treats it as a stall and stops.
    The original leaves `x, y = -1, -1` and indexes `grid[-1][-1]`/`goal[-1][-1]` (Python's
    wrap-to-last-element semantics), silently operating on the wrong cell instead of failing loudly.
    That's a latent bug in the original, not a deliberate behavior worth reproducing.
  - RANDOMIZED RESTARTS (added by this benchmark, not part of the original): the original always
    keeps the *first* cell found at the minimum candidate distance (`if ... < mn_dis: x, y = i, j`),
    making the whole algorithm deterministic -- its only randomization
    (`ratio_code = np.random.randint(0, 1)`) is dead code that always evaluates to 0. To get a sense
    of the heuristic's variance rather than repeating one deterministic run N times, both candidate
    searches below collect *all* cells tied at the minimum distance and pick uniformly at random
    among them, using a `random.Random(seed)` passed into `greedy(...)`. Each instance is run with
    `--restarts` different seeds (default 100); per-instance results are aggregated into a success
    rate plus mean/std transfer-count and distance among the successful restarts.

One "transfer" = one pick-up-then-drop-off cycle, directly comparable to one nonzero entry of
Pourfecto's source->target transfer matrix (see run_pourfecto.jl).
"""
import argparse
import csv
import glob
import json
import os
import random
import statistics
import time

import numpy as np


def greedy(grid, goal, k, max_iters, rng):
    """grid, goal: (n, n, k) float arrays. Mutates grid in place. Returns (done, n_transfers, distance).

    rng: random.Random instance used to break ties uniformly at random among equally-close
    candidate cells (see module docstring, "RANDOMIZED RESTARTS")."""
    n = grid.shape[0]
    head = np.zeros((k,))
    done = False
    prev_x, prev_y = 0, 0
    distance = 0
    n_transfers = 0

    for _ in range(max_iters):
        if head.sum() == 0:
            mn_dis = 2 * n
            candidates = []
            for i in range(n):
                for j in range(n):
                    if grid[i][j].sum() > 0 and np.any(grid[i][j] > goal[i][j]):
                        d = abs(prev_x - i) + abs(prev_y - j)
                        if d < mn_dis:
                            mn_dis = d
                            candidates = [(i, j)]
                        elif d == mn_dis:
                            candidates.append((i, j))
            if not candidates:
                break  # nothing left with excess: unreachable goal under this heuristic
            x, y = rng.choice(candidates)
            head = grid[x][y].copy()
            grid[x][y] -= head
            distance += abs(x - prev_x) + abs(y - prev_y)
            prev_x, prev_y = x, y
        else:
            mn_dis = 2 * n
            candidates = []
            for i in range(n):
                for j in range(n):
                    if goal[i][j].sum() > 0 and np.all(head <= np.maximum(goal[i][j] - grid[i][j], 0)):
                        d = abs(prev_x - i) + abs(prev_y - j)
                        if d < mn_dis:
                            mn_dis = d
                            candidates = [(i, j)]
                        elif d == mn_dis:
                            candidates.append((i, j))
            if not candidates:
                # nowhere left that can take the full head load: original algorithm has no
                # partial-dispense fallback here either (action_ratio branch is dead code, since
                # ratio_code is always 0 from `np.random.randint(0, 1)`), so this is a genuine stall.
                break
            x, y = rng.choice(candidates)
            grid[x][y] += head
            head = np.zeros((k,))
            n_transfers += 1
            distance += abs(x - prev_x) + abs(y - prev_y)
            prev_x, prev_y = x, y
            done = bool(np.all(goal == grid))
            if done:
                break

    return done, n_transfers, distance


def instance_to_arrays(instance):
    n, _ = instance["grid"]
    k = instance["n_types"]
    grid = np.zeros((n, n, k))
    goal = np.zeros((n, n, k))
    for cell in instance["init"]:
        grid[cell["row"], cell["col"], cell["type"]] += cell["amount"]
    for cell in instance["goal"]:
        goal[cell["row"], cell["col"], cell["type"]] += cell["amount"]
    return grid, goal, n, k


def run_restarts(grid0, goal0, k, max_iters, n_restarts, base_seed):
    successes = []
    transfers_list = []
    distance_list = []
    times = []
    for seed in range(n_restarts):
        rng = random.Random((base_seed, seed))
        t0 = time.time()
        done, n_transfers, distance = greedy(grid0.copy(), goal0.copy(), k, max_iters, rng)
        times.append(time.time() - t0)
        successes.append(done)
        if done:
            transfers_list.append(n_transfers)
            distance_list.append(distance)
    return successes, transfers_list, distance_list, times


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--instances-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "results", "greedy.csv"))
    ap.add_argument("--iters-per-unit", type=float, default=3.0)
    ap.add_argument("--restarts", type=int, default=100)
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    paths = sorted(glob.glob(os.path.join(args.instances_dir, "*.json")))

    rows = []
    for path in paths:
        with open(path) as f:
            instance = json.load(f)
        grid, goal, n, k = instance_to_arrays(instance)
        total_units = int(grid.sum())
        max_iters = max(50, int(total_units * args.iters_per_unit))
        name = os.path.splitext(os.path.basename(path))[0]

        successes, transfers_list, distance_list, times = run_restarts(
            grid, goal, k, max_iters, args.restarts, base_seed=name)

        n_success = sum(successes)
        success_rate = n_success / args.restarts
        rows.append({
            "solver": "greedy", "instance": name, "grid_n": n, "n_types": k,
            "total_units": total_units, "restarts": args.restarts,
            "n_success": n_success, "success_rate": round(success_rate, 4),
            "mean_transfers": round(statistics.mean(transfers_list), 3) if transfers_list else "",
            "std_transfers": round(statistics.pstdev(transfers_list), 3) if len(transfers_list) > 1 else (0 if transfers_list else ""),
            "mean_distance": round(statistics.mean(distance_list), 3) if distance_list else "",
            "std_distance": round(statistics.pstdev(distance_list), 3) if len(distance_list) > 1 else (0 if distance_list else ""),
            "mean_wall_time_s": round(statistics.mean(times), 6),
            "total_wall_time_s": round(sum(times), 6),
        })
        print(f"{name}: success_rate={success_rate:.2f} ({n_success}/{args.restarts}) "
              f"mean_transfers={rows[-1]['mean_transfers']} mean_distance={rows[-1]['mean_distance']} "
              f"total_time={rows[-1]['total_wall_time_s']:.3f}s")

    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
