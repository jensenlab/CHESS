# Instrument Interfaces

```@meta
DocTestSetup = :(using CHESS)
```

[Reads & Instrument Measurements](reads.md) covered instrument capability gating entirely within
`CHESSCore` -- `performable_operations` and `_check_capability`, checked in memory, with no notion of
persistence at all. This chapter covers the other half: how `CHESSDatabase` records *which*
instrument actually performed a persisted operation.

## A clean package boundary

`CHESSCore` owns instrument capability -- `performable_operations` and `_check_capability` -- it
has zero concept of a database, an `InstrumentID` column, or a ledger. `CHESSDatabase` owns zero capability
logic -- it never calls `_check_capability` directly, never inspects `performable_operations` -- and
owns 100% of the attribution: the `InstrumentID`/`InstrumentTime` columns on `Transfers`/
`Movements`/`EnvironmentAttributes`/`Reads`.

## One `instrument` argument, two separate uses

[`upload`](@ref) (`fun, args...; instrument=...`) is the single point where the two packages meet. The
same `instrument` value is used for two unrelated purposes, at two separate call sites, in the same
call:

```julia
function upload(fun::Function, args...; instrument=nothing, kwargs...)
    ...
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    ...
    fun(args...; instrument=instrument)   # gates capability -- inside CHESSCore
    up_fun(args...; instrument_id=instrument_id, ...)   # records attribution -- inside CHESSDatabase
    ...
end
```

`fun(args...; instrument=instrument)` runs the actual `CHESSCore` operation, which checks capability
internally via `_check_capability` -- if the instrument can't perform `fun`, this throws
`ArgumentError`, and since the in-memory change and the database write happen as one step (see
[Committing & Uploading](committing-uploading.md)), nothing is written and no `InstrumentID` is
ever recorded. Separately, `location_id(instrument)` is computed by `upload` itself and threaded
into the matching `upload_*`
call for the actual `INSERT`.

The examples use a new database with a plate, CHESS's `Epoch2` plate reader, and an `Autoclave`,
which cannot record reads:

```jldoctest instruments
julia> path = joinpath(mktempdir(), "lab.db");

julia> create_db(path);

julia> connect_SQLite(path)

julia> well = generate_location(loc"WP96", "Plate 1")["A1"];

julia> reader = generate_location(loc"Epoch2", "Reader 1");

julia> autoclave = generate_location(loc"Autoclave", "Autoclave 1");

julia> upload(record_read!, well, read"Fluorescence"(50u"RFU"); instrument=autoclave)
ERROR: ArgumentError: Autoclave 1 cannot perform record_read!
```

The gate only checks `performable_operations` -- `readable_types` is descriptive-only, not enforced
(already covered in [Reads & Instrument Measurements](reads.md)), so a capable instrument can record
any registered `ReadKind` through this same gate. `Epoch2` lists only `:Absorbance` and
`:Fluorescence`, but it can still record a free-text note:

```jldoctest instruments
julia> upload(record_read!, well, read"Fluorescence"(50u"RFU"); instrument=reader)
3

julia> @read ReaderNote
ReadKind(ReaderNote)

julia> upload(record_read!, well, ReaderNote("condensation on lid"); instrument=reader)
4
```

## Instrument settings: a different axis entirely

[`get_instrument_settings`](@ref) (`instrument_id, sequence_id=..., time=...`) is not related to
capability at all -- it's the actual time-varying configuration of one specific instrument instance
(free-text `Setting`/`Value` pairs, e.g. `"Gain"` = `"2.0"`), latest-wins per setting name, much like
an `Attribute`'s single current value rather than a `Read`'s accumulating history:

```jldoctest instruments
julia> upload_instrument_setting(reader, "Gain", 1.5);

julia> upload_instrument_setting(reader, "Gain", 2.0);

julia> get_instrument_settings(CHESSCore.location_id(reader))
1×3 DataFrame
 Row │ Setting  Value   SequenceID
     │ String   String  Int64
─────┼─────────────────────────────
   1 │ Gain     2.0              6
```

`performable_operations`/`actuatable_attributes`/`readable_types` are static capability data on a
`LocationKind`, checked (only the first) at call time and never themselves persisted as time-varying
state. `InstrumentSettings` is the reverse: real, ledger-ordered, persisted data with no capability
semantics attached.

[Interop](interop.md) covers a different topic entirely -- `CHESSCore`'s data-interchange formats for
exchanging `Location`/`Stock` data with tools outside CHESS -- not to be confused with the
package-responsibility boundary covered in this chapter.
