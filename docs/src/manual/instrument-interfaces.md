# Instrument Interfaces

```@meta
DocTestSetup = :(using CHESS)
```

[Reads & Instrument Measurements](reads.md) describes the capability check, which `CHESSCore`
performs in memory with no persistence. This page describes how `CHESSDatabase` records which
instrument performed a persisted operation.

## Package responsibilities

`CHESSCore` owns instrument capability, meaning `performable_operations` and the check that uses it.
It has no concept of a database, an `InstrumentID` column, or a ledger. `CHESSDatabase` has no
capability logic. It never checks `performable_operations`. It records which instrument performed
an operation, in the `InstrumentID` and `InstrumentTime` columns of `Transfers`, `Movements`,
`EnvironmentAttributes`, and `Reads`.

## The instrument argument

[`upload`](@ref) takes `fun, args...; instrument=...` and is where the two packages meet. The same
`instrument` value is used twice in one call, for two unrelated purposes:

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

`fun(args...; instrument=instrument)` runs the `CHESSCore` operation, which checks capability. If
the instrument cannot perform `fun`, the call throws `ArgumentError`. The in-memory change and the
database write are one step (see [Committing & Uploading](committing-uploading.md)), so nothing is
written and no `InstrumentID` is recorded. Separately, `upload` computes `location_id(instrument)`
and passes it to the matching `upload_*` function, which writes the row.

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

The check covers only `performable_operations`. The `readable_types` field is descriptive and is
not enforced (see [Reads & Instrument Measurements](reads.md)), so a capable instrument can record
any registered `ReadKind`. `Epoch2` lists only `:Absorbance` and `:Fluorescence`, but it can still
record a free-text note:

```jldoctest instruments
julia> upload(record_read!, well, read"Fluorescence"(50u"RFU"); instrument=reader)
3

julia> @read ReaderNote
ReadKind(ReaderNote)

julia> upload(record_read!, well, ReaderNote("condensation on lid"); instrument=reader)
4
```

## Instrument settings

[`get_instrument_settings`](@ref) takes `instrument_id, sequence_id=..., time=...`. It is unrelated
to capability. It returns the configuration of one instrument, which changes over time, as
free-text `Setting` and `Value` pairs such as `"Gain"` and `"2.0"`. Each setting holds its latest
value, like an `Attribute` and unlike the accumulating history of `Read`s:

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

`performable_operations`, `actuatable_attributes`, and `readable_types` are fixed capability data
on a `LocationKind`. Only the first is checked at call time, and none is persisted as changing
state. `InstrumentSettings` is the opposite: it is persisted in ledger order and has no capability
meaning.

[Interop](interop.md) describes the formats that `CHESSCore` uses to exchange `Location` and
`Stock` data with tools outside CHESS.
