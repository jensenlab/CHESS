# Naive vs. distance-aware batching: how much does it cut head travel?

Measures how much of the Nimbus head's dispense-to-dispense travel distance is saved by
distance-aware batch clustering (`Pourfecto.cluster_batches`,
`Pourfecto/src/compiler/batching.jl`) versus a naive capacity-only packer, and separately how much
`batch_ordering=:exact` saves over the default `:greedy` within-batch ordering.

## Why no solver is needed

Batching is a pure compile-stage transformation: it operates on a list of `(destination well,
volume)` items and a capacity bound, entirely downstream of the planning/scheduling solve. This
benchmark generates synthetic destination-well instances directly (`generate_instances.jl`) and
calls the batching functions on them (`using Pourfecto`), with no `pourfecto()` call, no MILP/QP
solve, and no Gurobi/SCIP/HiGHS license required -- unlike `../combinatorial_media_scaling/`.

## Naive baseline

`naive_batching.jl` defines `naive_cluster_batches`: the same capacity bound and one-to-many
capability as `cluster_batches`, but destinations are packed in their original input order with no
notion of spatial locality (first-fit-by-index). This isolates exactly what distance-awareness
buys, holding batch count roughly constant between the two (see `naive_n_batches` vs.
`default_n_batches` in the results -- they're identical in every sweep point below).

## Distance metric

For each set of batches, `total_distance` sums `grid_distance` between consecutive dispenses
*within* each batch, after ordering with `order_batch(batch, method)` -- exactly what
`order_greedy`/`order_exact` themselves optimize (Euclidean distance in `(row,col)` grid-index
space, no physical pitch scaling). Two axes are swept independently:

- **Clustering**: `naive_cluster_batches` vs. `cluster_batches`, both ordered with `:greedy`.
- **Ordering**: `cluster_batches`'s output ordered with `:greedy` vs. `:exact`.

## Instances

`generate_instances.jl` places `WELL_VOLUME = 200` uL destination wells on an 8x12 grid (DeepWP96
shape) against the real Nimbus channel capacity (1000 uL, read via
`dispense_channels(head(configurations["nimbus"]))[1].capacity` -- so batches hold ~5 wells,
matching real usage), swept over:

- `pattern`: `:uniform_random` (random subset), `:clustered_block` (contiguous, roughly-square
  block, randomly placed), `:row_fill` (first `n` wells filled row-major from the corner --
  deterministic, single seed).
- `density`: fraction of the 96 wells active, `[0.1, 0.25, 0.5, 0.75, 1.0]`.
- 3 seeds per `(pattern, density)` for the two random patterns.

## Running

```bash
julia --project=Pourfecto Pourfecto/benchmarks/nimbus_batching_distance/run_benchmark.jl
```

Writes `results/distance_results.csv` (one row per instance) and prints progress per instance.

## Results

Full sweep (35 instances). `clustering_improvement_pct` = naive:greedy -> default:greedy;
`ordering_improvement_pct` = default:greedy -> default:exact. Mean over seeds, by pattern and
density:

| pattern | density | mean clustering improvement | mean ordering improvement |
|---|---|---|---|
| uniform_random  | 0.1  | 41.7% | 7.4%  |
| uniform_random  | 0.25 | 49.0% | 9.4%  |
| uniform_random  | 0.5  | 56.5% | 13.9% |
| uniform_random  | 0.75 | 63.7% | 12.9% |
| uniform_random  | 1.0  | 62.8% | 13.8% |
| clustered_block | 0.1  | 0.0%  | 29.8% |
| clustered_block | 0.25 | 0.0%  | 0.0%  |
| clustered_block | 0.5  | 18.5% | 13.4% |
| clustered_block | 0.75 | 30.5% | 11.2% |
| clustered_block | 1.0  | 33.7% | 8.4%  |
| row_fill        | 0.1  | 0.0%  | 0.0%  |
| row_fill        | 0.25 | 17.2% | 1.8%  |
| row_fill        | 0.5  | 28.4% | 9.3%  |
| row_fill        | 1.0  | 33.7% | 8.4%  |

Averaged across all densities, per pattern:

| pattern | mean clustering improvement | mean ordering improvement |
|---|---|---|
| uniform_random  | 54.7% | 11.5% |
| clustered_block | 16.5% | 12.6% |
| row_fill        | 22.2% | 5.6%  |

Overall (35 instances): mean clustering improvement **33.7%**, mean ordering improvement **11.1%**
(minimum improvement observed for either axis: **0.0%** -- never worse than the naive/greedy
baseline, in every instance).

A few things stand out:

- **Random scatter benefits the most from distance-aware clustering** (~55% mean reduction in
  head travel). This is the pattern where naive first-fit-by-index has no reason to group nearby
  wells together, so the gap between "ignore geometry" and "exploit geometry" is largest.
- **`:row_fill` and low-density `:clustered_block` show 0% clustering improvement at their lowest
  densities.** At low density with these patterns, naive's input-order packing already happens to
  group adjacent wells (row-fill's input order *is* spatial order; a sparse random block is small
  enough that first-fit rarely splits it) -- there's no locality left for distance-awareness to
  exploit. The improvement grows with density as more items compete for the same batches.
- **Ordering improvement (`:greedy` -> `:exact`) is smaller but consistent (~5-30%)**, and never
  negative -- `:exact` is optimal by construction, so this is a direct measure of how far
  nearest-neighbor's greedy choices are from optimal on real-sized batches (~5 items). It's not
  free, though: `order_exact` is a brute-force permutation search, capped at 8 items
  (`Pourfecto/src/compiler/batching.jl`), so this gain only applies where batches stay small.
- **Batch count never differs between naive and default clustering** in this sweep
  (`naive_n_batches == default_n_batches` at every point) -- both are bin-packing to the same
  capacity bound, so this benchmark measures pure travel-distance improvement, not a confound from
  aspirate-count changes.

These results support keeping `cluster_batches`'s distance-aware packing as the default (it's
never worse, often substantially better, and doesn't cost extra aspirates), and suggest
`batch_ordering=:exact` is worth adopting as a future default where batch sizes stay within its
tractable range -- though `:greedy` remains the safe default today given `:exact`'s size cap and
the brute-force cost near it.
