# Reconstruction scaling: does history length slow down `reconstruct_location`?

CHESS records lab operations to an append-only ledger and reconstructs any location's current state
on demand by replaying that history (`reconstruct_location`/`reconstruct_location!`, see
[reconstruct_location.jl](../../src/reconstruction/reconstruct_location.jl)). This benchmark measures
how the wall time of that replay scales as a location's operation history grows, broken out by
operation type, and at a scale approximating a real lab (~100 pieces of labware, up to ~100,000
operations/day).

## Why break it out by operation type

Reading the reconstruction code turned up a specific reason to expect transfers to scale worse than
moves, reads, or environmental changes: reconstructing a well's *contents* doesn't just replay that
well's own ledger rows. `get_transfer_ancestors`
([reconstruct_contents.jl](../../src/reconstruction/reconstruct_contents.jl)) runs a **recursive SQL
CTE** over the whole `Transfers` table, walking backward through `x.Source = y.Destination` to find
every upstream transfer that ever contributed material to the target well. Its cost depends on the
*depth* of the transfer chain feeding a well (how many hops back the recursion has to walk), not just
that well's own operation count. Moves (`reconstruct_children!`/`reconstruct_parent!`) walk the
location tree, and reads (`reconstruct_reads!`) are a flat per-location table filter -- neither has
anything like the transfer chain's backward recursion.

That gives this benchmark a specific, falsifiable thing to measure: scaling **per operation type**,
with transfer *chain depth* as the primary suspect, rather than only one aggregate "time vs. ledger
size" curve.

## Scenarios

Each scenario keeps one growing ledger across its sweep (extending it by the gap between consecutive
sweep points, not rebuilding from scratch), so `wall_time_s` reflects reconstructing a location out of
a ledger that has genuinely accumulated that many prior operations.

- **transfer** -- a single linear transfer chain: a source bottle, then wells `w1 -> w2 -> ... -> wN`
  where each `wi` is filled entirely from `w[i-1]`. Isolates transfer-ancestor *chain depth* as a
  controlled variable. Reconstructs the current chain tail after each sweep point.
