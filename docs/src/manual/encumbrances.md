# Encumbrances

```@meta
DocTestSetup = :(using CHESS)
```

An encumbrance is a non-binding reservation of a future operation. It records that a transfer,
movement, or attribute change is planned without writing it to the history tables described in
[Database Architecture](db-architecture.md).

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

The pair `(ExperimentID, Name)` is unique, so a protocol has a stable identity within its
experiment. Each protocol also has an enforcement flag that is stamped with a ledger entry, so
enforcement can be switched on and off over time.

## Encumbering an operation

An encumbrance has no type of its own. It is an integer `Encumbrances.ID` that ties a `ProtocolID`
to one row in an operation-specific table: `EncumberedTransfers`, `EncumberedMovements`,
`EncumberedEnvironments`, `EncumberedLocks`, or `EncumberedActivity`.

`encumber` takes `protocol_id, fun, args...`. It runs the `CHESSCore` operation immediately in
memory and then records the reservation in the matching table. The operation is not deferred or
simulated:

```jldoctest encumbrances
julia> enc_move1 = encumber(p_id, move_into!, bench, plate1)
1

julia> print(parent(plate1))  # moved in memory already
Bench

julia> print(parent(reconstruct_location(CHESSCore.location_id(plate1))))  # not in the database
Lab
```

Non-binding refers to the database only: nothing is written to `Movements`, `Transfers`,
`EnvironmentAttributes`, or the other history tables. The in-memory objects change immediately, and
nothing reverses that change automatically. A movement encumbrance that passes a trailing `true`
to lock the location does lock it in memory:

```jldoctest encumbrances
julia> enc_move2 = encumber(p_id, move_into!, bench, plate2, true)
2

julia> is_locked(plate2)
true

julia> unlock!(plate2);  # reversing the in-memory lock is manual
```

## Completing an encumbrance

Performing the real operation later does not mark the encumbrance complete. A separate call links
the two. Here the real move is uploaded from a reconstruction, because `plate1` in memory has
already been moved:

```jldoctest encumbrances
julia> move_id = upload(move_into!, bench, reconstruct_location(CHESSCore.location_id(plate1)));

julia> CHESSDatabase.upload_encumbrance_completion(enc_move1, move_id)
```

Nothing ties the real operation to the encumbrance automatically. An encumbrance can be marked
complete without the operation having been performed, and the operation can be performed without
completing the encumbrance. Encumbrances record intent, and the caller links them to the ledger.

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

- `get_all_encumbrances(protocol_id)` lists every encumbrance ID in a protocol.
- `get_encumbrance_completion(encumbrance_ids)` reports whether each is linked to a ledger entry.
- `get_all_protocols` and `get_protocol_status` summarize at the protocol level, giving the number
  of completed encumbrances against the total.

[`get_last_protocol_id`](@ref) returns the ID of the most recently created protocol of an
experiment, and [`get_last_encumbrance_id`](@ref) returns the ID of the most recently created
encumbrance of a protocol:

```jldoctest encumbrances
julia> get_last_protocol_id(exp_id)
1

julia> get_last_encumbrance_id(p_id)
2
```

## Caching encumbered state

[`encumber_cache`](@ref) stores a snapshot of the state of a location under an encumbrance. It is the
encumbrance counterpart of `cache` (see [Caching & Repair](caching-repair.md)) and is used by
reconstructions that include planned operations. It takes the encumbrance ID and the location:

```jldoctest encumbrances
julia> encumber_cache(enc_move2, plate2)
```

[Instrument Interfaces](instrument-interfaces.md) describes how the capability check and the
recording of the instrument are divided between the two packages.
