#!/usr/bin/env python3
"""Convert a canonical instance JSON into rlforlqh's native text format.

rlforlqh's Greedy-Heuristic/greedy.py and Beam Search/beam_search.ipynb (via its `set_tasks`
function) both consume the same text format, one unit-quantity per line:

    STARTING STATE <i>
    <row> <col> <type>       # repeated once per unit of amount at that cell
    ...
    END
    GOAL STATE <i>
    <row> <col> <type>
    ...
    END

(confirmed against rlforlqh's own Greedy-Heuristic/data_generator.py output and
Beam Search/tests_5x5.txt). Integer `amount` fields in the canonical JSON are expanded into that
many repeated lines, since the native format has no amount field.

This converter exists for archival/manual-reproduction purposes -- run_greedy.py and
run_beam_search.py read the canonical JSON directly and do not round-trip through this format.
"""
import argparse
import glob
import json
import os


def instance_to_lines(instance, index=0):
    lines = [f"STARTING STATE {index}"]
    for cell in instance["init"]:
        lines.extend([f"{cell['row']} {cell['col']} {cell['type']}"] * cell["amount"])
    lines.append("END")
    lines.append(f"GOAL STATE {index}")
    for cell in instance["goal"]:
        lines.extend([f"{cell['row']} {cell['col']} {cell['type']}"] * cell["amount"])
    lines.append("END")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--instances-dir", default=os.path.join(os.path.dirname(__file__), "instances"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "instances", "all_instances.rlforlqh.txt"))
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.instances_dir, "*.json")))
    with open(args.out, "w") as f:
        for i, path in enumerate(paths):
            with open(path) as jf:
                instance = json.load(jf)
            f.write("\n".join(instance_to_lines(instance, i)) + "\n")
    print(f"wrote {args.out} ({len(paths)} instances)")


if __name__ == "__main__":
    main()
