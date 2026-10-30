# Ledger scale: does reconstruction cost depend on the size of the ledger?

Reconstructing one location should cost time in proportion to that location's own history, not to the
number of rows in the whole ledger. This benchmark builds a synthetic ledger of N rows and times the
reconstruction queries against it, so a change to those queries can be shown to remove the dependence on N.

- `generate.jl` builds the database with SQL on the real schema (made by `create_db`). The mix follows the
  design of the reconstruction work: 55% environment samples (one series per location and attribute), 28%
  reads that share ledger rows in batches of 96 (one tick per plate), 12% transfers in experiments of 96
  wells with dilution chains eleven steps deep fed by 200 reservoirs with Zipf-skewed use (the first
  reservoir is a hub), 2% movements, locks and activity, 0.5% of the ledger rows as amendments of earlier
  slots, and caches on 1% of the wells. The percentages are shares of operation rows; N counts ledger rows.
- `run.jl` times each query on random targets, records `EXPLAIN QUERY PLAN` of the SQL the function ran, and
  measures database size, the latency of appending an operation, the time of a mid-ledger insert (which
  renumbers every later slot) and the time of `get_last_sequence_id`.

```bash
julia --project=CHESSDatabase CHESSDatabase/benchmarks/ledger_scale/run.jl
```

Settings (environment variables): `BENCH_N` ledger rows (default 200000, the smoke size), `BENCH_DIR`
where the databases go (outside the repository), `BENCH_OUT` the results folder, `BENCH_VARIANTS`, and
`BENCH_TARGETS` (targets per query class).

Variants of one database: `noidx` has none of the `idx_chess_*` indexes, `cover` has the set of `src/indexes.jl`
(the ledger index on `(SequenceID, ID, Time)`, the default since decision D3), `idx` is that set with the ledger index
on `(SequenceID, ID)` as it was before, and `ledgeronly` has only `Ledger(SequenceID, ID)`, to separate its cost from that of the
other indexes (it is measured for size and write costs only: `BENCH_SKIP_QUERIES=1`).

The smoke size is 200,000. The 500,000 and 1,000,000 runs belong to the final measurement, not to routine
work.

## Results

`results/baseline_200000.csv` holds the timings of the queries as they were before any query was rewritten,
for the variants `noidx`, `idx` and `cover`. `results/costs_200000.csv` holds size and write costs for those
and `ledgeronly`, and
`results/plans_200000.txt` the full query plans. Columns of the baseline:

| Column | Meaning |
|---|---|
| `query`, `target` | the function and the class of location it was run on |
| `p50_ms`, `p95_ms` | wall time over `targets` x `runs` calls (the first call of each target is a warm-up) |
| `plan_scans_ledger` | the plan scans the whole `Ledger` table (or its copy `ledger_subset`) |
| `plan_materializes_ledger_subset` | the plan builds the `ledger_subset` common table expression |
| `plan_chess_index_uses` | how many plan lines use an `idx_chess_*` index |
