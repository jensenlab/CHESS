# The Ledger

```@meta
DocTestSetup = :(using CHESS)
```

The `Ledger` table (`ID`, `SequenceID`, `Time`) numbers every recorded event in order. The
numbering is separate from both the order in which rows are stored and the clock time of the
event. Every other persisted table has a `LedgerID` that places its rows in this history.

## Sequence and time

`SequenceID` is the event's place in the history. It can be revised if a mistake needs correcting
later. `Time`, together with `ID`, is when the system recorded the event, and it never changes once
written. The two answer different questions: what the history says happened at a given point, and
what the database held as of a given moment.

## Writing to the ledger

All writes call the low-level function `update_ledger(sequence_id)`, which inserts a new row
stamped with the current time and returns its `ID`. Three functions wrap it:

- [`append_ledger()`](@ref) adds a new slot at the end of the history.
- [`insert_ledger(sequence_id)`](@ref) adds a new slot in the middle. Every existing `SequenceID`
  greater than or equal to `sequence_id` moves forward by one to make room.
- [`replace_ledger(sequence_id)`](@ref) adds a new revision of an occupied slot. The slot keeps its
  place in the history. The new row, with a higher `ID` and a later `Time`, supersedes the old one
  for reconstructions as of any time at or after the replacement. The old row remains available for
  any as-of-time query that predates the replacement. `replace_ledger` first checks that the slot
  is occupied and raises an error pointing to `append_ledger` or `insert_ledger` if it is not.

```jldoctest ledger
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> before = get_last_sequence_id()
1

julia> new_id = append_ledger()
2

julia> get_sequence_id(new_id) == before + 1
true
```

Calling `update_ledger` directly on an occupied sequence ID also replaces the slot.
`replace_ledger` is preferred because it checks that the slot exists.

## Resolving a slot to its current revision

More than one row can share a `SequenceID`, because a revision of a slot is a new row. Every
reconstruction query in `CHESSDatabase` resolves a slot to its current revision in the same way: for
each sequence ID, it takes the most recent row recorded no later than a given time.

```sql
SELECT Max(ID), SequenceID, Time
FROM Ledger
WHERE Time <= cutoff
GROUP BY SequenceID
```

The row with the highest `ID`, the most recently written, wins among those no later than the
cutoff. The same query is used throughout [Reconstruction](reconstruction.md) and
[Caching & Repair](caching-repair.md). Cache repair uses it to test whether a slot has been amended
since a cache was taken.

## Query helpers

- `get_last_sequence_id(time=now())` returns the newest `SequenceID` as of `time`.
- `get_sequence_id(ledger_id)` returns the slot that a `Ledger` row belongs to.
- `get_all_ledger_ids(sequence_id, time=now())` returns every revision of one slot up to `time`.

`get_last_ledger_id` has two forms that are not interchangeable:

- `get_last_ledger_id(sequence_id, time=now())` resolves one slot to its current revision. Use it
  to bound a reconstruction query.
- `get_last_ledger_id(time=now())`, with no slot, returns the most recently written row in the
  table, whichever slot it revises. It suits timestamping metadata that attaches to whatever
  happened last. Once any slot has been replaced, it is not the end of the history.

[Committing & Uploading](committing-uploading.md) describes `upload` and `update`, which write real
operations on top of these functions.
