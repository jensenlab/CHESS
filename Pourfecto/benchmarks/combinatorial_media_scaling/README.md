# Combinatorial media at scale: a Tempest-only, 384-well scaling sweep

Reworks `Pourfecto/examples/combinatorial_media/combinatorial_media.jl` (5 x 96-well plates,
~480 wells) into a scaling benchmark that pushes toward ~200,000 individual transfers in a single
`pourfecto()` call, and measures three things: planner accuracy, wall-clock solve time, and the
number of individual transfers scheduled.

## Problem

- 20 reagents, each held in its own 1 L bottle (`:Bottle1L`) on the deck, plus one 1 L bottle of
  water.
- Target labware: 384-well plates (`:WP384`). Every well holds 80 uL total: a unique continuous
  dose (0.1-1.0 uL) of every one of the 20 reagents, topped up with water. Unlike the original
  example's random 50%-inclusion subset, every reagent is present in every well here, so scaling
  the plate count scales the transfer count directly and predictably.
- Sweep: `n_plates` in `[1, 2, 5, 10, 20, 30]`. At 30 plates: 11,520 wells x 21 sources (20
  reagents + water) = 241,920 possible transfers, comfortably past the ~200,000 target -- and,
  since every well needs every source, essentially all of them end up scheduled (see Results).

## Why Tempest only

Tempest is the only instrument configuration that can both aspirate from a large bottle and
dispense into a 384-well plate:

- Its aspirate-eligible source kinds are `:Conical15`, `:Conical50`, `:Bottle1L`, `:Bottle250mL`,
  `:Bottle500mL`, `:FilterBottle1L`.
- Its dispense-eligible target kinds are `:WP96`/`:WP384` only.

No other bundled config (`single_channel`, `cobra`, `nimbus`, `eight_channel_vertical`,
`eight_channel_horizontal`, `plate_master`) accepts a bottle as a source, so this problem is
scheduled with `configs = ["tempest"]`, unlike the original example's 7-config list.

## Why `min_cost_flow` + Gurobi

Every non-default Pourfecto *scheduling* objective (`min_active_flow`, `min_config`,
`min_sources`, `min_labware`, `min_aspirations`) turns the scheduling phase into a MILP via
indicator constraints. `Pourfecto/benchmarks/rlforlqh_comparison/README.md` already shows
`min_active_flow` costing 150-172s at just 400 wells. At 11,520 wells that scaling would make the
MILP objectives intractable, so this benchmark uses the default `"min_cost_flow"` scheduling
objective throughout.

That's not the whole story, though: **the planning phase is a QP regardless of the `objective`
keyword.** `build_planning_model`/`solve_planning_model` always minimize a sum-of-squared-slacks
objective to find the closest feasible plan, one priority level at a time -- `objective` only
governs the later scheduling phase. In testing, HiGHS's active-set QP solver scaled badly on this:
at just 1 plate (384 wells, ~8,000 decision variables) it hadn't reached optimality after hitting
its 60s-per-solve time limit twice, for 255s of wall time and a slightly sub-optimal plan (8,059 of
8,064 possible transfers active). Gurobi's barrier QP solver solved the identical problem to full
optimality in ~9s, and scaled sub-linearly in further testing (5x the plates cost only ~1.8x the
time). This benchmark therefore defaults to `Gurobi.Optimizer` (available here under an academic
license). If you don't have a Gurobi license, `HiGHS.Optimizer` is a drop-in substitute in
`run_benchmark.jl`, but expect it to be much slower and possibly time-limited even at small plate
counts.

Reagents keep the default priority (0, exact match required), since planner accuracy on reagent
dosing is the point of this benchmark. Water is deprioritized
(`PriorityDict("water" => typemax(UInt64))`), exactly as in the original example, so the LP isn't
forced to trade off reagent accuracy for exact water volume.

## Running the sweep

```bash
# from the CHESS repo root, one-time environment setup:
julia --project=Pourfecto -e 'using Pkg; Pkg.instantiate()'

julia --project=Pourfecto Pourfecto/benchmarks/combinatorial_media_scaling/run_benchmark.jl \
    results/scaling_results.csv 300
```

The second (optional) argument is the `solver_timelimit` in seconds, applied to both of
`pourfecto()`'s internal solves (planning and scheduling), so total wall time per sweep point can
run up to roughly `2 * solver_timelimit` in the worst case.

## Metrics

- **n_transfers**: count of nonzero entries in `transfers(pc)` -- the number of individual
  well/bottle-to-well transfer operations scheduled.
- **wall_time_s**: time to produce the full plan, from `@timed pourfecto(...)`.
- **mean_abs_error_g** / **max_abs_error_g**: per-well, per-reagent absolute error between
  `planned_stocks(pc)` (what the plan actually delivers) and `target_stocks(pc)` (what was
  requested), via `CHESSCore.quantity`. Water is excluded from this accuracy metric since it's
  deprioritized and expected to deviate; the 20 named reagents are not.

## Results

Full sweep, `Gurobi.Optimizer`, `solver_timelimit=300` (never hit -- every solve reported "Optimal
Solution Found" at both priority levels, no time-limit warnings anywhere in the sweep):

| n_plates | n_wells | n_transfers | wall_time_s | mean_abs_error_g | max_abs_error_g |
|---|---|---|---|---|---|
| 1  | 384    | 8,064   | 7.3  | 2.48e-5 | 5.00e-5 |
| 2  | 768    | 16,128  | 3.0  | 2.50e-5 | 5.00e-5 |
| 5  | 1,920  | 40,320  | 8.1  | 2.50e-5 | 5.00e-5 |
| 10 | 3,840  | 80,640  | 17.9 | 2.50e-5 | 5.00e-5 |
| 20 | 7,680  | 161,280 | 39.1 | 2.50e-5 | 5.00e-5 |
| 30 | 11,520 | 241,920 | 61.8 | 2.50e-5 | 5.00e-5 |

A few things stand out:

- **Transfer count is exactly dense.** `n_transfers` equals `n_wells * 21` at every sweep point --
  every well needs a nonzero dose of every one of the 20 reagents plus water, and the planner
  schedules exactly that, no more and no less. The 30-plate point reaches 241,920 transfers, well
  past the ~200,000 target.
- **Wall time scales roughly linearly with well count** once past the smallest instance (2 -> 30
  plates is a 15x increase in wells for a ~20x increase in time -- not the superlinear blowup an
  active-set QP solver would show, and nowhere near the MILP-objective wall times reported in
  `rlforlqh_comparison/README.md` at a fraction of this scale). The n_plates=1 point (7.3s) is
  slower than n_plates=2 (3.0s) purely from one-time JuMP/Gurobi startup overhead, not problem
  difficulty.
- **Accuracy is essentially exact and scale-invariant.** Mean and max per-reagent absolute error
  stay pinned at ~2.5e-5 g and ~5.0e-5 g respectively across the entire sweep -- consistent with
  solver numerical tolerance, not a systematic planning shortfall, and unaffected by plate count.
