"""
    struct SynergyFormat <: InstrumentFormat end

Gen5 .xlsx export format for the BioTek Synergy plate reader (e.g. Synergy H1). See
[`InstrumentFormat`](@ref) and [`_parse_gen5_workbook`](@ref) (shared by every Gen5-family format).
"""
struct SynergyFormat <: InstrumentFormat end

detect(::Type{SynergyFormat}, path::AbstractString) =
    occursin(r"^Synergy"i, something(_gen5_reader_type(path), ""))

parse_raw(::Type{SynergyFormat}, path::AbstractString; kwargs...) = _parse_gen5_workbook(SynergyFormat, path)

register_format!(SynergyFormat; name="synergy")
