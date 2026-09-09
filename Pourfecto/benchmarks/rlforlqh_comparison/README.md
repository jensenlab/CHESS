# rlforlqh vs Pourfecto: head-to-head benchmark

Compares Pourfecto against rlforlqh's Beam Search and Greedy-Heuristic solvers
(https://github.com/Kingsford-Group/rlforlqh, WABI 2023) on the one problem both actually solve: a
closed-system grid-rearrangement instance, where every reagent type's total quantity is conserved
between an init grid and a goal grid, and only the per-cell distribution changes.

rlforlqh's RL solver is not included: it requires training CORA (https://github.com/AGI-Labs/continual_rl)
from scratch per grid size/reagent count, with no published checkpoint.

## Problem mapping

- rlforlqh's grid cell = a well; its integer "amount" per type = microliters of that reagent.
- Pourfecto runs in **planning-only** mode (`Pourfecto.planner(sources, targets; ...)`, via
  `to_pourfecto_stocks.jl`): one `Stock` per occupied init cell (source) and per occupied goal cell
  (target), `priority=0` on every reagent (exact match required, no slack). No `Labware`/instrument
  config/scheduling is built at all -- an earlier version of this benchmark ran Pourfecto's
  scheduling layer with a `single_channel` instrument config, which models physical
  pipette-head/deck geometry that rlforlqh's greedy/beam-search have no equivalent of (they only
  ever decide which cell to move liquid between next, never reason about a physical instrument).
  Planning-only puts both sides on the same footing: does an exact-match sequence of transfers
  exist, and can you find it.
