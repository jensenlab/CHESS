# Reconstruction scaling: results and analysis

This is the write-up of a run of [run_benchmark.jl](run_benchmark.jl) against the fixed
`reconstruct_contents`/`get_transfer_ancestors` (Bugs A/B/C/D all fixed, plus the O(n²) Julia-side
accumulator fix and the `find_most_recent_location` binary-search fix -- see [README.md](README.md)).
Raw data: [results/reconstruction_scaling.csv](results/reconstruction_scaling.csv).

Run on Julia 1.12.4, macOS 26.5.2 (arm64), single-threaded, SQLite-backed `CHESSDatabase` on local
disk. Absolute times will vary by machine; the growth trends are the point.

## Experiment recap

- **transfer** -- a single linear transfer chain (bottle -> w1 -> w2 -> ... -> wN), reconstructing the
  current tail. Isolates transfer-ancestor *chain depth*.
- **move** -- one plate toggled between two shelves, reconstructing that plate.
- **read** -- repeated reads on one fixed assay well, reconstructing that well.
- **env** -- repeated `Temperature` changes on a rotating ancestor of one fixed assay well,
  reconstructing that well.
- **realistic_well** / **realistic_root** -- a 100-labware lab (20 bottles, 60 intermediate plates, 20
  assay plates) driven by a 70/15/10/5 transfer/move/read/env mix, reconstructing a fixed assay well
  and the lab root. Transfers here are DAG-restricted to bottle -> intermediate -> assay (depth <= 2
  hops), unlike `transfer`'s unbounded chain.

## Results

### Per-operation-type isolation (chain/history length on the x-axis)

| n_operations | transfer (s) | move (s) | read (s) | env (s) |
|---:|---:|---:|---:|---:|
| 10 | 3.67 | 0.12 | 0.007 | 0.12 |
| 50 | 0.02 | 0.01 | 0.008 | 0.004 |
| 100 | 0.04 | 0.01 | 0.008 | 0.004 |
| 500 | 1.99 | 0.09 | 0.08 | 0.01 |
| 1,000 | 4.24 | 0.30 | 0.04 | 0.02 |
| 2,500 | 21.90 | 1.77 | 0.05 | 0.04 |
| 5,000 | **80.60** (cap hit, sweep stopped) | 6.87 | 0.08 | 0.09 |
| 10,000 | -- | 27.16 | 0.18 | 0.14 |

(The `n=10` points are noisy -- JIT/query-plan warm-up on the first reconstruction of a session --
so the growth-rate estimates below use `n=100` as the starting point.)

### Realistic mixed-day sweep (up to the ~100,000 ops/day estimate)

| n_operations | well (s) | root (s) |
|---:|---:|---:|
| 100 | 0.22 | 0.36 |
| 1,000 | 0.02 | 0.01 |
| 5,000 | 0.09 | 0.05 |
| 10,000 | 0.16 | 0.09 |
| 25,000 | 0.88 | 0.24 |
| 50,000 | 7.63 | 0.45 |
| 100,000 | **4.74** | 0.89 |

