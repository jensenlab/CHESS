# Caching & Repair

```@meta
DocTestSetup = :(using CHESS)
```

[Reconstruction](reconstruction.md) can replay a location's entire history from the beginning. A
cache limits how much of the history must be replayed.

## Taking a cache

`cache` takes `loc, sequence_id=nothing, time=now()` and stores a snapshot. It is called explicitly.
It does not run on every write or on a schedule. It first checks that `loc` and everything nested in
it are committed. The examples use a new database with one plate and two transfers, then cache well
A2:

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

A call to `cache` writes one row for each applicable sub-state table: parent, children,
environment, lock and activity, and, for a `Well` only, contents. Each row is stamped with the
`Ledger` revision current at `sequence_id`. `cache` does not recurse into children, so the caller
chooses what to snapshot and when.

## Shared storage

The sub-objects that are most expensive to store repeatedly are a location's child set, its
attribute set, and a well's stock. `CachedChildSets`, `CachedAttributeSets`, and `CachedStocks` each
store one copy of an identical child set, attribute set, or stock, and every cached location that
has it refers to that copy. Committing the plate cached all 96 wells, but most are empty and share
one stored stock:

```jldoctest caching
julia> query_db("SELECT COUNT(*) AS cache_rows, COUNT(DISTINCT StockID) AS stored_stocks FROM CachedContents")
1×2 DataFrame
 Row │ cache_rows  stored_stocks
     │ Int64       Int64
─────┼───────────────────────────
   1 │         97              3
```

## Repair

Amending history with `update` and `replace` or `insert` (see
[Committing & Uploading](committing-uploading.md)) can invalidate a cache taken after the amended
point. `process_update` runs two steps in order.

`validate(ledger_id)` replays everything downstream of the edit, up to `get_last_sequence_id()`,
with the relevant cache masked out by setting `max_cache` to just before it. Any physically
impossible state that the edit created, such as a negative stock or an overfilled well, then
surfaces as an error instead of persisting.

`cache_repair(ledger_id)` determines the kind of operation that was edited, using
`isa_transfer`, `isa_movement`, `isa_environment_attribute`, `isa_lock`, and `isa_activity`, and
repairs the matching cache. It finds every cache reachable from the edited sequence point onward
and recomputes each value with that cache masked out (`max_cache = cache_seq_id - 1`). If the
recomputed value differs from the stale cache, or the history behind the cache has since been
amended, it writes a new cache row that supersedes the old one from that point forward. The old row
is never deleted, so a reconstruction as of an earlier time still sees what it saw before the
repair.

## Example of a repair

Well A2 was cached after both transfers. Correcting the first transfer from 50 µL to 20 µL amends
the history before that cache, so repair writes a new cache row for A2, with `StockID` 4, that
supersedes the stale one:

```jldoctest caching
julia> query_db("SELECT ID, StockID, LedgerID FROM CachedContents WHERE LocationID = $a2")
2×3 DataFrame
 Row │ ID     StockID  LedgerID
     │ Int64  Int64    Int64
─────┼──────────────────────────
   1 │     9        2         2
   2 │    97        3         4

julia> update(transfer!, reconstruct_location(CHESSCore.location_id(committed["A1"])),
              reconstruct_location(a2), 20u"µL"; replace=get_sequence_id(first_transfer));
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
20.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  20.0 μL          100 %
```

The old row stays, so a reconstruction as of a time before the correction still uses it.

[Encumbrances](encumbrances.md) describes reservations of future operations, which are recorded
alongside the ledger without being written to the history tables.
