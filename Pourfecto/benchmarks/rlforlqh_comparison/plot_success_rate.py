#!/usr/bin/env python3
"""Plot success rate vs. grid size, split by reagent count, for Pourfecto vs. rlforlqh.

Reads results/comparison.csv (written by compare_results.py). greedy_success_rate and
beam_search_success_rate are each already a per-instance rate over --restarts randomized seeds (see
run_greedy.py / run_beam_search.py); pourfecto_success_rate is the degenerate 0/1 case (an exact
solver has nothing to restart). The "Ferdosi et al." series (the rlforlqh paper's authors) takes,
per (grid_n, n_types) cell, the better of greedy_success_rate and beam_search_success_rate per
instance, then averages over instances in the cell -- a ceiling on what rlforlqh's two runnable
solvers achieve on these instances (its RL solver is excluded from the whole benchmark; see
README.md).

Output: results/success_rate.png
"""
import argparse
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def to_num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--comparison-csv", default=os.path.join(os.path.dirname(__file__), "results", "comparison.csv"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "results", "success_rate.png"))
    args = ap.parse_args()

    with open(args.comparison_csv) as f:
        rows = list(csv.DictReader(f))

    # groups[n_types][grid_n] -> list of rows
    groups = defaultdict(lambda: defaultdict(list))
    for r in rows:
        groups[int(r["n_types"])][int(r["grid_n"])].append(r)

    n_types_values = sorted(groups.keys())
    grid_sizes = sorted({int(r["grid_n"]) for r in rows})

    def success_rate(cell_rows, rate_key):
        vals = [to_num(r[rate_key]) for r in cell_rows]
        vals = [v for v in vals if v is not None]
        return sum(vals) / len(vals) if vals else None

    def ferdosi_rate(cell_rows):
        # per-instance best-of, then average over instances in the cell (matches how the
        # per-cell success rate is otherwise computed).
        vals = []
        for r in cell_rows:
            g = to_num(r["greedy_success_rate"]) or 0.0
            b = to_num(r["beam_search_success_rate"]) or 0.0
            vals.append(max(g, b))
        return sum(vals) / len(vals) if vals else None

    fig, ax = plt.subplots(figsize=(7, 5))

    blues = matplotlib.colormaps["Blues"]
    reds = matplotlib.colormaps["Reds"]
    # sample colormaps away from the near-white low end so the lightest line stays visible
    shades = [0.45 + 0.45 * i / max(1, len(n_types_values) - 1) for i in range(len(n_types_values))]

    for shade, k in zip(shades, n_types_values):
        by_size = groups[k]
        xs = [n for n in grid_sizes if n in by_size]

        pourfecto_ys = [success_rate(by_size[n], "pourfecto_success_rate") for n in xs]
        ferdosi_ys = [ferdosi_rate(by_size[n]) for n in xs]

        ax.plot(xs, pourfecto_ys, marker="o", color=blues(shade), label=f"Pourfecto (k={k})")
        ax.plot(xs, ferdosi_ys, marker="s", color=reds(shade), label=f"Ferdosi et al. (k={k})")

    ax.set_xlabel("Grid size (N x N)")
    ax.set_ylabel("Success rate")
    ax.set_ylim(-0.05, 1.05)
    ax.set_xticks(grid_sizes)
    ax.set_title("Success rate vs. grid size, by reagent count")
    ax.legend(loc="center left", bbox_to_anchor=(1.02, 0.5), fontsize=9)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    fig.savefig(args.out, dpi=150, bbox_inches="tight")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