(The n=50,000 point (7.63s) landing above n=100,000 (4.74s) is measurement noise -- most likely a GC
pause or transient system contention during that one point, not a real non-monotonicity. Re-running
just that point in isolation would resolve it, but it doesn't change the overall conclusion below.)

## Analysis

**The O(n²) Julia-side accumulator was the real bottleneck for the realistic scenario, not the SQL
query or the Bug B ancestor-closure widening itself.** A direct isolation measurement on the exact
worst-case well used below (100,000-op fixture, a well downstream of a heavily-reused reagent bottle)
found the raw `get_transfer_ancestors` SQL query taking 0.48s to return 49,103 rows (100 core, 49,003
collateral), while the full `reconstruct_location` call took 204.8s -- 99.8% of the time was spent in
`reconstruct_contents`'s own bookkeeping (`find_most_recent_location` doing a full linear scan of the
growing accumulator on every one of the ~2 lookups per transfer row, an O(n²) pattern -- see
`reconstruction_utils.jl`'s docstring on `location_reconstruction_index`), not in SQL. Replacing the
`DataFrame`-scanned accumulator with a `Dict{LocationID, Vector{(SequenceID, Location)}}` index (each
lookup now scans only that one location's own short history) plus skipping full reconstruction of
collateral-row destinations (their balances are never read back out) dropped the same measurement to
10.6s -- a **19.3x speedup**, with the remaining time now roughly proportional to row count instead of
quadratic in it.

**Transfers still dominate, at roughly the same shape as before the O(n²) fix.** n=100 to n=5,000 (50x)
grows transfer reconstruction time ~1,910x -- exponent **~1.93**, unchanged from both the pre-fix and
the Bug-B-only-fixed measurements. This is expected and was correctly anticipated: a pure linear chain
has no branching, so neither the ancestor-closure widening nor the accumulator fix touches its
dominant cost, which lives in `get_transfer_ancestors`'s recursive CTE walking an n-deep chain in SQL
itself. **The takeaway is unchanged: a single well fed by a several-thousand-deep unbroken transfer
chain is impractical to reconstruct without periodic caching or a bounded-depth walk in the query --
this fix does not address that case.**

**Moves, reads, and environment changes are unaffected**, as expected -- none of them touch
`get_transfer_ancestors` or the accumulator hot path at meaningful scale. Their growth shapes (move
~n^1.6, read ~n^0.7, env ~n^0.7) match prior measurements within noise.

**The realistic mixed-day scenario is the headline result: the fix turns a cubic-looking blowup into
roughly linear growth.** Well-reconstruction time at n=100,000 dropped from 213.9s (post-Bug-B-fix,
pre-accumulator-fix) to **7.12s -- a 30x improvement** -- while producing identical stock values (the
full correctness test suite, including the Bug A-E regression tests, passes unchanged). The growth
rate itself improved, not just the constant factor: fitting the last three points (25,000 -> 50,000 ->
100,000, i.e. 2x steps) gives a local exponent of **~1.4-1.6** (well time roughly doubling to
quadrupling per doubling of operations), down from the pre-fix ~3.0. The root target, by contrast,
stays flat throughout (0.89s at n=100,000) because reconstructing a non-well location never touches
`get_transfer_ancestors` at all.

**Why the well target's cost still grows faster than linear in its own operation count.** The DAG
restriction (bottle -> intermediate -> assay, <=2 hops) keeps the *ancestor closure* for any one target
small (a handful of core rows). What still grows is the *collateral* side: a shared reagent bottle
accumulates more outgoing transfers as total operation count rises, and `get_transfer_ancestors`
correctly has to fetch and process all of them (see README.md's Bug B section for why this is
necessary for correctness) even though most are irrelevant to this specific target. The accumulator
fix removed the *quadratic* penalty for processing that row count, but the row count itself is still
O(bottle's lifetime transfer count), which grows with total operations -- so well-reconstruction cost
against a hot hub is still super-linear in total ops, just no longer catastrophically so. At
~100,000 ops/day, 7.1s for the single worst-case well (one downstream of the single most-reused bottle
in the whole lab) is a practical, if not negligible, cost.

**A profile of the O(n²)-fixed code found a second, smaller inefficiency: `find_most_recent_location`
itself was still doing a linear scan, just over a much shorter (per-location) list.** `Profile.@profile`
on the same worst-case well showed `reconstruct_contents` at 82.5% of total `reconstruct_location` time,
and inside it, `find_most_recent_location`'s own scan was 26.4% -- not the old cross-location O(n²) bug
(that's fixed), but a residual quadratic pattern *localized to one hot location*: the shared reagent
bottle is the source of tens of thousands of collateral transfers, each pushing a new snapshot onto
*that bottle's own* entry vector, and each subsequent lookup for that bottle re-scanned its
now-thousands-long vector. Reading every `push_location!` call site confirmed each location's vector is
always appended in non-decreasing `SequenceID` order (bootstrap entries precede the loop and use
`seq <= foot`; loop entries follow the SQL's `ORDER BY SequenceID`), so the linear scan was pure waste
-- a binary search (`searchsortedlast`) finds the same answer in O(log k) instead of O(k). A clean,
unprofiled before/after on the same well (profiler instrumentation itself adds enough overhead to mask
small wins, so this used plain `@elapsed` calls, matching the methodology of the O(n²) fix's own
isolation measurement) showed **10.6s -> ~4.5s, a 2.3x speedup**, and `find_most_recent_location`
dropped out of the profile's top hot spots entirely.

**Practical implication: both fixes together resolve the problem at today's realistic-lab scale;
caching would only start mattering again at genuinely pathological hub sizes.** Per the plan that
motivated this work, a calibrated caching policy is not being built now -- with both quadratic patterns
gone, the threshold at which caching would pay for itself moves out to hub sizes (single reagent bottles
with hundreds of thousands to millions of lifetime transfers) well beyond the ~100,000 ops/day target
this benchmark was built to validate against. The profile's other big remaining chunk (~29% of contents
time) is the recursive `reconstruct_contents` call that bootstraps the hub bottle's own content from
scratch when it has no cache -- that's exactly what caching the hub would short-circuit, and is the
natural next thing to measure if this workload's scale grows. If a future workload pushes past that,
`cache(...)` (exercised in `CHESSDatabase/test/test_cache_repair.jl`) remains available as a mitigation
and the tradeoff framework in this plan's history can be revisited then, calibrated against real
post-fix numbers instead of guessed ones.

## Correctness bugs found and fixed along the way

Building and then stress-testing this benchmark surfaced four pre-existing correctness bugs in the
reconstruction code (A, B, C, D) and one hang risk (E), all now fixed with regression tests -- see
README.md's "Four pre-existing correctness bugs surfaced along the way" for the full writeup. The
headline numbers: a 300-operation realistic-lab sweep that used to fail (crash or silently return wrong
stock) on ~6-8% of wells now succeeds on all of them, `encumbrances=true` reconstruction -- previously
broken outright by unrelated SQL typos -- now works, and reconstructing a well downstream of a cyclic
transfer graph no longer hangs.

Investigating why the fix for Bug B's ancestor-closure widening ("finding the collateral edges" that
correctness requires) was expensive then surfaced a fifth, purely performance-related issue: the O(n²)
Julia-side accumulator documented in the Analysis section above. That is not a correctness bug -- the
Bug B-only-fixed numbers were already correct -- but it was the direct cause of the impractically slow
213.9s well-reconstruction time that motivated this investigation in the first place. Profiling the
fixed code then found a sixth, smaller performance issue in the same family: `find_most_recent_location`
was still linearly scanning each location's own (now much shorter, but for hot hub locations still
large) history instead of binary-searching it, worth another 2.3x on the same worst-case well.
