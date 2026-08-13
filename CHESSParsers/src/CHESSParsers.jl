module CHESSParsers

using
    CHESSCore, # Labware/Location/Read/record_read! and the read_kinds registry
    CHESSLabConstants, # registers the Absorbance/Fluorescence ReadKinds instrument reads use
    DataFrames, # LabwareRead's tabular payload
    JSON, # JSON interface
    JSONTables, # DataFrame <-> JSON table interop
    Dates, # instrument read timestamps
    XLSX # reading BioTek Gen5 .xlsx exports

include("types.jl")
include("registry.jl")

include("instruments/gen5.jl")
include("instruments/Epoch2.jl")
include("instruments/Synergy.jl")
include("instruments/Cytation.jl")
include("instruments/BioSpa.jl")

include("dataframe_interface.jl")
include("chess_interface.jl")
include("json_interface.jl")

export InstrumentFormat, LabwareRead, detect, parse_raw # generic interface
export format_registry, register_format!, detect_format, parse_instrument_file # dispatch
export Epoch2Format, SynergyFormat, CytationFormat # built-in Gen5 (BioTek) plate-reader formats
export BioSpaFormat # not yet implemented -- see src/instruments/BioSpa.jl
export record_reads! # CHESS-object interface
export labwareread_to_json, json_to_labwareread # JSON interface

end # module CHESSParsers