- **move** -- one plate (`ChainState`'s counterpart for movement) repeatedly toggled between two
  shelves. Reconstructs that plate.
- **read** -- repeated `BenchAbsorbance` reads recorded on one fixed assay well. Reconstructs that
  well.
- **env** -- repeated `Temperature` changes on a rotating ancestor of one fixed assay well.
  Reconstructs that well (its environment is inherited from the ancestor chain).
- **realistic** -- a ~100-labware lab (20 reagent bottles, 60 intermediate 96-well plates, 20 assay
  96-well plates -- [build_realistic_lab](../common/lab_simulator.jl)) driven by a weighted mix of all
  four operation types approximating a real day (70% transfer, 15% move, 10% read, 5% env), swept
  toward the ~100,000-operations/day estimate. Transfers here are restricted to a strict
  bottle -> intermediate -> assay DAG (never backward or sideways within a tier), so the
  transfer-ancestor chain feeding any well stays at most 2 hops deep regardless of operation count --
  the opposite regime from the `transfer` scenario's unbounded chain depth. Reconstructs both a
  representative assay well and the whole lab root after each sweep point.

Each sweep stops growing once a single `reconstruct_location` call exceeds a wall-time cap (60s) --
hitting that cap is itself a result, not just an implementation safeguard.

## Four pre-existing correctness bugs surfaced along the way

While building and then stress-testing the `transfer`/`realistic` scenarios, four unrelated
correctness bugs in the reconstruction code surfaced. All four are now fixed.

**Bug A (fixed).** `fetch_content_cache`
([reconstruct_contents.jl](../../src/reconstruction/reconstruct_contents.jl)) used to return `Empty()`
both when it found a genuinely-empty cache row *and* when it found no cache row at all, so the two
`isnothing(stock)` checks that were supposed to trigger a recursive-reconstruction fallback for
"no cache found here" could never fire -- any ancestor (e.g. a reagent bottle) cached *earlier* than a
later-created target's own creation-time cache point would silently bootstrap as incorrectly empty,
crashing a downstream `withdraw!` during replay. Fixed: `fetch_content_cache` returns `nothing` (not
`Empty()`) when no cache row is found, so the fallback path actually runs. Regression test:
[`test/test_reconstruct_contents_bootstrap.jl`](../../test/test_reconstruct_contents_bootstrap.jl).

**Bugs C and D (fixed).** Every `encumbrances=true` reconstruction (previewing state with
currently-planned-but-not-yet-executed protocol steps included) was broken outright by SQL typos,
independent of Bug A/B -- six sites referenced a CTE column that didn't exist (Bug C), two more
referenced real table columns under the wrong name (Bug D). Fixed across
`reconstruct_contents.jl`/`reconstruct_attributes.jl`/`reconstruct_children.jl`/
`reconstruct_activity.jl`/`reconstruct_lock.jl`/`reconstruct_parent.jl`. Regression test:
[`test/test_reconstruct_encumbrances.jl`](../../test/test_reconstruct_encumbrances.jl).

**Bug B (fixed).** Even with Bug A fixed, a broader sweep over a 300-operation realistic lab still
found roughly **6-8% of wells** failing to reconstruct or silently returning the *wrong* stock
composition. Root cause: `get_transfer_ancestors`'s recursive CTE built a well's bootstrap history by
following "what fed my sources," but never checked whether a source was *drained away to somewhere
outside the query's closure* in between -- so replay could resurrect stock that was already spent
elsewhere by the time of the transfer actually being reconstructed. This applied to any interim
withdrawal, partial or complete, not just full drains -- a full drain tended to crash, a partial one
silently returned the wrong value. Fixed by widening the closure query to also discover a core well's
other outgoing transfers (tagged with a `Core` column so `reconstruct_contents` only does full,
possibly-recursive bootstrap work for genuine ancestors -- collateral destinations are cheap `Empty()`
stubs), which also fixed a related hang: the recursive CTE used `UNION ALL`, which never terminates on
a genuine cycle in the transfer graph (switched to `UNION`). Regression tests:
[`test/test_reconstruct_contents_ancestor_closure.jl`](../../test/test_reconstruct_contents_ancestor_closure.jl).
The re-run 300-operation sweep now shows **0 failures out of 480 wells**, down from ~30.

**Performance issue (fixed, not a correctness bug).** After Bug B's fix, the realistic scenario's
well-reconstruction time grew to an impractical 213.9s at 100,000 accumulated operations. Isolating SQL
time from Julia time on the worst-case well showed the SQL query taking 0.48s while the full
reconstruction took 204.8s -- 99.8% of the cost was `reconstruct_contents`'s own bookkeeping, not the
query. Root cause: `find_most_recent_location` did a full linear scan of the entire growing accumulator
on every lookup (twice per transfer row), an O(n²) pattern. Fixed by replacing the
`DataFrame`-scanned accumulator with a `Dict{LocationID, Vector}` index (each lookup now scans only
that one location's own history) and by skipping full reconstruction of collateral-row destinations,
whose balances are never read back out. See [REPORT.md](REPORT.md) for the full measurement and the
post-fix numbers (7.1s at 100,000 operations, down from 213.9s).

**Performance issue (fixed, not a correctness bug).** Profiling the O(n²)-fixed code (`Profile.@profile`
on the same worst-case well) found `find_most_recent_location` itself still doing a linear scan --
26.4% of `reconstruct_contents`'s time -- over a location's own entry vector, which for a heavily-reused
hub bottle can still run to thousands of entries. Each location's vector is always appended in
non-decreasing `SequenceID` order (verified by reading every `push_location!` call site), so the scan
was unnecessary: switched to `searchsortedlast` (O(log k) instead of O(k)). A clean, unprofiled
before/after on the same well showed 10.6s -> ~4.5s, a 2.3x speedup. See REPORT.md for the full
writeup.

This benchmark's fixtures (`build_realistic_lab`, `start_transfer_chain`) still create every location a
scenario will ever need *before* caching any of that scenario's sources (see the docstring on
`build_realistic_lab` in [../common/lab_simulator.jl](../common/lab_simulator.jl)) -- that ordering
predates all four fixes above and is no longer required by any of them, but is harmless to keep.

## Running it

```bash
julia --project=CHESSDatabase CHESSDatabase/benchmarks/reconstruction_scaling/run_benchmark.jl \
    [results_csv]
```

Writes raw results to `results/reconstruction_scaling.csv` (default) or the given path. See
[REPORT.md](REPORT.md) for the write-up of an actual run's results.
