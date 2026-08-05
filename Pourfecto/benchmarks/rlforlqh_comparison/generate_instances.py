#!/usr/bin/env python3
"""Generate paired liquid-handler rearrangement instances for the rlforlqh/Pourfecto benchmark.

Each instance is a closed-system transportation problem on an NxN grid: every reagent type's
total quantity is conserved between the init grid and the goal grid, only its distribution across
cells changes. This is the problem rlforlqh's Beam Search and Greedy-Heuristic solvers operate on
(see ../../../rlforlqh/Greedy-Heuristic/data_generator.py for the reference generator this mirrors),
and it is also exactly what Pourfecto solves when source/target labware are two states of the same
grid with one reagent per well and a single_channel instrument config.

Each occupied cell holds exactly one reagent type (never a mix of two). This isn't a simplification
for rlforlqh's benefit -- it's required for the instance to be solvable at all under physically
realistic mixing: a real (or Pourfecto-modeled) pipette can't selectively extract one reagent back
out of an already-mixed well, so a source cell holding, say, an inseparable 1:1 mix of two types can
strand liquid no target can use in its pure form, making the whole instance infeasible by
construction -- confirmed by hand against one such generated instance, where Pourfecto's planner,
rlforlqh's greedy heuristic, and its beam search all independently reported failure. Restricting
scatter() to one type per cell guarantees a feasible rearrangement exists (match same-type cells
directly), so a solver failing on a generated instance always reflects a heuristic's limitation, not
an unsolvable instance.

Output: one JSON file per instance under instances/, plus an index.csv listing them.
"""
import argparse
import csv
import json
import os
import random


def make_instance(n, k, n_units, rng):
    """Scatter n_units unit-quantities of each of k reagent types onto an nxn grid twice
    (once for init, once for goal), independently, so the total per type is conserved but
    the distribution differs. A cell already holding type t' != t is skipped when placing type t,
    so no cell ever mixes two reagent types (see module docstring for why that matters)."""

    def scatter():
        cell_type = {}  # (r, c) -> the one type occupying it, if any
        counts = {}
        for t in range(k):
            placed = 0
            attempts = 0
            max_attempts = n_units * n * n  # generous; only matters if the grid is nearly full
            while placed < n_units and attempts < max_attempts:
                attempts += 1
                r, c = rng.randrange(n), rng.randrange(n)
                if cell_type.get((r, c), t) != t:
                    continue  # occupied by a different type; skip to keep cells single-type
                cell_type[(r, c)] = t
                counts[(r, c, t)] = counts.get((r, c, t), 0) + 1
                placed += 1
            if placed < n_units:
                raise RuntimeError(
                    f"grid too full to place {n_units} unmixed units of type {t} "
                    f"(n={n}, k={k}); reduce --units-per-type or increase grid size"
                )
        return [{"row": r, "col": c, "type": t, "amount": amt} for (r, c, t), amt in counts.items()]

    init = scatter()
    goal = scatter()

    # Enforce conservation exactly: rescale goal counts per type to match init's total (scatter()
    # already uses the same n_units per type, so totals already match by construction; this is a
    # belt-and-suspenders check, not a correction step).
    init_totals = {}
    goal_totals = {}
    for cell in init:
        init_totals[cell["type"]] = init_totals.get(cell["type"], 0) + cell["amount"]
    for cell in goal:
        goal_totals[cell["type"]] = goal_totals.get(cell["type"], 0) + cell["amount"]
    assert init_totals == goal_totals, (init_totals, goal_totals)

    return {"grid": [n, n], "n_types": k, "init": init, "goal": goal}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sizes", type=int, nargs="+", default=[5, 8, 10, 15, 20],
                     help="grid side lengths to sweep (NxN)")
    ap.add_argument("--n-types", type=int, nargs="+", default=[1, 2, 4],
                     help="reagent-type counts to sweep")
    ap.add_argument("--units-per-type", type=int, default=None,
                     help="unit-quantities scattered per reagent type; defaults to n//2")
    ap.add_argument("--seeds", type=int, nargs="+", default=[0, 1, 2],
                     help="random seeds per (size, n_types) cell")
    ap.add_argument("--out-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    index_rows = []

    for n in args.sizes:
        units = args.units_per_type if args.units_per_type is not None else max(2, n // 2)
        for k in args.n_types:
            for seed in args.seeds:
                rng = random.Random((n, k, seed))
                instance = make_instance(n, k, units, rng)
                name = f"n{n}_k{k}_seed{seed}"
                path = os.path.join(args.out_dir, f"{name}.json")
                with open(path, "w") as f:
                    json.dump(instance, f, indent=2)
                index_rows.append({
                    "name": name, "grid_n": n, "n_types": k, "seed": seed,
                    "units_per_type": units, "path": os.path.relpath(path, args.out_dir),
                })
                print(f"wrote {path}")

    index_path = os.path.join(args.out_dir, "index.csv")
    with open(index_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(index_rows[0].keys()))
        writer.writeheader()
        writer.writerows(index_rows)
    print(f"wrote {index_path} ({len(index_rows)} instances)")


if __name__ == "__main__":
    main()
