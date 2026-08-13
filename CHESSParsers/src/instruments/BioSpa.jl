"""
    struct BioSpaFormat <: InstrumentFormat end

Export format for the BioTek/Agilent BioSpa automated incubator's `.SES` session file. See
[`InstrumentFormat`](@ref).

Not yet implemented. A `.SES` is a chamber-level environmental log (temperature/O2/CO2/humidity over
time, plus a plate slot/barcode mapping) rather than a per-well plate read, so it doesn't fit
[`LabwareRead`](@ref)'s well/read_kind/value shape -- it needs its own result type (closer to
`CHESSCore.set_attribute!` over time) before it can be implemented.
"""
struct BioSpaFormat <: InstrumentFormat end

detect(::Type{BioSpaFormat}, path::AbstractString) = false # detection not yet implemented -- see docstring

parse_raw(::Type{BioSpaFormat}, path::AbstractString; kwargs...) =
    error("BioSpa parsing not yet implemented -- its .SES data doesn't fit LabwareRead, see the BioSpaFormat docstring")

register_format!(BioSpaFormat; name="biospa")
