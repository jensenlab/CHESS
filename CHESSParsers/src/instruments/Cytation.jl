"""
    struct CytationFormat <: InstrumentFormat end

Gen5 .xlsx export format for the BioTek Cytation plate reader/imager (e.g. Cytation5, Cytation10,
CytationC10). See [`InstrumentFormat`](@ref) and [`_parse_gen5_workbook`](@ref) (shared by every
Gen5-family format).
"""
struct CytationFormat <: InstrumentFormat end

detect(::Type{CytationFormat}, path::AbstractString) =
    occursin(r"^Cytation"i, something(_gen5_reader_type(path), ""))

parse_raw(::Type{CytationFormat}, path::AbstractString; kwargs...) = _parse_gen5_workbook(CytationFormat, path)

register_format!(CytationFormat; name="cytation")
