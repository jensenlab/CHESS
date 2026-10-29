# Transfer closure by frontier expansion

`get_transfer_ancestors` and `get_transfer_descendents` (`src/reconstruction/local_closure.jl`) find the
transfers that matter for a set of wells. They are the first step of `reconstruct_contents`,
`trace_contents`, `transfers_touch*` and `repair_content_caches`. This note states what they compute, why
the walk well by well returns the same rows as the original recursive queries, and which test covers each
step. The original queries are kept as `_get_transfer_ancestors_global` and `_get_transfer_descendents_global`
and are the oracle of `test/equivalence/`.

## Why a rewrite

The original queries build `ledger_subset` (the current revision of every ledger slot in the window) over the
whole ledger and then run a recursive query over every transfer in it. Their time grows with the length of
the ledger even when the closure has a handful of wells. The rewrite reads, for each well, only the
transfers that name it, through `Transfers(Source, LedgerID)`, `Transfers(Destination, LedgerID)` and
`Discards(Source, LedgerID)`, and tests visibility on those rows with `visible_join`. The time depends on the
size of the closure and on the lifetime degree of its wells.

It does not remove the cost of a *hub*: a well that fed many wells (a shared reservoir) has all of its outgoing
transfers in the closure of every well downstream of it, as collateral rows, so that closure grows with the
history of the hub.

## Definitions

A ledger row is *visible* in a window `[from, to]` at time `t` when it is the current revision of its slot,
the slot is in the window and the row was written at or before `t` (`src/reconstruction/visibility.jl`).
An operation row is visible when its `LedgerID` is a visible ledger row.

- `Y(w, in)`: the visible transfers with `Destination = w`.
- `Y(w, out)`: the visible transfers and discards with `Source = w`. A discard has `Destination = NULL`.
- `y`: the visible transfers and discards, the set the original query calls `y`.

## Ancestors

The original computes `x`, the least set of rows of `y` that contains the *seeds* (rows with `Destination` or
`Source` in `locs`) and, for a row `r` in the set, every row of `y` with `Destination = r.Source`. The
well set `A` is the sources and destinations of `x`. The *collateral* rows are the rows of `y` with `Source` in
`A` whose ledger entry is not in `x`. The result is `x` with `Core = 1` and the collateral rows with
`Core = 0`, one row per transfer or discard row (rows are identified by table and row ID; a ledger entry can hold several), ordered by `SequenceID`, then ledger entry, then the order recorded.

The rewrite:

1. fetch `Y(l, in) ∪ Y(l, out)` for each `l` in `locs`; these are the seeds;
2. for each well that is the source of a row added and was not expanded before, fetch `Y(w, in)` and add the
   rows not seen before; repeat until no source is new;
3. compute `A` from the rows found, fetch `Y(a, out)` for each `a` in `A` and keep the rows whose ledger entry is
   not in `x`;
4. sort by `SequenceID`, ledger entry and row; a row found as core is not repeated as collateral.

Wells are sent to the database in chunks of 500 (`_id_chunk`).

- **T1, visibility.** A transfer or discard row is in the original `y` exactly when its ledger row is in
  `ledger_subset`, which is exactly when `visible_join` keeps it (Lemma V in `visibility.jl`, checked against the
  CTE for every operation table by the equivalence suite). Every row the rewrite reads is filtered by
  `visible_join`, so the rows it can see are the rows of `y` with a given key.
  Test: `transfer closure T1` (an amended slot read before and after the amendment, four windows, a time before
  anything was written), and the equivalence run at amended slots and time cut-offs.
- **T2, seeds.** The seeds of the original are the rows of `y` with `Destination in locs OR Source in locs`, which are
  `Y(l, in) ∪ Y(l, out)` over `l`. Test: ancestors of one or several locations, of a source only, of a destination
  only, of an unrelated location and of no location.
- **T3, fixpoint.** The original `x` is the least set containing the seeds and closed under
  "`r` in the set and `y.Destination = r.Source` imply `y` in the set". The rows with `y.Destination = s` are
  exactly `Y(s, in)`. Step 2 adds `Y(s, in)` for every source `s` of a row in the set, so everything it adds is in
  the least set, and a row of the least set is reached because it is `Y(s, in)` for the source of an earlier row.
  Each well is expanded once (the `expanded` set) and the set of rows only grows within the finite set of
  transfers, so the loop ends, also when the transfers form a cycle.
  Test: `a cycle ends and expands each well once`; every comparison with the original.
