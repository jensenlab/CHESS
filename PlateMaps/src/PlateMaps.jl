module PlateMaps

using Random,
DataFrames,
JSON,
Plots,
ColorBrewer,
JuMP,
Gurobi

import Plots: plot
import DataFrames: DataFrame

include("types.jl")
include("utils.jl")
include("interface.jl")
include("scheduling/edges.jl")
include("scheduling/objectives.jl")
include("scheduling/defaults.jl")
include("scheduling/search.jl")
include("scheduling/place_runs.jl")
include("scheduling/exchange.jl")
include("scheduling/MILP.jl")
include("scheduling/plate_assignment.jl")
include("scheduling/schedule.jl")
include("interface/dataframe_interface.jl")
include("interface/json_interface.jl")
include("visualization/visualize_plate.jl")

#types.jl
export PlateMap, PlacementError, describe, wells_from_locationkind
#interface.jl
export nodes, well_position
#scheduling/edges.jl
export mkedge, edge_nodes, roles, components
#scheduling/objectives.jl
export total_distance, total_evenness, hybrid, manhattan_distance, margins, run_compactness
#scheduling/place_runs.jl
export place_runs
#scheduling/schedule.jl
export schedule_platemap, control_solvers
#scheduling/plate_assignment.jl
export plate_solvers
#interface/dataframe_interface.jl
export platemaps_from_dataframe
#interface/json_interface.jl
export platemap_to_json, json_to_platemap, platemaps_to_json, json_to_platemaps, NODE_TYPE_REGISTRY
#visualization
export plot

end # module PlateMaps
