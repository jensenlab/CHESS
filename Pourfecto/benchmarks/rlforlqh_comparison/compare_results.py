#!/usr/bin/env python3
"""Join results/{greedy,beam_search,pourfecto}.csv into one comparison table.

greedy.csv and beam_search.csv hold restart-aggregated stats (success_rate over --restarts seeded
runs per instance, plus mean/std transfers and distance among the successful restarts -- see
run_greedy.py / run_beam_search.py). pourfecto.csv holds a single deterministic outcome per instance
(Pourfecto has nothing to restart), normalized here to the same success_rate/mean_*/std_* shape
(std_* always 0 -- there is no variance to report).

Prints a per-instance table and a per-(grid_n, n_types) summary (mean success rate, mean
transfers/distance/time among instances with a solution). See the benchmark README for the
fairness caveats: Pourfecto is an exact solver, the heuristics are not; Pourfecto's transfer count
is informational only in planning mode, not something it minimizes (see run_pourfecto.jl).
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


def normalize_row(solver, r):
    """Map a raw per-instance row from either schema (restart-aggregated for greedy/beam_search,
    single-shot for pourfecto) onto one common shape: success_rate, mean/std transfers, mean/std
    distance, mean_time_s."""
    if solver == "pourfecto":
        success = to_bool(r["success"])
        return {
            "success_rate": 1.0 if success else 0.0,
            "mean_transfers": to_num(r.get("n_transfers", "")) if success else None,
            "std_transfers": 0.0 if success else None,
            "mean_distance": to_num(r.get("distance", "")) if success else None,
            "std_distance": 0.0 if success else None,
            "mean_time_s": to_num(r.get("wall_time_s", "")),
        }
    return {
        "success_rate": to_num(r.get("success_rate", "")) or 0.0,
        "mean_transfers": to_num(r.get("mean_transfers", "")),
        "std_transfers": to_num(r.get("std_transfers", "")),
        "mean_distance": to_num(r.get("mean_distance", "")),
        "std_distance": to_num(r.get("std_distance", "")),
        "mean_time_s": to_num(r.get("mean_wall_time_s", "")),
    }


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

    metrics = ["success_rate", "mean_transfers", "std_transfers", "mean_distance", "std_distance", "mean_time_s"]
    header = ["instance", "grid_n", "n_types"]
    for s in solvers:
        header += [f"{s}_{m}" for m in metrics]

    out_rows = []
    for name in instances:
        entry = by_instance[name]
        any_row = next(iter(entry.values()))
        row = {"instance": name, "grid_n": any_row["grid_n"], "n_types": any_row["n_types"]}
        for s in solvers:
            r = entry.get(s)
            normalized = normalize_row(s, r) if r is not None else {m: "" for m in metrics}
            for m in metrics:
                v = normalized.get(m, "")
                row[f"{s}_{m}"] = "" if v is None else v
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
    print("\nSummary by (grid_n, n_types): mean success rate, mean transfers/distance/time_s where solved\n")
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
            rates = [to_num(r[f"{s}_success_rate"]) for r in group]
            rates = [v for v in rates if v is not None]
            row[f"{s}_success_rate"] = f"{sum(rates)/len(rates):.3f}" if rates else ""
            for metric, key_name in [("mean_transfers", "mean_transfers"), ("mean_distance", "mean_distance"), ("mean_time_s", "mean_time_s")]:
                vals = [to_num(r[f"{s}_{metric}"]) for r in group]
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