- **T4, collateral.** The collateral of the original is `{y : y.Source in A, y.LedgerID not in LedgerIDs(x)}`, which is
  the union of `Y(a, out)` over `a` in `A` without the ledger entries of `x`; step 3 is that definition. A discard of
  a well in `A` is collateral too, with `Destination` missing.
  Test: the `Core` split of the ancestors of a well that received from two bottles, passed material on, and
  discarded some.
- **T5, output.** The original ends with `GROUP BY LedgerID` and `Max(Core)`, so it returns one row per ledger entry
  with `Core = 1` if any row of the entry is in `x`, ordered by the `SequenceID` of the entry. For an entry with one
  transfer or discard, step 4 returns the same. The original assumes that an entry has at most one such row; with
  several (see [ticks](ticks.md)) its `GROUP BY` would drop all but one, so the rewrite and the `:legacy` queries keep
  every row, identified by table and row ID. The result differs from the original only for such entries.
  Test: unique rows, columns, order; the multi-row cases of `test_ticks.jl`.
- **T6, descendants.** The original runs its recursion on all rows of `Transfers`, without the visibility test, and
  joins only the final rows to `ledger_subset`: a transfer that is not visible (outside the window, superseded, or
  written after `time`) still leads to wells whose own visible transfers are returned. The rewrite follows the
  same raw rows through `Transfers(Destination, LedgerID)` and `Transfers(Source, LedgerID)` and tests
  visibility at the end on the ledger rows found, in chunks. The result has the columns `LedgerID`, `EncumbranceID`,
  `Source`, `Destination`, `Quantity`, `Unit`, `ID`, `SequenceID`, `Time`. Discards are not followed.
  Test: `T6`, a transfer outside the window that leads to a transfer inside it.

## Forward tracing

`_transfers_out_of` returns the visible transfers whose source is in a set of wells for `trace_forward`. It
reads them through `Transfers(Source, LedgerID)` and orders them by `SequenceID`. The original read them through a
`ledger_subset` and returned them in an order that depended on the query plan. The order matters to
`_spread_forward` only for the `Depth` and `ViaWell` of a well, which are taken from the state of the source at the
moment a transfer is processed: with a transfer into the source and a transfer out of it in the same round, the
source's final state is used only if the first is processed first. `SequenceID` order does that, and it is the
order of the history. The trace of reached wells and sequence IDs is the same for every order. Test:
`transfers out of a well are read in sequence order`.

## What is not changed

`encumbrances=true`, `reconstruction_mode[] === :legacy` and more than `LOCAL_KEY_LIMIT` seeds use the original
queries. `repair_content_caches` calls `get_transfer_descendents` and so uses the rewrite for its closure.
`transfers_touch` and `transfers_touched_by` call the two functions. The ancestors have an `EncumbranceID` column only
with `encumbrances=true`; without it `transfers_touched_by` reports `EncumbranceID` 0 (the original threw an
`ArgumentError` whenever there was a row to read). This is an intended difference from the frozen original and the
equivalence suite compares against the original's rows with 0 added (`eqv_touched_by`).

## Intended difference: the order of a location's history in `reconstruct_contents`

`reconstruct_contents` keeps for each location a list of `(SequenceID, snapshot)` entries that
`find_most_recent_location` binary-searches, so the list must stay sorted. When a core well has no cache in the range a
call reads, the call recurses and bootstraps that well from an older cache, after the caller already recorded a stub for
it at the caller's own sequence point. The older entry was appended behind the newer one, the search then found nothing
and a transfer was applied to a missing destination (`MethodError` in `_reconstruction_transfer`). The ledger that
triggers it is valid: a cache of the target well exactly at the slot before a transfer, with the source's newest cache
older. `push_location!` now inserts an entry that is older than the last one at its place (after equal ones); the usual
append is unchanged. The frozen original has the bug, so the equivalence suite redefines `Legacy.push_location!` with the
same insertion (the frozen file is not edited). Tests: "push_location! keeps each history sorted"
(`test_reconstruct_contents_order.jl`) and "reconstruct_contents with a cache at the slot before a transfer"
(two reduced recipes from deep runs; the stock must be the same for `max_cache` 0, the point's and the slot).
