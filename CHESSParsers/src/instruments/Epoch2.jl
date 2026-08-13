"""
    struct Epoch2Format <: InstrumentFormat end

Gen5 .xlsx export format for the BioTek Epoch2 plate reader. See [`InstrumentFormat`](@ref) and
[`_parse_gen5_workbook`](@ref) (shared by every Gen5-family format).
"""
struct Epoch2Format <: InstrumentFormat end

detect(::Type{Epoch2Format}, path::AbstractString) =
    occursin(r"^Epoch\s*2"i, something(_gen5_reader_type(path), ""))

parse_raw(::Type{Epoch2Format}, path::AbstractString; kwargs...) = _parse_gen5_workbook(Epoch2Format, path)

register_format!(Epoch2Format; name="epoch2")
