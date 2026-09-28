# Committing & Uploading

```@meta
DocTestSetup = :(using CHESS)
```

[`build_location`](@ref) (`CHESSCore`) builds a `Location` entirely in memory -- no database calls
are made, and it has no `location_id`. `CHESSDatabase` adds the other half: functions that turn an
in-memory location real, and functions that persist an operation performed on one.

## The uncommitted/committed boundary

[`generate_location`](@ref) (`kind, name=..., child_namer=...`) is `build_location`'s
database-connected counterpart -- it connects location-creation directly to the database, so every
location it builds already has a real, database-assigned ID, and the tree it returns is already
committed, in one step. The examples on this page use a new, empty database:

```jldoctest committing
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> room = generate_location(loc"Room", "Room A");

julia> CHESSCore.location_id(room)
1
```

[`commit_location!(loc)`](@ref) does the same for a location that was already built with
`build_location`. It returns a **new** committed `Location` -- `loc` itself is left unchanged,
because `location_id`/`name`/`kind` are immutable fields on every concrete `Location` subtype:

```jldoctest committing
julia> eph_root = build_location(loc"Room", "merge test room");

julia> eph_plate = build_location(loc"WP96", "merge test plate");

julia> move_into!(eph_root, eph_plate)

julia> committed = commit_location!(eph_root);

julia> CHESSCore.is_committed(committed)
true

julia> CHESSCore.is_committed(eph_root)
false
```

[`release_location(loc)`](@ref) is the inverse: builds an uncommitted copy, stripping every
`location_id` in the subtree, without touching the database. It exists for merging subtrees
reconstructed from different databases -- `release_location` each piece to strip its source IDs,
recombine in memory with `build_location`/`move_into!`, then `commit_location!` the merged result
against the target database.

## `upload`: the write path

[`upload`](@ref) (`fun, args...; instrument=nothing`) is the entry point for persisting an operation.
It runs `fun` (the in-memory `CHESSCore` change) and then the matching database write as one step:
if either fails, neither happens. It returns the ledger ID of the new entry:

```jldoctest committing
julia> upload(set_attribute!, room, attr"Temperature"(21u"°C"))
3
```

`upload` first checks that every argument is already committed (`CHESSCore.assert_all_committed`) --
uploading a change to an uncommitted location fails before anything is written, including before a
`Ledger` row is allocated, so no stray, incomplete entry is left behind by that failure.

[`upload_operation`](@ref CHESSDatabase.upload_operation) (`fun`) is the lookup `upload` uses to find the right database-writing function
for each operation: `move_into! -> upload_movement`, `transfer! -> upload_transfer`, `set_attribute! ->
upload_environment_attribute`, `record_read! -> upload_read`, plus `lock!`/`unlock!`/
`toggle_lock!`/`activate!`/`deactivate!`/`toggle_activity!` -> `upload_lock`/`upload_activity`, and
`assign_barcode! -> update_barcode`, and `observe! -> upload_observation`.

## `update`: amending history

`update` (`fun, args...; ledger_id=...`) is the counterpart used with
[`replace_ledger`](@ref)/[`insert_ledger`](@ref) (from [The Ledger](ledger.md)) instead of the
default `append_ledger()` -- it amends an existing point in history rather than appending a new one.
After running `fun` and its persistence call, `update` also triggers `process_update`, which
validates the edit and repairs any caches it invalidates -- covered in full in
[Caching & Repair](caching-repair.md).

For example, recording a 50 µL transfer and then correcting it to 20 µL:

```jldoctest committing
julia> plate = build_location(loc"WP96", "Plate 1");

julia> deposit!(plate["A1"], 200u"µL" * rgt"water")

julia> plate = commit_location!(plate);

julia> ledger_id = upload(transfer!, plate["A1"], plate["A2"], 50u"µL");

julia> update(transfer!, plate["A1"], plate["A2"], 20u"µL"; ledger_id=replace_ledger(get_sequence_id(ledger_id)));
caches updated: 0

julia> stock(reconstruct_location(CHESSCore.location_id(plate["A2"])))
0.02 mL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.02 mL        100.0 %
```

`update` runs `fun` on the objects passed to it, just like `upload`, so after amending history those
in-memory objects hold both transfers (70 µL in A2). The database holds the corrected history;
reconstruct from it, as above, to see the amended state.

[Reconstruction](reconstruction.md) covers the other direction: building a `Location` back out of
everything committed and uploaded so far.
