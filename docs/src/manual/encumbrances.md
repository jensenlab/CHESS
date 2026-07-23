# Encumbrances

An encumbrance is a non-binding, future-dated reservation of an operation -- a way to say "this
transfer/movement/attribute-change is planned" without writing it into the canonical history tables
covered in [Database Architecture](db-architecture.md).

## Protocols

A **Protocol** is a named, experiment-scoped group of encumbrances:

```julia-repl
julia> p_id = upload_protocol(exp_id, "test_protocol")
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

```julia-repl
julia> enc_move1 = encumber(p_id, move_into!, shelf1, plate1)
```

"Non-binding" describes the *database* side only -- nothing is written to `Movements`/`Transfers`/
`EnvironmentAttributes`/etc. The in-memory object graph really is mutated right away, and nothing in
the encumbrance machinery undoes that automatically. A movement encumbrance that also passes a
trailing `lock=true` really does lock the location in memory:

```julia-repl
julia> enc_move5 = encumber(p_id, move_into!, l1, plate1, true)

julia> CHESSCore.unlock!(plate1)   # reversing the in-memory lock manually, nothing does this for you
```

## Completing an encumbrance is a separate, manual step

Performing the real operation later does **not**, by itself, mark an encumbrance complete. Linking
the two is an explicit call:

```julia-repl
julia> upload_encumbrance_completion(enc_move1, get_last_ledger_id())
```

Nothing automatically ties "the real operation happened" to "this encumbrance is complete" -- an
encumbrance can be marked complete without the corresponding real operation ever having been
performed, or vice versa. Encumbrances model *intent*; closing the loop back to the ledger is the
caller's responsibility.

## Status queries

```julia-repl
julia> CHESSDatabase.get_all_encumbrances(protocol1_id)

julia> status = CHESSDatabase.get_encumbrance_status(protocol1_id)

julia> status[status.EncumbranceID .== enc_move1, :IsComplete][1]
true
```

`get_all_encumbrances(protocol_id)` lists every encumbrance ID in a protocol.
`get_encumbrance_completion(encumbrance_ids)` reports whether each is linked to a ledger entry.
`get_all_protocols`/`get_protocol_status` summarize at the protocol level -- how many of a
protocol's encumbrances have been completed versus its total.

[Instrument Interfaces](instrument-interfaces.md) covers the last topic in this group: how an
`Instrument`'s in-memory capability check and its database attribution are split across the two
packages.
