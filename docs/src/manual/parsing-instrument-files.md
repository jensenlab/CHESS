# Parsing Instrument Files

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

[`parse_instrument_file`](@ref) either auto-detects the format or uses one passed explicitly:

```julia
lrs = parse_instrument_file("plate_read.xlsx")             # auto-detected -> Vector{LabwareRead}
els = parse_instrument_file("session.SES")                 # auto-detected -> Vector{EnvironmentLog}
lrs = parse_instrument_file("plate_read.xlsx"; format="epoch2")
lrs = parse_instrument_file("plate_read.xlsx"; format=Epoch2Format)
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

`DataFrame(lr)` (or `DataFrame(el)`) returns the tidy measurement table directly.

[`record_reads!(labware, lr; well_map=identity, instrument=nothing)`](@ref) records every row of a
`LabwareRead` onto a `Labware` as a [`Read`](@ref), via [`record_read!`](@ref) (see
[Reads & Instrument Measurements](reads.md) for the underlying single-read mechanics) -- `well_map`
converts a row's `well` value to the well name used on `labware`, for when the instrument's own
well-naming convention differs. It also accepts a `Vector{LabwareRead}` directly, recording every
element against the same `labware`:

```julia
plate = build_location(loc"WP96")
record_reads!(plate, lrs) # lrs :: Vector{LabwareRead}
```

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
