# Committing & Uploading

```@meta
DocTestSetup = :(using CHESS)
```

[`build_location`](@ref) from `CHESSCore` builds a `Location` in memory. It makes no database calls
and the location has no `location_id`. `CHESSDatabase` provides functions that commit a location to
the database and functions that persist operations performed on it.

## Committed and uncommitted locations

[`generate_location`](@ref) takes `kind, name=..., child_namer=...`. It is the database counterpart
of `build_location`: every location it builds gets an ID from the database, and the tree it returns
is committed in one step. The examples on this page use a new, empty database:

```jldoctest committing
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> room = generate_location(loc"Room", "Room A");

julia> CHESSCore.location_id(room)
1
```

[`commit_location!(loc)`](@ref) commits a location that was already built with `build_location`.
It returns a new committed `Location` and leaves `loc` unchanged, because `location_id`, `name`,
and `kind` are immutable fields of every `Location` subtype:

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

[`release_location(loc)`](@ref) is the inverse. It builds an uncommitted copy of the tree with every
`location_id` removed, without touching the database. It is used to merge subtrees reconstructed
from different databases: release each piece to remove its source IDs, combine the pieces in memory
with `build_location` and `move_into!`, and commit the merged result to the target database.

## Uploading an operation

[`upload`](@ref) takes `fun, args...; instrument=nothing` and persists an operation. It runs `fun`,
the in-memory `CHESSCore` change, and then the matching database write as one step. If either
fails, neither takes effect. It returns the ledger ID of the new entry:

```jldoctest committing
julia> upload(set_attribute!, room, attr"Temperature"(21u"°C"))
3
```

`upload` first checks that every argument is committed with `CHESSCore.assert_all_committed`.
Uploading a change to an uncommitted location fails before anything is written, including the
`Ledger` row, so a failure leaves no incomplete entry.

[`upload_operation`](@ref CHESSDatabase.upload_operation) takes `fun` and returns the function that
writes that operation to the database:

| Operation | Database function |
|---|---|
| `move_into!` | `upload_movement` |
| `transfer!` | `upload_transfer` |
| `set_attribute!` | `upload_environment_attribute` |
| `record_read!` | `upload_read` |
| `lock!`, `unlock!`, `toggle_lock!` | `upload_lock` |
| `activate!`, `deactivate!`, `toggle_activity!` | `upload_activity` |
| `assign_barcode!` | `update_barcode` |
| `observe!` | `upload_observation` |

## Amending history

[`update`](@ref) takes `fun, args...; replace=s` or `insert=s`. It amends a point in the history
instead of appending a new entry. With `replace=s`, it records a new revision of the entry at
sequence ID `s`. With `insert=s`, it adds an entry there and moves later entries back (see
[The Ledger](ledger.md)). After running `fun` and writing it to the database, `update` validates the
edit and repairs the caches that the edit invalidates (see [Caching & Repair](caching-repair.md)).
All of this happens in one SQL transaction, so a failed `update` leaves the database unchanged.

For example, recording a 50 µL transfer and then correcting it to 20 µL:

```jldoctest committing
julia> plate = build_location(loc"WP96", "Plate 1");

julia> deposit!(plate["A1"], 200u"µL" * rgt"water")

julia> plate = commit_location!(plate);

julia> ledger_id = upload(transfer!, plate["A1"], plate["A2"], 50u"µL");

julia> update(transfer!, plate["A1"], plate["A2"], 20u"µL"; replace=get_sequence_id(ledger_id));
caches updated: 0

julia> stock(reconstruct_location(CHESSCore.location_id(plate["A2"])))
20.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  20.0 μL          100 %
```

Like `upload`, `update` runs `fun` on the objects passed to it, so after the amendment those
in-memory objects hold both transfers, 70 µL in A2. The database holds the corrected history.
Reconstructing from it, as above, gives the amended state.

[Reconstruction](reconstruction.md) describes building a `Location` back from the committed history.
