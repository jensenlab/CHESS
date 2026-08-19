module ControlMaps

using DataFrames, JSON, JuMP, Gurobi

import DataFrames: DataFrame

include("types.jl")
include("mutation.jl")
include("query.jl")
include("components.jl")
include("scheduling/defaults.jl")
include("scheduling/greedy.jl")
include("scheduling/MILP.jl")
include("scheduling/uniform_controls.jl")
include("dataframe_interface.jl")
include("json_interface.jl")

# types.jl
export ControlMap
# mutation.jl
export add_run!, add_control!, link!, unlink!, remove_run!, remove_control!, set_metadata!
# query.jl
export controls, runs, control_types, roles, has_run, has_control, has_link, edge_metadata, edges,
       n_runs, n_controls, n_edges
# components.jl
export components, n_components, n_nodes, component_sizes
# scheduling/
export schedule_uniform_controls, group_solvers, default_control_id_factory
# dataframe_interface.jl
export DataFrame
# json_interface.jl
export controlmap_to_json, json_to_controlmap, write_json, read_controlmap_json

end # module ControlMaps
