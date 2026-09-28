# Parsing Instrument Files

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSParsers` turns lab-instrument export files -- plate-reader spreadsheets, incubator session
logs, and similar -- into forms the rest of CHESS already knows how to use: a tidy `DataFrame`,
[`Read`](@ref)s recorded directly onto a [`Labware`](@ref), or JSON. It's a separate package from
`CHESS` (not re-exported by it, so `using CHESSParsers` on its own), designed so a new instrument
export shape can be supported by adding a new format rather than changing anything already working.

## The `InstrumentFormat` interface

Every concrete instrument format is a singleton `struct` subtyping [`InstrumentFormat`](@ref) and
implements two methods:

```julia
struct ExFormat <: InstrumentFormat end

CHESSParsers.detect(::Type{ExFormat}, path::AbstractString) = endswith(path, ".ex")

function CHESSParsers.parse_raw(::Type{ExFormat}, path::AbstractString; kwargs...)
    # ... read `path`, return a Vector{LabwareRead} or Vector{EnvironmentLog}
end
```

`detect` sniff-tests whether a file looks like that format's export; `parse_raw` does the actual
parsing. Registering the format with [`register_format!`](@ref) makes it discoverable by
auto-detection and by name:

```julia
register_format!(ExFormat; name="ex_format")
```

## `LabwareRead` and `EnvironmentLog`

Parsing returns a `Vector` of one of two result types, depending on whether the data has a well to
attach to:

- [`LabwareRead`](@ref) -- one per **(plate, channel)** found in the file, a channel being one
  specific measurement configuration (e.g. absorbance at a given wavelength). `data` is exactly
  `well`/`time`/`value`; everything constant for that one (plate, channel) -- instrument, plate id,
  `read_kind`, wavelength -- lives once in `metadata` instead of being repeated on every row.
- [`EnvironmentLog`](@ref) -- one per **reading kind**, for chamber-level data with no well at all
  (an incubator's temperature/CO2/humidity history). `data` is exactly `time`/`value`.

Both share the same two-field shape (`metadata::Dict{String,Any}`, `data::DataFrame`), so the
`DataFrame`/JSON conversions below work identically for either.

## Parsing a file

[`parse_instrument_file`](@ref) either auto-detects the format or uses one passed explicitly. The
examples here parse the de-identified sample exports in CHESSParsers' test suite:

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

CHESSParsers' built-in formats:

| Format | Produces | Covers |
|---|---|---|
| `Epoch2Format` | `LabwareRead` | BioTek Epoch 2 plate-reader `.xlsx` exports |
| `SynergyFormat` | `LabwareRead` | BioTek Synergy plate-reader `.xlsx` exports |
| `CytationFormat` | `LabwareRead` | BioTek Cytation plate-reader `.xlsx` exports |
| `BioSpaFormat` | `EnvironmentLog` | BioTek/Agilent BioSpa incubator `.SES` session logs |
| `Take3TrioFormat` | `LabwareRead` | BioTek Take3 Trio nucleic-acid quant `.xlsx` exports |

The three plate-reader formats share one underlying Gen5 `.xlsx` parsing engine (they're
distinguished only by the file's own `Reader Type:` field) that handles endpoint, kinetic, and
spectrum-scan reads, single- or multi-plate, single- or multi-channel workbooks alike.

## Getting data out

`DataFrame(lr)` (or `DataFrame(el)`) returns the tidy measurement table directly. `DataFrame` comes
from DataFrames.jl, which CHESSParsers does not re-export:

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
every row of a `LabwareRead` onto a `Labware` as a [`Read`](@ref), via [`record_read!`](@ref) (see
[Reads & Instrument Measurements](reads.md) for the underlying single-read mechanics) -- `well_map`
converts a row's `well` value to the well name used on `labware`, for when the instrument's own
well-naming convention differs. It also accepts a `Vector{LabwareRead}` directly, recording every
element against the same `labware`:

```jldoctest parsing
julia> plate = build_location(loc"WP96");

julia> record_reads!(plate, lrs);

julia> reads(plate["A1"])
1-element Vector{Read}:
 1.04 OD
```

`record_reads!` is provided by CHESSParsers' `CHESSCore` package extension, not CHESSParsers itself
-- `CHESSCore` is a weak dependency, so parsing a file never requires it, but recording the result
onto a `Labware` does. `using CHESSCore` (alongside whatever registers the `ReadKind`s involved, e.g.
`using CHESSLabConstants`) activates it.

`labwareread_to_json`/`json_to_labwareread` (and their `environmentlog_to_json`/
`json_to_environmentlog` counterparts) round-trip a result through a plain JSON string, for handing
data to tools outside Julia entirely.

## Adding a new instrument format

A new format lives in its own file under `CHESSParsers/src/instruments/`, implementing `detect` and
`parse_raw` as shown above and calling `register_format!` once at the bottom. See the package's own
[`CHESSParsers/README.md`](https://github.com/jensenlab/CHESS/blob/main/CHESSParsers/README.md) for
the full contributor workflow -- how to work from a real, private export file, de-identify it into a
committed regression fixture, and add tests -- and the [API Reference](../api/parsers.md) for the
complete function list.
