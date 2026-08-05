#!/usr/bin/env python3
"""Join results/{greedy,beam_search,pourfecto}.csv into one comparison table.

Prints a per-instance table and a per-(grid_n, n_types) summary (success rate, mean transfers/
distance/time among successes, since failed runs have no plan to measure). See the benchmark
README for the fairness caveats this comparison is subject to (Pourfecto is an exact solver, the
heuristics are not; beam search's "n_transfers" counts dispense ops rather than pickup/dropoff
pairs -- see run_beam_search.py).
"""
import argparse
import csv
import os
from collections import defaultdict


def read_csv(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return list(csv.DictReader(f))


def to_bool(v):
    return str(v).strip().lower() in ("true", "1")


def to_num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--results-dir", default=os.path.join(os.path.dirname(__file__), "results"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "results", "comparison.csv"))
    args = ap.parse_args()

    solvers = ["greedy", "beam_search", "pourfecto"]
    rows_by_solver = {s: read_csv(os.path.join(args.results_dir, f"{s}.csv")) for s in solvers}

    by_instance = defaultdict(dict)
    for solver, rows in rows_by_solver.items():
        for row in rows:
            by_instance[row["instance"]][solver] = row

    instances = sorted(by_instance.keys(), key=lambda name: (
        int(name.split("_")[0][1:]), int(name.split("_")[1][1:]), name,
    ))

    header = ["instance", "grid_n", "n_types"]
    for s in solvers:
        header += [f"{s}_success", f"{s}_transfers", f"{s}_distance", f"{s}_time_s"]
    out_rows = []
    for name in instances:
        entry = by_instance[name]
        any_row = next(iter(entry.values()))
        row = {"instance": name, "grid_n": any_row["grid_n"], "n_types": any_row["n_types"]}
        for s in solvers:
            r = entry.get(s)
            if r is None:
                row[f"{s}_success"] = ""
                row[f"{s}_transfers"] = ""
                row[f"{s}_distance"] = ""
                row[f"{s}_time_s"] = ""
            else:
                row[f"{s}_success"] = to_bool(r["success"])
                row[f"{s}_transfers"] = r.get("n_transfers", "")
                row[f"{s}_distance"] = r.get("distance", "")
                row[f"{s}_time_s"] = r.get("wall_time_s", "")
        out_rows.append(row)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header)
        writer.writeheader()
        writer.writerows(out_rows)
    print(f"wrote {args.out}\n")

    # per-instance table
    col_widths = {h: max(len(h), *(len(str(r[h])) for r in out_rows)) for h in header}
    print(" | ".join(h.ljust(col_widths[h]) for h in header))
    print("-+-".join("-" * col_widths[h] for h in header))
    for r in out_rows:
        print(" | ".join(str(r[h]).ljust(col_widths[h]) for h in header))

    # per-(grid_n, n_types) summary
    print("\nSummary by (grid_n, n_types): success rate, mean transfers/distance/time_s among successes\n")
    groups = defaultdict(list)
    for r in out_rows:
        groups[(int(r["grid_n"]), int(r["n_types"]))].append(r)

    summary_header = ["grid_n", "n_types", "n_instances"]
    for s in solvers:
        summary_header += [f"{s}_success_rate", f"{s}_mean_transfers", f"{s}_mean_distance", f"{s}_mean_time_s"]

    summary_rows = []
    for key in sorted(groups.keys()):
        grid_n, n_types = key
        group = groups[key]
        row = {"grid_n": grid_n, "n_types": n_types, "n_instances": len(group)}
        for s in solvers:
            successes = [r for r in group if r[f"{s}_success"] is True]
            n_with_data = sum(1 for r in group if r[f"{s}_success"] != "")
            rate = len(successes) / n_with_data if n_with_data else None
            row[f"{s}_success_rate"] = f"{rate:.2f}" if rate is not None else ""
            for metric, key_name in [("transfers", "mean_transfers"), ("distance", "mean_distance"), ("time_s", "mean_time_s")]:
                vals = [to_num(r[f"{s}_{metric}"]) for r in successes]
                vals = [v for v in vals if v is not None]
                row[f"{s}_{key_name}"] = f"{sum(vals)/len(vals):.2f}" if vals else ""
        summary_rows.append(row)

    col_widths = {h: max(len(h), *(len(str(r[h])) for r in summary_rows)) for h in summary_header}
    print(" | ".join(h.ljust(col_widths[h]) for h in summary_header))
    print("-+-".join("-" * col_widths[h] for h in summary_header))
    for r in summary_rows:
        print(" | ".join(str(r[h]).ljust(col_widths[h]) for h in summary_header))


if __name__ == "__main__":
    main()
