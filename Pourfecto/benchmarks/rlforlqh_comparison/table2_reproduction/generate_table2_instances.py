#!/usr/bin/env python3
"""Generate instances reproducing the exact six configurations in Table 2 of Ferdosi, Ge & Kingsford,
"Reinforcement Learning for Robotic Liquid Handler Planning" (WABI 2023), using the paper's own
instance-generation procedure -- not the simplified single-reagent-per-cell generator used by the
broader ../generate_instances.py sweep.

`_populate_grid` and `_populate_goal_with_full_reward` below are a direct, faithful port of the
same-named functions in ../../../../rlforlqh/Greedy-Heuristic/data_generator.py (confirmed against
that file's actual __main__ usage, which is what generated the paper's own data):

  1. The GOAL state is built by `_populate_grid`: each unit of each reagent type is scattered
     independently at a uniformly random (row, col). A cell can end up holding more than one
     reagent type purely by chance -- unlike ../generate_instances.py, mixing is not forbidden here.
  2. The INIT state is built by `_populate_goal_with_full_reward`, which *decomposes* the goal state:
     for each goal cell, it repeatedly peels off a random nonzero sub-vector of that cell's remaining
     goal content and places it at a fresh (row, col) elsewhere that (a) is not already used in the
     init state being built, (b) does not already need that same reagent in ITS OWN goal (so the
     placement can never accidentally already satisfy part of the goal), and, since the original
     code's __main__ always calls this with separate_plates=True, (c) has no goal requirement of any
     kind. This guarantees a valid decomposition path exists back to the goal (replay the same moves
     in reverse), and -- like the goal state -- can produce multi-reagent init cells.

Table 2's six configurations (grid_size, reagent unit counts per type):
    4x4   [4,4]
    6x6   [3,3]
    6x6   [8,8]
    8x8   [4,4]
    8x8   [15,15]
    10x10 [5,5,5,5]

Output: one JSON file per instance under instances/<config>/, plus an index.csv.
"""
import argparse
import csv
import json
import os

import numpy as np

# (label, grid_size, blocks) -- exactly Table 2's six rows.
TABLE2_CONFIGS = [
    ("4x4_4-4", 4, [4, 4]),
    ("6x6_3-3", 6, [3, 3]),
    ("6x6_8-8", 6, [8, 8]),
    ("8x8_4-4", 8, [4, 4]),
    ("8x8_15-15", 8, [15, 15]),
    ("10x10_5-5-5-5", 10, [5, 5, 5, 5]),
]


def populate_grid(n, blocks, rng):
    """Port of data_generator.py's _populate_grid: scatter each unit of each type independently at
    a uniformly random (row, col). Returns an (n, n, k) array -- this is the GOAL state."""
    k = len(blocks)
    grid = np.zeros((n, n, k), dtype=int)
    for block_id, num_blocks in enumerate(blocks):
        for _ in range(num_blocks):
            r, c = rng.integers(0, n, size=2)
            grid[r, c, block_id] += 1
    return grid


def populate_goal_with_full_reward(n, k, goals, rng, separate_plates=True):
    """Port of data_generator.py's _populate_goal_with_full_reward: decompose `goals` (the GOAL
    state) into a new (n, n, k) array -- the INIT state -- by repeatedly moving a random nonzero
    sub-vector of each goal cell's content to a fresh, currently-empty, non-goal-conflicting cell.
    `separate_plates=True` matches the original script's actual __main__ call (the only one of its
    three generation modes that isn't disabled there)."""
    grid = np.zeros((n, n, k), dtype=int)
    for i in range(n):
        for j in range(n):
            blocks_to_fill = goals[i, j].copy()
            while blocks_to_fill.sum() > 0:
                blocks = rng.integers(0, blocks_to_fill + 1)
                while blocks.sum() == 0:
                    blocks = rng.integers(0, blocks_to_fill + 1)
                r, c = rng.integers(0, n, size=2)
                while (np.minimum(blocks, goals[r, c]).sum() > 0
                       or grid[r, c].sum() != 0
                       or (separate_plates and goals[r, c].sum() != 0)):
                    r, c = rng.integers(0, n, size=2)
                grid[r, c] += blocks
                blocks_to_fill -= blocks
    return grid


def array_to_cells(arr):
    cells = []
    n0, n1, k = arr.shape
    for r in range(n0):
        for c in range(n1):
            for t in range(k):
                amt = int(arr[r, c, t])
                if amt > 0:
                    cells.append({"row": r, "col": c, "type": t, "amount": amt})
    return cells


def make_instance(n, blocks, rng):
    goal = populate_grid(n, blocks, rng)
    init = populate_goal_with_full_reward(n, len(blocks), goal, rng, separate_plates=True)
    return {
        "grid": [n, n],
        "n_types": len(blocks),
        "init": array_to_cells(init),
        "goal": array_to_cells(goal),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--n-instances", type=int, default=1000,
                     help="instances per config (paper: 1000 for RL/GH)")
    ap.add_argument("--n-beam-search", type=int, default=100,
                     help="of --n-instances, how many (the first N) are also used for beam search "
                          "(paper: 100, since BS is far slower)")
    ap.add_argument("--out-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    ap.add_argument("--seed", type=int, default=0, help="matches data_generator.py's np.random.seed(0)")
    args = ap.parse_args()

    index_rows = []
    for label, n, blocks in TABLE2_CONFIGS:
        rng = np.random.default_rng(args.seed)
        config_dir = os.path.join(args.out_dir, label)
        os.makedirs(config_dir, exist_ok=True)

        for i in range(args.n_instances):
            instance = make_instance(n, blocks, rng)
            # sanity check: conservation holds by construction (init is a decomposition of goal)
            init_total = sum(c["amount"] for c in instance["init"])
            goal_total = sum(c["amount"] for c in instance["goal"])
            assert init_total == goal_total == sum(blocks), (label, i, init_total, goal_total)

            name = f"{label}_inst{i:04d}"
            path = os.path.join(config_dir, f"{name}.json")
            with open(path, "w") as f:
                json.dump(instance, f)

            index_rows.append({
                "config": label, "grid_n": n, "n_types": len(blocks),
                "blocks": ",".join(map(str, blocks)), "index": i, "name": name,
                "use_for_beam_search": i < args.n_beam_search,
                "path": os.path.relpath(path, args.out_dir),
            })
        print(f"wrote {args.n_instances} instances for {label} -> {config_dir}")

    index_path = os.path.join(args.out_dir, "index.csv")
    with open(index_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(index_rows[0].keys()))
        writer.writeheader()
        writer.writerows(index_rows)
    print(f"wrote {index_path} ({len(index_rows)} instances total)")


if __name__ == "__main__":
    main()
