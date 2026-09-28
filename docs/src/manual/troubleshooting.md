# Troubleshooting

The errors CHESS raises most often, what triggers each one, and where the concept behind it is
covered in detail.

## Locations and movement

### `LockedLocationError`

Thrown by [`move_into!`](@ref) when the location being moved is [`is_locked`](@ref). Locked
locations cannot be moved from their current parent, though their own children can still be moved.
See [Movement & Occupancy](movement.md) for the full set of move-refusal reasons.

### `AlreadyLocatedInError`

Thrown by [`move_into!`](@ref) when the location being moved is already inside the target parent.
See [Movement & Occupancy](movement.md).

### `OccupancyError`

Thrown by [`move_into!`](@ref) when the move would exceed the parent's remaining capacity, per its
[`occupancy`](@ref)/[`occupancy_cost`](@ref) accounting. See [Movement & Occupancy](movement.md)
for how occupancy cost is computed.

### `AmbiguousOccupancyRuleError`

Thrown by [`occupancy_cost`](@ref) when more than one category-based rule matches a parent/child
pair and no exact rule decides between them. Register an exact rule for that pair with
[`set_occupancy_cost!`](@ref). See [Movement & Occupancy](movement.md).

### `FixedMembershipError`

Thrown when trying to add or remove a slot from a `Labware`'s fixed internal structure, or move a
`Well` independently of its `Labware` -- both are permanently fixed at construction. See
[Locations](core-concepts.md) for the generic-vs-fixed distinction between `GenericLocation` and
`Labware`/`Well`, and [Movement & Occupancy](movement.md) for how it applies to `move_into!`.

### `ChildNotFoundError` and `AmbiguousChildNameError`

Thrown when looking up a child by name, as in `plate["Z9"]`, finds no child with that name, or
finds more than one:

```
Child Not Found Error: no child of Plate 1 named Z9
```

Check the names with [`children`](@ref). Give siblings distinct names to avoid the ambiguous case.

## Stocks and wells

### `WellCapacityError`

Thrown by [`deposit!`](@ref) and [`transfer!`](@ref) when the result would exceed the well's
capacity:

```
Well Capacity Error: 1000 mL is greater than the well's capacity (400 μL)
```

Capacity comes from the well's `LocationKind`; see
[Wells: Depositing & Transferring Material](wells.md).

### `MixingError`

Thrown by `Stock` subtraction (`-`) when the result would leave a reagent at a negative quantity.
See [Stocks](stocks.md) for `Stock` arithmetic.

## Registered names

### "could not be found in lab modules"

A string-macro lookup such as `loc"..."`, `rgt"..."`, or `org"..."` found no constant by that name:

```
ArgumentError: Symbol Nonexistent could not be found in lab modules Module[CHESSCore, CHESSLabConstants]
```

The error suggests close matches when there are any. Lookups only search CHESS and registered lab
modules, so a constant registered in your own session is used through its binding (`DemoPlate`),
not `loc"DemoPlate"`. A lab module must be registered with `CHESSCore.register_lab` and loaded
with `using` where the lookup runs. See [Registering Lab Constants](registering-lab-constants.md).

### "already exists"

[`@location_kind`](@ref), [`@attribute`](@ref), [`@read`](@ref), and [`@stock`](@ref) refuse to
register a name twice:

```
ArgumentError: LocationKind Room already exists
```

`using CHESS` already registers many common names, such as `Room` and `WP96`. Use the registered
constant, or pick a new name. `@reagent`, `@chemical`, and `@organism` do not check, and silently
replace an existing registration. See [Registering Lab Constants](registering-lab-constants.md).

## Databases

### "use connect_SQLite to connect to a database"

A `CHESSDatabase` function ran before any database was connected. Call
[`connect_SQLite`](@ref) with the database path first, or [`create_db`](@ref) and then
`connect_SQLite` for a new database. See [Database Architecture](db-architecture.md).

### `UncommittedLocationError`

Thrown by [`upload`](@ref) when a location involved has never been committed to the database:

```
Uncommitted Location Error: Room A has no location_id and has not been committed. See commit_location!.
```

Build the location with [`generate_location`](@ref), or commit an in-memory one with
[`commit_location!`](@ref) and use the location it returns. Nothing is written to the database
when this error is thrown. See [Committing & Uploading](committing-uploading.md).

### "does not exist yet -- use append_ledger or insert_ledger"

[`replace_ledger`](@ref) was given a sequence ID past the end of the ledger. Only an existing entry
can be replaced; use [`append_ledger`](@ref) to add a new one at the end, or
[`insert_ledger`](@ref) to add one in the middle. See [The Ledger](ledger.md).

### "the new operation is not the same type of operation as the previous one"

[`update`](@ref) with [`replace_ledger`](@ref) must replace an operation with the same kind of
operation, such as a transfer with a transfer. To change what kind of operation happened at that
point, see [The Ledger](ledger.md) for inserting a new entry instead.

### Errors from `update` that name a well or stock

After amending history, `update` replays everything that happened afterward to check that the
history is still possible. If the correction makes a later step impossible, such as a transfer out
of a well that would now be empty, the replay throws the same error that step would throw on its
own (for example `WellCapacityError` or `MixingError`). See [Caching & Repair](caching-repair.md).

!!! warning "A failed `update` still changes the ledger"
    `replace_ledger` and `insert_ledger` add their ledger row as soon as they are called, before
    `update` runs, and that row is not removed if `update` then fails. After a failed
    `update(...; ledger_id=replace_ledger(s))`, the slot `s` has a newer, empty revision, so
    reconstructions no longer see the operation that was there. The in-memory objects passed to
    `update` have also already been changed. There is currently no supported way to restore the
    slot afterward, so check that a correction is the same kind of operation, and still possible,
    before calling `update`.

## Installation and environment

### Julia version

CHESS needs Julia 1.12 or later: its packages are tied together as a Pkg workspace, which older
versions do not support. Check with `versioninfo()`.

### `Pkg.add(url=...)` doesn't work

CHESS must be used from a local clone. Its packages find each other through the workspace's local
paths, which Pkg does not carry over to a project that adds CHESS by URL. Clone the repository and
run `Pkg.instantiate()` in it; see [Installation](../index.md#Installation).

### "does not have X in its dependencies" after pulling changes

A package gained a dependency since your local environment was last resolved. Manifest files are
not committed, so resolve again in the environment you are using, for example:

```julia
using Pkg
Pkg.activate("docs")   # or "Pourfecto/docs", "PlateMaps/docs", ...
Pkg.resolve()
```

### Solver licenses

Pourfecto's default optimizer, and `RunMaps`' `solver = "MILP"` option, use Gurobi, which needs a
license (free for academic use). Pourfecto can use a free solver through its `optimizer` keyword;
see the [Pourfecto documentation](https://jensenlab.github.io/CHESS/pourfecto/dev/).
