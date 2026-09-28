# Caching & Repair

```@meta
DocTestSetup = :(using CHESS)
```

[Reconstruction](reconstruction.md) can always replay a location's entire history from nothing --
caching exists to bound how much of that history it actually has to replay.

## Taking a cache

`cache` (`loc, sequence_id=nothing, time=now()`) is an explicit, manually-invoked snapshot --
not automatic on every write, and not on any scheduler. It asserts `loc` (and everything nested
within it) is already committed before writing anything. The examples use a new database with one
plate and two transfers, then cache well A2:

```jldoctest caching
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> plate = build_location(loc"WP96", "Plate 1");

julia> deposit!(plate["A1"], 200u"µL" * rgt"water")

julia> committed = commit_location!(plate);

julia> first_transfer = upload(transfer!, committed["A1"], committed["A2"], 50u"µL");

julia> upload(transfer!, committed["A1"], committed["A3"], 10u"µL");

julia> a2 = CHESSCore.location_id(committed["A2"]);

julia> cache(committed["A2"])
```

A call to `cache` writes one row per applicable sub-state table -- parent, children, environment,
lock/activity, and (for a `Well` only) contents -- each stamped with the `Ledger` revision current
at `sequence_id`. It doesn't recurse into children automatically; callers decide what to snapshot
and when.

## Deduplicating expensive sub-objects

The sub-objects most expensive to store repeatedly -- a location's child set, its attribute set, a
well's stock -- are shared automatically when identical: `CachedChildSets`, `CachedAttributeSets`,
and `CachedStocks` each store one copy of a given child-set, attribute-set, or stock, so many
locations that happen to have an identical one at cache time reuse that same stored copy instead of
duplicating it. Committing the plate cached all 96 wells, but most are empty and share one stored
stock:

```jldoctest caching
julia> query_db("SELECT COUNT(*) AS cache_rows, COUNT(DISTINCT StockID) AS stored_stocks FROM CachedContents")
1×2 DataFrame
 Row │ cache_rows  stored_stocks
     │ Int64       Int64
─────┼───────────────────────────
   1 │         97              3
```

## Repair: keeping caches correct as history changes

Amending history (via `update` with [`replace_ledger`](@ref)/[`insert_ledger`](@ref), see
[Committing & Uploading](committing-uploading.md)) can invalidate a cache taken after the amended
point. `process_update` runs two steps automatically, in order:

**`validate(ledger_id)`** -- forces a full forward replay of everything downstream of the edit, all
the way to `get_last_sequence_id()`, with the relevant cache masked out (`max_cache` set to just
before it). This exists purely to let any physically-impossible state the edit created (a negative
stock, an overfilled well) surface as a real error rather than silently persisting.

**`cache_repair(ledger_id)`** -- figures out what kind of operation was edited
(`isa_transfer`/`isa_movement`/`isa_environment_attribute`/`isa_lock`/`isa_activity`) and repairs
the matching cache. It finds every cache reachable from the edited sequence point onward, and for
each, recomputes the value with that specific cache masked out (`max_cache = cache_seq_id - 1`). If
the recomputed value differs from what the stale cache held -- or the cache's own history has
itself since been amended -- a new cache row is written to supersede the old one **going forward
only**. The old row is never deleted, so a reconstruction query asking "as of an earlier moment"
still sees exactly what it saw before the repair.

## A repair in practice

Well A2 was cached after both transfers. Correcting the first transfer from 50 µL to 20 µL amends
history before that cache, so repair writes a new cache row for A2 (`StockID` 4) that supersedes
the stale one:

```jldoctest caching
julia> query_db("SELECT ID, StockID, LedgerID FROM CachedContents WHERE LocationID = $a2")
2×3 DataFrame
 Row │ ID     StockID  LedgerID
     │ Int64  Int64    Int64
─────┼──────────────────────────
   1 │     9        2         2
   2 │    97        3         4

julia> update(transfer!, reconstruct_location(CHESSCore.location_id(committed["A1"])),
              reconstruct_location(a2), 20u"µL"; ledger_id=replace_ledger(get_sequence_id(first_transfer)));
caches updated: 1

julia> query_db("SELECT ID, StockID, LedgerID FROM CachedContents WHERE LocationID = $a2")
3×3 DataFrame
 Row │ ID     StockID  LedgerID
     │ Int64  Int64    Int64
─────┼──────────────────────────
   1 │     9        2         2
   2 │    97        3         4
   3 │    98        4         4

julia> stock(reconstruct_location(a2))
0.02 mL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.02 mL        100.0 %
```

The old row stays, so a reconstruction as of a time before the correction still uses it.

[Encumbrances](encumbrances.md) covers the next topic: non-binding, future-dated reservations that
sit alongside this same ledger without touching the canonical history tables at all.
