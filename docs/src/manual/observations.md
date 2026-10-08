# Observations

```@meta
DocTestSetup = :(using CHESS)
```

Most operations describe how the state of the lab changed: a transfer moves material, a movement
changes a parent. An observation states what the state is, whatever the history predicted. It makes
no claim about how the state came about. Observations record state that is known only by looking at
it, such as the contents of a bottle when it is first entered, or a measured volume that differs from
the volume that the transfers predict.

## Observing in memory

[`observe!`](@ref) is the in-memory operation. It has one form for each kind of fact:

- `observe!(well, component, quantity)` states that a component is present in a well at exactly that
  quantity, and every other component is unchanged. A zero quantity states that it is absent.
- `observe!(location, attribute)` states the own attribute of a location. A `missing` value states
  that the location has no value of its own and takes its parent's.
- `observe!(child, parent)` states that a child is in a parent, or nowhere when the parent is
  `nothing`. This moves the child like `move_into!` and ignores a lock on the child. Occupancy rules
  still apply.
- `observe!(location, facet, value)` states a scalar fact. The facet is `:cost`, `:locked`, or
  `:active`.

## Recording an observation

[`observe`](@ref) records an observation in the database and returns its ledger ID. It takes the same
facts as `observe!` and updates the location in memory as well. With no fact, it observes all of the
location as it is in memory: every component, its cost, its own attributes, its parent, and its lock
and activity. The keyword `recursive` also observes everything inside the location, and everything
shares one ledger entry. `upload(observe!, ...)` records a single observation like any other
operation (see [Committing & Uploading](committing-uploading.md)).

The examples use a new database with one plate and a transfer of 50 µL from well A1 to well A2:

```jldoctest observations
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> plate = generate_location(loc"WP96", "Plate 1");

julia> observe(plate["A1"], rgt"water", 200u"µL")
2

julia> upload(transfer!, plate["A1"], plate["A2"], 50u"µL");

julia> a2 = CHESSCore.location_id(plate["A2"]);

julia> stock(reconstruct_location(a2))
50.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  50.0 μL          100 %
```

The first observation put 200 µL of water into well A1 and no operation produced it. Later
operations replay on top of an observation, so the transfer moved 50 µL from it.

## Comparing observations with history

[`observation_discrepancies`](@ref) compares every observation of a list of locations with what the
history predicted just before it, and returns the differences as a `DataFrame`. The columns are
`LedgerID`, `SequenceID`, `LocationID`, `Facet` (`"component"`, `"cost"`, `"attribute"`, `"parent"`,
`"locked"`, or `"active"`), `Key` (the component or attribute, or `missing`), `Predicted`, and
`Observed`. An attribute is compared with the effective environment of the location, so a value that
it inherits counts as predicted. A parent is reported as a location ID, or `missing` for none.

Here well A2 is observed with 45 µL after the transfer predicted 50 µL:

```jldoctest observations
julia> observe(plate["A2"], rgt"water", 45u"µL");

julia> observation_discrepancies([a2])
1×7 DataFrame
 Row │ LedgerID  SequenceID  LocationID  Facet      Key    Predicted  Observed
     │ Int64     Int64       Int64       String     Any    Any        Any
─────┼─────────────────────────────────────────────────────────────────────────
   1 │        4           4          10  component  water  50.0 μL    45.0 μL
```

## Older databases

[`backfill_observations`](@ref) is a one-off migration for a database written before observations
existed, in which some state is known only from a cache, for example the contents of a bottle that were
cached when it was committed. It walks every cache in sequence order and compares it with what the
ledger alone predicts at that point. Wherever they differ, it records the cached state as
observations on a new ledger entry inserted after the cache and repairs the caches that follow.
Afterward every cache can be recomputed from the ledger. Labware membership is structural and stays
with the caches: which labware a well belongs to, and the grid of slots inside a labware. The function
returns the number of ledger entries that it added.
