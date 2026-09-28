# Encumbrances

```@meta
DocTestSetup = :(using CHESS)
```

An encumbrance is a non-binding, future-dated reservation of an operation -- a way to say "this
transfer/movement/attribute-change is planned" without writing it into the canonical history tables
covered in [Database Architecture](db-architecture.md).

## Protocols

A **Protocol** is a named, experiment-scoped group of encumbrances. The examples use a new database
with a lab holding a bench and two plates, and one experiment:

```jldoctest encumbrances
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> lab = generate_location(loc"Lab", "Lab");

julia> bench = generate_location(loc"Bench", "Bench");

julia> plate1 = generate_location(loc"WP96", "Plate 1");

julia> plate2 = generate_location(loc"WP96", "Plate 2");

julia> for x in (bench, plate1, plate2); upload(move_into!, lab, x); end

julia> exp_id = upload_experiment("demo experiment", "docs")
1

julia> p_id = upload_protocol(exp_id, "move plates to bench")
1
```

`(ExperimentID, Name)` is unique -- a protocol has a stable identity within an experiment. Each
protocol also carries its own ledger-timestamped enforcement flag, so enforcement can be toggled
over time rather than being a fixed property.

## Encumbering an operation

There is no `Encumbrance` struct -- an encumbrance is a row identity: an `Int` `Encumbrances.ID`
tying a `ProtocolID` to one row in an operation-specific `Encumbered*` table (`EncumberedTransfers`,
`EncumberedMovements`, `EncumberedEnvironments`, `EncumberedLocks`, `EncumberedActivity`).

`encumber` (`protocol_id, fun, args...`) has a mechanism worth stating plainly: it runs the raw
`CHESSCore` mutation **immediately, in-memory**, then records the reservation into the matching
`Encumbered*` table. Nothing about this is deferred or simulated:

```jldoctest encumbrances
julia> enc_move1 = encumber(p_id, move_into!, bench, plate1)
1

julia> print(parent(plate1))  # moved in memory already
Bench

julia> print(parent(reconstruct_location(CHESSCore.location_id(plate1))))  # not in the database
Lab
```

"Non-binding" describes the *database* side only -- nothing is written to `Movements`/`Transfers`/
`EnvironmentAttributes`/etc. The in-memory object graph really is mutated right away, and nothing in
the encumbrance machinery undoes that automatically. A movement encumbrance that also passes a
trailing `lock=true` really does lock the location in memory:

```jldoctest encumbrances
julia> enc_move2 = encumber(p_id, move_into!, bench, plate2, true)
2

julia> is_locked(plate2)
true

julia> unlock!(plate2);  # reversing the in-memory lock manually, nothing does this for you
```

## Completing an encumbrance is a separate, manual step

Performing the real operation later does **not**, by itself, mark an encumbrance complete. Linking
the two is an explicit call. Here the real move is uploaded from a fresh reconstruction, since
`plate1` in memory has already been moved:

```jldoctest encumbrances
julia> move_id = upload(move_into!, bench, reconstruct_location(CHESSCore.location_id(plate1)));

julia> CHESSDatabase.upload_encumbrance_completion(enc_move1, move_id)
```

Nothing automatically ties "the real operation happened" to "this encumbrance is complete" -- an
encumbrance can be marked complete without the corresponding real operation ever having been
performed, or vice versa. Encumbrances model *intent*; closing the loop back to the ledger is the
caller's responsibility.

## Status queries

```jldoctest encumbrances
julia> CHESSDatabase.get_all_encumbrances(p_id)
2-element Vector{Int64}:
 1
 2

julia> CHESSDatabase.get_encumbrance_status(p_id)
2×4 DataFrame
 Row │ EncumbranceID  Operation  LedgerID  IsComplete
     │ Int64          String     Integer?  Bool?
─────┼────────────────────────────────────────────────
   1 │             1  Movement          6        true
   2 │             2  Movement    missing       false
```

`get_all_encumbrances(protocol_id)` lists every encumbrance ID in a protocol.
`get_encumbrance_completion(encumbrance_ids)` reports whether each is linked to a ledger entry.
`get_all_protocols`/`get_protocol_status` summarize at the protocol level -- how many of a
protocol's encumbrances have been completed versus its total.

[Instrument Interfaces](instrument-interfaces.md) covers the last topic in this group: how an
instrument's in-memory capability check and its database attribution are split across the two
packages.
