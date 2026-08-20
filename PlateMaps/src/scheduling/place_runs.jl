"""
    place_runs(wells::BitMatrix, run_nodes, edges; restarts::Int=10, iterations::Int=1000,
               rng::AbstractRNG=Random.default_rng()) -> Dict{Any,CartesianIndex{2}}

Fix run-node positions before control placement, minimizing [`run_compactness`](@ref) -- edge-connected
groups of runs are clustered together (via the same restart/local-move search [`schedule_platemap`](@ref)
uses for control placement) so that a run's specific linked control isn't left stranded far from it.
Runs with no edges, or whose whole component has no other run member, are unconstrained by the objective
and land wherever the initial random draw puts them.

# Keyword Arguments
- `restarts`/`iterations`: search effort, independent of the control solver's own `restarts`/`iterations`.
- `rng`: random number generator used for the initial placement and every search move.
"""
function place_runs(wells::BitMatrix,run_nodes,edges;restarts::Int=10,iterations::Int=1000,
        rng::AbstractRNG=Random.default_rng())
    ns = collect(run_nodes)
    well_idxs = findall(wells)
    length(ns) <= length(well_idxs) || throw(ArgumentError("more run nodes ($(length(ns))) than active wells ($(length(well_idxs)))"))
    isempty(ns) && return Dict{Any,CartesianIndex{2}}()
    score = pos -> run_compactness(pos,edges,ns)
    pos,_ = _local_search(wells,ns,well_idxs,Dict{Any,CartesianIndex{2}}(),score,true,restarts,iterations,rng)
    return pos
end
