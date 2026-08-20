module RunMaps

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
include("scheduling/duplicates.jl")
include("scheduling/pooled_controls.jl")
include("dataframe_interface.jl")
include("json_interface.jl")

# types.jl
export RunMap
# mutation.jl
export add_run!, link!, unlink!, remove_run!, set_metadata!
# query.jl
export linked_runs, linking_runs, runs, relation_types, roles, has_run, has_link, edge_metadata, edges,
       n_runs, n_edges
# components.jl
export components, n_components, n_nodes, component_sizes
# scheduling/
export schedule_uniform_controls, group_solvers, default_linked_run_id_factory,
       schedule_duplicates, default_duplicate_id_factory, schedule_controls!
# dataframe_interface.jl
export DataFrame
# json_interface.jl
export runmap_to_json, json_to_runmap, write_json, read_runmap_json

end # module RunMaps
