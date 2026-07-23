module CHESSLabConstants

using CHESSCore, Unitful, DataFrames, SQLite, DBInterface, HTTP, JSON

include("./pubchem.jl")
include("./chemicals/chemical_utils.jl")

include("./environments/attributes.jl")
include("./reads/reads.jl")

include("./locations/locations.jl")
include("./locations/instruments.jl")
include("./locations/occupancy_rules.jl")

include("./chemicals/solids.jl")
include("./chemicals/liquids.jl")
include("./chemicals/dissociation.jl")

include("./organisms/organism_utils.jl")
include("./organisms/organisms.jl")

include("./standard_stocks/thy.jl")
include("./standard_stocks/cdm.jl")
include("./standard_stocks/align_base_media.jl")

export get_mw_density, register_reagent!, register_organism!, register_chemical!

function __init__()
    CHESSCore.register_lab(CHESSLabConstants)
    _register_occupancy_rules!()
    _register_dissociation_rules!()
end

end # module CHESSLabConstants
