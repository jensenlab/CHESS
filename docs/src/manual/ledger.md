# The Ledger

The `Ledger` table (`ID`, `SequenceID`, `Time`) numbers every recorded event in order, deliberately
kept separate from both the order rows happen to be stored in and the real-world clock time
(`Time`). Every other persisted table references a `LedgerID` to place itself in this history.

## Two timelines: what happened, and when we recorded it

`SequenceID` says where an event sits in the story -- and can be revised, if a mistake needs
correcting later. `Time` (paired with `ID`) says when the system actually recorded it, and never
changes once written. Keeping these separate means you can ask two different questions
independently: "what did the story say happened at this point?" and "what did we believe as of a
given moment?"

## Three ways to write

Only two of the three have their own names -- all three funnel through the same low-level
primitive, `update_ledger(sequence_id)`, which inserts a new row stamped with the current time and
returns its `ID`:

- [`append_ledger()`](@ref) -- a new slot at the end of history.
- [`insert_ledger(sequence_id)`](@ref) -- a new slot in the middle: shifts every existing
  `SequenceID` greater than or equal to `sequence_id` forward by one to make room.
- [`replace_ledger(sequence_id)`](@ref) -- a new revision of an *already-occupied* slot. The logical
  position doesn't move; a new row (higher `ID`, later `Time`) supersedes the old one for
  reconstructions as of any transaction-time at or after the replacement, while the old row remains
  reconstructable for any "as of time T" query where T predates it. Unlike the other two,
  `replace_ledger` asserts the slot is already occupied first -- `error("sequence_id $sequence_id
  does not exist yet -- use append_ledger or insert_ledger")` if not.

```julia-repl
julia> before = get_last_sequence_id()

julia> new_id = append_ledger()

julia> get_sequence_id(new_id) == before + 1
true
```

Calling `update_ledger` directly on an already-occupied `sequenceID` is silently the "replace"
operation too -- `replace_ledger` is preferred specifically because it asserts the slot exists
first, rather than succeeding either way.

## Resolving a slot to its current revision

Because more than one row can share a `SequenceID` -- a fresh revision of an existing slot is the
point, not a mistake -- every reconstruction query in `CHESSDatabase` resolves a `SequenceID` slot
to its current revision the same way. In plain terms, this asks: for each position in the story,
what is the most recent entry recorded no later than a given moment?

```sql
SELECT Max(ID), SequenceID, Time
FROM Ledger
WHERE Time <= cutoff
GROUP BY SequenceID
```

The highest-`ID` (most recently written) row no later than the requested cutoff wins. This same
query recurs throughout [Reconstruction](reconstruction.md) and [Caching & Repair](caching-repair.md)
-- it's also precisely what cache-repair's invalidation check tests: "has this slot been amended
since the cache was taken."

## Query helpers

`get_last_sequence_id(time=now())` -- the newest `SequenceID` as of `time`. `get_sequence_id(ledger_id)`
-- which slot a given `Ledger` row belongs to. `get_all_ledger_ids(sequence_id, time=now())` -- every
revision of one slot up to `time`.

`get_last_ledger_id` has two forms that are **not interchangeable**:

- `get_last_ledger_id(sequence_id, time=now())` resolves *a given slot* to its current revision --
  the one safe to use for bounding a reconstruction query.
- `get_last_ledger_id(time=now())` (bare) returns the physically newest row in the whole table,
  regardless of which slot it revises. It's appropriate for timestamping something meant to attach
  to "whatever just happened" (its only current caller is `upload_protocol`'s
  `ledger_id_entered_at` default, provenance metadata never used to bound a query) -- but it is not
  a substitute for "the current end of the story" once anything has ever been replaced.

[Committing & Uploading](committing-uploading.md) covers the higher-level API (`upload`/`update`)
built on top of these primitives -- the entry points actually used to write real operations, rather
than manipulating `Ledger` slots directly.