- Every generated instance keeps each occupied cell to a single reagent type (see
  `generate_instances.py`'s docstring): a cell mixing two types can strand liquid that no
  single-reagent target can use, which makes the instance genuinely infeasible under real mixing
  physics -- confirmed once, by hand, where Pourfecto's planner and both rlforlqh heuristics
  independently agreed an instance was unsolvable. Restricting to single-type cells guarantees a
  feasible rearrangement always exists, so a solver's failure means the heuristic missed it, not
  that the problem was impossible.
- Both `greedy.py` and beam search's tie-breaking are deterministic in the original rlforlqh code
  (the only randomization in `greedy.py`, `np.random.randint(0, 1)`, always evaluates to 0). This
  benchmark adds seeded random tie-breaking to both (see `run_greedy.py`'s and
  `beam_search_lib.py`'s module docstrings) and runs each instance across 100 random seeds, to
  measure each heuristic's run-to-run variance rather than a single deterministic outcome. Pourfecto
  is unaffected: an exact solver has no tie-breaking to randomize, and none was added.

## Running the sweep

```bash
# 1. generate paired instances (writes benchmarks/rlforlqh_comparison/instances/*.json)
python3 generate_instances.py --sizes 4 6 8 10 12 14 16 18 20 --n-types 1 2 4 \
    --seeds 0 1 2 3 4 5 6 7 8 9

# 2. (optional) archive rlforlqh's own text format, for manual reproduction
python3 to_rlforlqh_format.py

# 3. run each solver -- greedy and beam search run 100 randomized restarts per instance
python3 run_greedy.py --restarts 100
python3 run_beam_search.py --restarts 100 --timeout 2       # parallelized across --workers (default: all cores)
julia --project=../.. run_pourfecto.jl instances results/pourfecto.csv 60   # from this directory, deterministic, one pass

# 4. compare
python3 compare_results.py
python3 plot_success_rate.py
```

`run_pourfecto.jl` needs the Pourfecto Julia environment instantiated (`julia --project=Pourfecto
-e 'using Pkg; Pkg.instantiate()'` from the CHESS repo root, one-time). It solves with SCIP (free,
open-source; Pourfecto defaults to Gurobi, which needs a commercial or academic license this
benchmark shouldn't assume is present). Swap in `optimizer=Gurobi.Optimizer` in `run_pourfecto.jl`
if a license is available.

`run_beam_search.py` is the slow part: some (grid size, reagent count) cells fail almost every
restart, and a failing restart can run close to the full `--timeout` before giving up. At 270
instances x 100 restarts, a single process would take on the order of hours; work is split across
instances with a process pool (`ProcessPoolExecutor`, `--workers` default: all cores). The full
270-instance x 100-restart sweep took ~69 minutes on an 8-core machine with `--timeout 2`.

## Metrics

- **success_rate**: fraction of the 100 randomized restarts that reached the goal grid exactly
  (greedy, beam search), or 1.0/0.0 for Pourfecto's single deterministic outcome. On equal footing
  across all three solvers -- this and wall-clock time are the only metrics that are.
- **mean_time_s**: mean wall-clock time per restart (greedy, beam search) or the single solve time
  (Pourfecto).
- **mean_transfers**/**std_transfers**, **mean_distance**/**std_distance**: discrete source-to-target
  transfers, and total Manhattan distance between them, computed over the *successful* restarts only
  (std is 0 for Pourfecto -- nothing to vary). Comparable *as observations* -- greedy's
  pickup/dropoff cycles, beam search's dispense-command count (see `run_beam_search.py`), and
  Pourfecto's nonzero entries in the solved transfer matrix -- but **not comparable as an
  optimization target** on the Pourfecto side in this mode: `Pourfecto.planner` only minimizes
  weighted slack (zero at the optimum whenever an exact match is feasible), not transfer count, so
  the number of active source->target pairs it returns is just whatever the LP/QP solver happened to
  pick among equally valid, zero-slack solutions. In practice this means Pourfecto's
  `mean_transfers` here is often *higher* than the heuristics' (see results below) -- the expected
  cost of dropping the scheduling-layer objective that used to minimize it, not a regression in
  solution quality (the underlying plan is still exact).

## Results (270-instance sweep: grid_n in {4,6,...,20}, n_types in {1,2,4}, 10 seeds each, 100 restarts per instance for greedy/beam search)

Full per-instance and per-(grid_n, n_types) tables in `results/comparison.csv`; success rate plotted
in `results/success_rate.png`. Mean success rate by (grid_n, n_types):

| grid_n | n_types | greedy | beam_search | pourfecto |
|---|---|---|---|---|
| 4  | 1 | 0.900 | 1.000 | 1.000 |
| 4  | 2 | 0.652 | 0.283 | 1.000 |
| 4  | 4 | 0.024 | 0.000 | 1.000 |
| 6  | 1 | 0.900 | 1.000 | 1.000 |
| 6  | 2 | 0.551 | 0.196 | 1.000 |
| 6  | 4 | 0.155 | 0.000 | 1.000 |
| 8  | 1 | 0.900 | 1.000 | 1.000 |
| 8  | 2 | 0.600 | 0.007 | 1.000 |
| 8  | 4 | 0.076 | 0.000 | 1.000 |
| 10 | 1 | 0.900 | 1.000 | 1.000 |
| 10 | 2 | 0.779 | 0.014 | 1.000 |
| 10 | 4 | 0.093 | 0.000 | 1.000 |
| 12 | 1 | 1.000 | 1.000 | 1.000 |
| 12 | 2 | 0.749 | 0.055 | 1.000 |
| 12 | 4 | 0.097 | 0.000 | 1.000 |
| 14 | 1 | 0.900 | 1.000 | 1.000 |
| 14 | 2 | 0.824 | 0.000 | 1.000 |
| 14 | 4 | 0.249 | 0.000 | 1.000 |
| 16 | 1 | 0.900 | 0.133 | 1.000 |
| 16 | 2 | 0.530 | 0.000 | 1.000 |
| 16 | 4 | 0.002 | 0.000 | 1.000 |
| 18 | 1 | 1.000 | 0.000 | 1.000 |
| 18 | 2 | 0.832 | 0.000 | 1.000 |
| 18 | 4 | 0.128 | 0.000 | 1.000 |
| 20 | 1 | 1.000 | 0.000 | 1.000 |
| 20 | 2 | 0.469 | 0.000 | 1.000 |
| 20 | 4 | 0.143 | 0.000 | 1.000 |

Pourfecto's planning-only solve reached **100% success on all 270 instances** (deterministic, no
restarts needed). Averaged over 100 randomized restarts per instance:

- **Greedy** holds up reasonably well at `n_types=1` (0.9-1.0 across every grid size) and degrades
  gradually at `n_types=2` (0.83 down to 0.47, noisily, as grid size grows), but collapses at
  `n_types=4` (0.00-0.25 everywhere) -- consistent with the earlier single-run finding, now with a
  real success-rate estimate instead of one 0/1 sample per instance.
- **Beam search is far more fragile than the earlier deterministic run suggested.** With the
  original code's tie-breaking, a single run happened to succeed at `n_types=1` for every grid size
  tested. Randomizing tie-breaking reveals that was partly luck: success rate at `n_types=1` holds
  at 1.0 only through grid_n=14, then falls off a cliff -- 0.133 at 16x16 and **0.0 at 18x18 and
  20x20**. At `n_types>=2` it is at or near 0.0 for grid_n>=8. Its one-cell-at-a-time transition
  function, without backtracking, is evidently much more sensitive to early tie-breaking choices
  than the original single deterministic trace let on -- exactly the kind of finding restart-based
  evaluation is for.
- Neither heuristic backtracks: an unlucky early pickup/placement choice can strand the rest of the
  grid regardless of how many restarts are tried, which is why success rate plateaus well below 1.0
  rather than approaching it as restarts accumulate.

**Wall-clock time is no longer a meaningful cost for Pourfecto** now that scheduling/MILP is out of
the picture: mean solve time across all 270 instances is a few tens of milliseconds, comparable to
or faster than a single greedy restart and far faster than beam search (which needs a `--timeout`
per restart specifically because some instances are slow to resolve).

**Transfer count/distance no longer favor Pourfecto**, and often run the other way: e.g. at
grid_n=20, n_types=4, greedy's mean transfer count among its successful restarts is 39.0 vs.
Pourfecto's 113.2 -- consistent with the metrics caveat above. This is expected, not a
solution-quality regression: planning mode has no notion of "minimize the number of pipetting
operations," so its LP/QP solve is free to spread a transfer across more source/target pairs than
strictly necessary as long as the target composition matches exactly. Read `mean_transfers`/
`mean_distance` here as "what a valid exact plan looked like," not as a claim about which solver
produces a more efficient protocol -- success rate and wall-clock time are the only metrics
genuinely on equal footing between planning-only Pourfecto and rlforlqh's heuristics.
