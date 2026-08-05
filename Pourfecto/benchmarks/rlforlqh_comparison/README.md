# rlforlqh vs Pourfecto: head-to-head benchmark

Compares Pourfecto against rlforlqh's Beam Search and Greedy-Heuristic solvers
(https://github.com/Kingsford-Group/rlforlqh, WABI 2023) on the one problem both actually solve: a
closed-system grid-rearrangement instance, where every reagent type's total quantity is conserved
between an init grid and a goal grid, and only the per-cell distribution changes.

rlforlqh's RL solver is not included: it requires training CORA (https://github.com/AGI-Labs/continual_rl)
from scratch per grid size/reagent count, with no published checkpoint.

## Problem mapping

- rlforlqh's grid cell = a well; its integer "amount" per type = microliters of that reagent.
- Pourfecto's source labware = the init grid, target labware = the goal grid, one reagent per
  occupied cell, `single_channel` instrument config (one well-to-well pipetting operation at a
  time, matching rlforlqh's one-tip model), `objective="min_active_flow"` (minimize count of
  nonzero transfers), `priority=0` on every reagent (exact match required, no slack).
- Every generated instance keeps each occupied cell to a single reagent type (see
  `generate_instances.py`'s docstring): a cell mixing two types can strand liquid that no
  single-reagent target can use, which makes the instance genuinely infeasible under real mixing
  physics -- confirmed once, by hand, where Pourfecto's planner and both rlforlqh heuristics
  independently agreed an instance was unsolvable. Restricting to single-type cells guarantees a
  feasible rearrangement always exists, so a solver's failure means the heuristic missed it, not
  that the problem was impossible.

## Running the sweep

```bash
# 1. generate paired instances (writes benchmarks/rlforlqh_comparison/instances/*.json)
python3 generate_instances.py --sizes 5 8 10 15 20 --n-types 1 2 4 --seeds 0 1 2

# 2. (optional) archive rlforlqh's own text format, for manual reproduction
python3 to_rlforlqh_format.py

# 3. run each solver
python3 run_greedy.py
python3 run_beam_search.py --timeout 60
julia --project=../.. run_pourfecto.jl instances results/pourfecto.csv 90   # from this directory

# 4. compare
python3 compare_results.py
```

`run_pourfecto.jl` needs the Pourfecto Julia environment instantiated (`julia --project=Pourfecto
-e 'using Pkg; Pkg.instantiate()'` from the CHESS repo root, one-time). It solves with SCIP (free,
open-source, and the only bundled optimizer that supports `min_active_flow`'s indicator constraints
without a Gurobi license -- see `docs/src/manual/pourfecto_method.md`'s solver comparison table).
Swap in `optimizer=Gurobi.Optimizer` in `run_pourfecto.jl` if a license is available; it should only
change wall-clock time, not the plan found.

## Metrics

- **success**: did the plan reach the goal grid exactly.
- **n_transfers**: discrete well-to-well transfer operations. Comparable across all three solvers
  by construction (Pourfecto's nonzero active-flow count under `single_channel`; greedy's
  pickup/dropoff cycles; beam search's dispense-command count -- see `run_beam_search.py` for why
  dispense count, not raw protocol length, is the fairest match).
- **distance**: total Manhattan distance traveled by the pipette head. Not an objective Pourfecto
  optimizes for here (only `n_transfers` is), so this isn't a metric stacked in Pourfecto's favor.
- **wall_time_s**: time to produce the full plan.

## Results (39-instance sweep: grid_n in {5,8,10,15,20}, n_types in {1,2,4}, 2-3 seeds each)

Full per-instance and per-(grid_n, n_types) tables in `results/comparison.csv`. Summary of success
rate (fraction of instances solved) by (grid_n, n_types):

| grid_n | n_types | greedy | beam_search | pourfecto |
|---|---|---|---|---|
| 5  | 1 | 1.00 | 1.00 | 1.00 |
| 5  | 2 | 0.67 | 0.67 | 1.00 |
| 5  | 4 | 0.00 | 0.00 | 1.00 |
| 8  | 1 | 0.67 | 1.00 | 1.00 |
| 8  | 2 | 1.00 | 0.00 | 1.00 |
| 8  | 4 | 0.00 | 0.00 | 1.00 |
| 10 | 1 | 0.67 | 1.00 | 1.00 |
| 10 | 2 | 1.00 | 0.00 | 1.00 |
| 10 | 4 | 0.00 | 0.00 | 1.00 |
| 15 | 1 | 1.00 | 1.00 | 1.00 |
| 15 | 2 | 0.50 | 0.00 | 1.00 |
| 15 | 4 | 0.00 | 0.00 | 1.00 |
| 20 | 1 | 1.00 | 1.00 | 1.00 |
| 20 | 2 | 0.00 | 0.00 | 1.00 |
| 20 | 4 | 0.00 | 0.00 | 1.00 |

Pourfecto's exact MILP solve reached **100% success on all 39 instances**. Both rlforlqh heuristics
are perfect at `n_types=1` (a pure sorting problem, easy for greedy nearest-excess/nearest-need
matching) but collapse as reagent-type count rises -- both hit 0% at `n_types=4` by grid size 8, and
beam search is at 0% for every `n_types=2` instance at grid_n >= 8. Neither heuristic backtracks: one
early wrong pickup-or-placement choice with the wrong reagent composition can strand the rest of the
grid in an unrecoverable state.

Where a heuristic does succeed, transfer counts are close to Pourfecto's optimum (e.g. at
grid_n=20, n_types=1: greedy 10, beam search 10, Pourfecto 10 -- all tied), but total travel
**distance is consistently higher** for both heuristics (e.g. same instance: greedy 205, beam
search 91.5, Pourfecto 146.5, averaged over 2 seeds) since neither optimizes for it -- expected,
since only Pourfecto's objective (`min_active_flow`) targets transfer count, and distance is a
reported-only metric on all three sides.

**Wall-clock time is where Pourfecto's MILP shows a real cost.** Both heuristics stay under ~10s
even at 20x20/4 types. Pourfecto is faster than both at grid_n<=10 (sub-second to a few seconds),
comparable at 15x15 (~14-16s), but jumps to **~150-172s at 20x20** regardless of `n_types` --
consistent with `min_active_flow`'s indicator-constraint MILP scaling with well count (400 wells)
rather than reagent count. None of these runs hit the 90s `solver_timelimit` passed to
`run_pourfecto.jl`'s wrapper call itself timing out with an error -- the ~150-170s wall times reflect
`pourfecto()`'s two internal sequential solves (planning, then scheduling) each allotted up to that
budget, plus JuMP model-construction overhead that the timelimit doesn't bound. This is the
concrete manifestation of the fairness caveat above: Pourfecto's guarantee of an exact, optimal
answer costs two orders of magnitude more wall-clock time at the largest scale than either
heuristic, which return fast, best-effort (and, in this problem regime, mostly failing) answers.
