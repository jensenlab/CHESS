# Parsing Instrument Files

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSParsers` converts lab-instrument export files, such as plate-reader spreadsheets and
incubator session logs, into forms the rest of CHESS uses: a tidy `DataFrame`, [`Read`](@ref)s
recorded onto a [`Labware`](@ref), or JSON. It is a separate package that `CHESS` does not
re-export, so it is loaded on its own. A new export shape is supported by adding a format, without
changing existing ones.

## The `InstrumentFormat` interface

Every instrument format is a singleton type that subtypes [`InstrumentFormat`](@ref) and implements
two methods:

```julia
struct ExFormat <: InstrumentFormat end

CHESSParsers.detect(::Type{ExFormat}, path::AbstractString) = endswith(path, ".ex")

function CHESSParsers.parse_raw(::Type{ExFormat}, path::AbstractString; kwargs...)
    # ... read `path`, return a Vector{LabwareRead} or Vector{EnvironmentLog}
end
```

`detect` tests whether a file looks like the format's export, and `parse_raw` parses it.
[`register_format!`](@ref) registers the format so that it can be found by auto-detection and by
name. [`format_registry`](@ref) holds the registered formats, keyed by name, and
`keys(format_registry)` lists them:

```julia
register_format!(ExFormat; name="ex_format")
```

## `LabwareRead` and `EnvironmentLog`

Parsing returns a vector of one of two result types, depending on whether the data has a well to
attach to:

- [`LabwareRead`](@ref): one per **plate and channel** found in the file. A channel is one
  measurement configuration, such as absorbance at a given wavelength. The `data` table has the
  columns `well`, `time`, and `value`. Everything constant for the plate and channel (instrument,
  plate id, `read_kind`, wavelength) is stored once in `metadata` and not repeated on every row.
- [`EnvironmentLog`](@ref): one per **reading kind**, for chamber-level data with no well, such as
  an incubator's temperature, CO2, and humidity history. The `data` table has the columns `time`
  and `value`.

Both have the same two fields, `metadata::Dict{String,Any}` and `data::DataFrame`, so the
conversions to `DataFrame` and JSON below work for either.

## Parsing a file

[`parse_instrument_file`](@ref) detects the format or uses one passed explicitly. The examples
parse the de-identified sample exports in the CHESSParsers test suite:

```jldoctest parsing
julia> using CHESSParsers

julia> fixtures = joinpath(pkgdir(CHESSParsers), "test", "fixtures");

julia> lrs = parse_instrument_file(joinpath(fixtures, "single_plate_single_read.xlsx"));

julia> lrs[1].metadata["read_kind"], lrs[1].metadata["wavelength"]
("Absorbance", 600)

julia> els = parse_instrument_file(joinpath(fixtures, "biospa_environment_log.SES"));

julia> [el.metadata["read_kind"] for el in els]
4-element Vector{String}:
 "Temperature"
 "O2"
 "CO2"
 "Humidity"
```

[`detect_format`](@ref) shows which format auto-detection picks. To skip detection, pass the format
by its registered name or its type:

```jldoctest parsing
julia> detect_format(joinpath(fixtures, "single_plate_single_read.xlsx"))
Epoch2Format

julia> lrs = parse_instrument_file(joinpath(fixtures, "single_plate_single_read.xlsx"); format="epoch2");

julia> lrs = parse_instrument_file(joinpath(fixtures, "single_plate_single_read.xlsx"); format=Epoch2Format);
```

CHESSParsers includes these formats:

| Format | Produces | Covers |
|---|---|---|
| `Epoch2Format` | `LabwareRead` | BioTek Epoch 2 plate-reader `.xlsx` exports |
| `SynergyFormat` | `LabwareRead` | BioTek Synergy plate-reader `.xlsx` exports |
| `CytationFormat` | `LabwareRead` | BioTek Cytation plate-reader `.xlsx` exports |
| `BioSpaFormat` | `EnvironmentLog` | BioTek/Agilent BioSpa incubator `.SES` session logs |
| `Take3TrioFormat` | `LabwareRead` | BioTek Take3 Trio nucleic-acid quant `.xlsx` exports |

The names of the registered formats:

```jldoctest parsing
julia> sort(collect(keys(format_registry)))
5-element Vector{String}:
 "biospa"
 "cytation"
 "epoch2"
 "synergy"
 "take3trio"
```

The three plate-reader formats share one Gen5 `.xlsx` parsing engine and are distinguished only by
the file's `Reader Type:` field. The engine handles endpoint, kinetic, and spectrum-scan reads, in
workbooks with one or several plates and channels.

## Getting data out

Calling `DataFrame` on a `LabwareRead` or `EnvironmentLog` returns the tidy measurement table.
`DataFrame` comes from DataFrames.jl, which CHESSParsers does not re-export:

```jldoctest parsing
julia> using DataFrames

julia> first(DataFrame(lrs[1]), 3)
3×3 DataFrame
 Row │ well    time                 value
     │ String  DateTime             Float64
─────┼──────────────────────────────────────
   1 │ A1      2020-01-01T09:00:00    1.036
   2 │ A2      2020-01-01T09:00:00    0.227
   3 │ A3      2020-01-01T09:00:00    0.273
```

[`record_reads!(labware, lr; well_map=identity, instrument=nothing, layout=nothing)`](@ref) records
every row of a `LabwareRead` onto a `Labware` as a [`Read`](@ref), using [`record_read!`](@ref)
(see [Reads & Instrument Measurements](reads.md)). `well_map` converts a row's `well` value to the
well name used on `labware`, for instruments whose well names differ. It also accepts a
`Vector{LabwareRead}` and records every element against the same `labware`:

```jldoctest parsing
julia> plate = build_location(loc"WP96");

julia> record_reads!(plate, lrs);

julia> reads(plate["A1"])
1-element Vector{Read}:
 1.04 OD
```

`record_reads!` comes from a CHESSParsers package extension that depends on `CHESSCore`. Parsing a
file does not need `CHESSCore`, but recording the result onto a `Labware` does. Loading `CHESSCore`
activates the extension, together with whatever registers the `ReadKind`s involved, such as
`CHESSLabConstants`.

`labwareread_to_json` and `json_to_labwareread`, and the matching `environmentlog_to_json` and
`json_to_environmentlog`, convert a result to a JSON string and back, for handing data to tools
outside Julia.

## Adding a new instrument format

A new format goes in its own file under `CHESSParsers/src/instruments/`. The file implements
`detect` and `parse_raw` as shown above and calls `register_format!` once at the end. The
[CHESSParsers README](https://github.com/jensenlab/CHESS/blob/main/CHESSParsers/README.md)
describes the contributor workflow: working from a private export file, de-identifying it into a
committed regression fixture, and adding tests. The [API Reference](../api/parsers.md) lists every
function.
