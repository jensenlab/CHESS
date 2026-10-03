# Reconstruction

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSDatabase` does not store the current state of the lab. It stores the history of operations
and rebuilds any state by replaying it. [`reconstruct_location(location_id,
sequence_id=get_last_sequence_id(), time=now(), max_cache=sequence_id; encumbrances=false)`](@ref)
rebuilds a location. The examples use a new database holding one plate, with a transfer between two
of its wells:

```jldoctest reconstruction
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> plate = build_location(loc"WP96", "Plate 1");

julia> deposit!(plate["A1"], 200u"µL" * rgt"water")

julia> committed = commit_location!(plate);

julia> transfer_id = upload(transfer!, committed["A1"], committed["A2"], 50u"µL");

julia> preview = reconstruct_location(CHESSCore.location_id(committed));

julia> CHESSCore.location_id(preview) == CHESSCore.location_id(committed)
true
```

Every call builds a new, independent object graph that shares nothing with any live object. This
makes reconstruction the way to preview a hypothetical change to a persisted location without side
effects, as `build_location` does for locations that do not exist yet:

```jldoctest reconstruction
julia> real_well = committed["A1"];

julia> preview = reconstruct_location(CHESSCore.location_id(real_well));

julia> original_stock = stock(real_well);

julia> drain!(preview)

julia> stock(real_well) == original_stock
true
```

Passing an earlier `sequence_id` reconstructs the state at that point in the history. Well A2 held
nothing before the transfer:

```jldoctest reconstruction
julia> a2 = CHESSCore.location_id(committed["A2"]);

julia> stock(reconstruct_location(a2))
50.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  50.0 μL          100 %

julia> stock(reconstruct_location(a2, get_sequence_id(transfer_id) - 1))
Empty Stock
```

## Caches and replay

Each sub-reconstruction (`reconstruct_parent`, `reconstruct_children`, `reconstruct_attributes`,
`reconstruct_contents`, `reconstruct_lock`, and `reconstruct_activity`) works the same way. It finds
the most recent usable snapshot at or before `max_cache` and replays only the history recorded after
that snapshot, up to `sequence_id`. `max_cache` defaults to `sequence_id` and can be set lower.
[Caching & Repair](caching-repair.md) uses this to reconstruct a value as if a given snapshot did
not exist.

Each sub-reconstruction has a mutating form whose name ends in `!`: `reconstruct_parent!`,
`reconstruct_children!`, `reconstruct_attributes!`, `reconstruct_contents!`,
`reconstruct_lock!`, and `reconstruct_environment!`. These set that part of the state of locations
that already exist, with the same arguments as the form without `!`, and they accept a vector of
locations. [`get_location_info`](@ref) returns the name of a committed location and a function that
builds a bare location of the right kind, with no parent, children, or contents. The two together
rebuild one part of a location:

```jldoctest reconstruction
julia> name, constructor = get_location_info(a2);

julia> well = constructor(a2, name);

julia> stock(well)
Empty Stock

julia> reconstruct_contents!(well);

julia> stock(well)
50.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  50.0 μL          100 %
```

`reconstruct_location!` runs these in one pass: the environment first (the parent chain and its
attributes), then children, contents, lock, activity, and reads.

## Environment

`reconstruct_environment` differs from the other reconstructions. It does not rebuild only one
location's own attributes. It walks the full ancestor chain one generation at a time, collecting
every location of a generation in one query, until it reaches the root. It then reconstructs the
attributes of the whole ancestor set in one batch and sets each node's parent reference to the
ancestor already collected. The result is a connected chain that `environment(loc)` can use to
resolve inheritance.

## Reads

Reads accumulate and never supersede each other, so they have no cache. `get_reads` queries the
`Reads` table directly, and `reconstruct_reads!` converts each row according to what it stores:

- If `row.Value` is missing, the read is `missing`, meaning no result.
- If `row.Unit` is missing, the read is the raw string, which is a qualitative read.
- Otherwise, the read is `parse(Float64, row.Value) * Unitful.uparse(row.Unit)`, a quantitative
  read.

Rows are sorted by `InstrumentTime`, or by the upload `Time` when the instrument reported none.
This is the ordering that makes `reads(loc, kind)` a time series (see
[Reads & Instrument Measurements](reads.md)).

## Labware children

`fetch_child_cache` raises an error if no child-set cache exists for a `Labware`. The children of a
`Labware` form a grid of fixed shape that cannot be derived from `Movements` alone, so a cache of
its children is required, unlike for other locations.

## Contents

`reconstruct_contents` is the most involved reconstruction, because the current stock of a well can
depend on transfers made several steps before any cached snapshot. It proceeds in three steps:

1. It fetches the content cache of each requested well, or starts from `Empty()` with zero cost if
   none exists.
2. It finds the earliest cached snapshot among the requested wells. It then searches `Transfers`,
   and `EncumberedTransfers` when `encumbrances=true`, for every transfer that could have
   contributed material to any requested well, however many transfers back that goes.
3. It replays those transfers in the order they happened, working on a temporary copy of each well
   involved. The copies have no parent and no children, and are never part of a connected lab.

[Caching & Repair](caching-repair.md) describes how the caches stay correct as the history is
amended.
