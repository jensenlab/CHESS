"""
    abstract type InstrumentFormat end

Dispatch tag for a specific instrument export format (e.g. an `Epoch2` plate-reader export, a
`BioSpa` incubator export). Every concrete format is a singleton `struct` subtyping this and
implements two extension-point functions:

- `detect(::Type{T}, path::AbstractString) -> Bool`: sniff-test whether `path` looks like a `T`
  export, used by [`detect_format`](@ref) for auto-detection.
- `parse_raw(::Type{T}, path::AbstractString; kwargs...) -> Vector{LabwareRead}`: parse `path` into
  the package's canonical [`LabwareRead`](@ref) representation, one per (plate, channel) found in
  the file.

Register a new format with [`register_format!`](@ref) so it participates in both auto-detection and
name-based lookup (see [`parse_instrument_file`](@ref)).
"""
abstract type InstrumentFormat end

"""
    detect(::Type{T}, path::AbstractString) where T<:InstrumentFormat -> Bool

Return `true` if the file at `path` looks like a `T` export. Every concrete [`InstrumentFormat`](@ref)
must implement this method; there is no fallback.
"""
function detect end

"""
    parse_raw(::Type{T}, path::AbstractString; kwargs...) where T<:InstrumentFormat -> Vector{LabwareRead}

Parse the file at `path`, known to be a `T` export, into one [`LabwareRead`](@ref) per (plate,
channel) found in it. Every concrete [`InstrumentFormat`](@ref) must implement this method; there is
no fallback.
"""
function parse_raw end

"""
    struct LabwareRead
        metadata::Dict{String,Any}
        data::DataFrame
    end

The canonical, instrument-agnostic result of parsing one *channel* of one *plate* from an instrument
export file -- a channel being one specific measurement configuration (e.g. absorbance at a given
wavelength, or fluorescence at a given excitation/emission pair). A single export file commonly
contains multiple plates and/or multiple channels per plate; [`parse_raw`](@ref)/
[`parse_instrument_file`](@ref) return a `Vector{LabwareRead}`, one per (plate, channel) combination,
rather than trying to force everything into one wide table. This is the seam that keeps the rest of
the package (DataFrame/CHESS-object/JSON conversion) generic regardless of the instrument.

Fields:
- `metadata`: everything that's constant for this one (plate, channel) -- at minimum
  `metadata["format"]` (the `InstrumentFormat` subtype that produced it), `metadata["plate"]`, and
  `metadata["read_kind"]` (e.g. `"Absorbance"`/`"Fluorescence"`, matching an already-registered
  `CHESSCore.ReadKind` name), plus whatever else the format exposes (instrument serial, protocol
  name, export datetime, a channel's wavelength or excitation/emission, ...).
- `data`: a tidy `DataFrame` with exactly three columns -- `well::String`, `time::DateTime`,
  `value::Float64` -- one row per well per timepoint (a single row for an endpoint/non-kinetic read).

See also: [`DataFrame(::LabwareRead)`](@ref), [`record_reads!`](@ref), [`labwareread_to_json`](@ref).
"""
struct LabwareRead
    metadata::Dict{String,Any}
    data::DataFrame
end
