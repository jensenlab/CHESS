"""
    _exchange_solve(wells, edges, fixed_pos; objective=:hybrid, minimize=true, restarts=10, iterations=1000,
                     lambda=0.5, rng=Random.default_rng(), kwargs...) -> Dict{Any,CartesianIndex{2}}

Heuristic local-search solver: place every node referenced by `edges` that isn't already in `fixed_pos`
(i.e. every control node, with run nodes already fixed by [`place_runs`](@ref)) onto `wells`'s remaining
active wells, minimizing (or maximizing) the chosen objective. Returns the *full* position dict
(`fixed_pos` merged with the placed controls) -- the internal counterpart `MILP`'s `_milp_solve` mirrors;
[`schedule_platemap`](@ref) is the public entry point that calls one of these via `solver=`. Accepts and
ignores extra `kwargs` (e.g. `optimizer`/`timelimit`, meant for `plate_solver="MILP"`), since
`schedule_platemap` forwards one shared keyword bag to both the plate solver and this control solver.
"""
function _exchange_solve(wells::BitMatrix,edges,fixed_pos::AbstractDict;objective::Symbol=:hybrid,minimize::Bool=true,
        restarts::Int=10,iterations::Int=1000,lambda=0.5,rng::AbstractRNG=Random.default_rng(),kwargs...)
    objective in (:distance,:evenness,:hybrid) || throw(ArgumentError("objective must be :distance, :evenness, or :hybrid"))
    all_nodes = collect(edge_nodes(edges))
    control_nodes = collect(setdiff(all_nodes,keys(fixed_pos)))
    well_idxs = findall(wells)
    free_wells = collect(setdiff(well_idxs,values(fixed_pos)))
    length(control_nodes) <= length(free_wells) || throw(ArgumentError(
        "more control nodes ($(length(control_nodes))) than free active wells ($(length(free_wells)))"))

    lb_dist,ub_dist,lb_even,ub_even = 0.0,1.0,0.0,1.0
    if objective == :hybrid
        _,lb_dist = _local_search(wells,control_nodes,free_wells,fixed_pos,pos->total_distance(pos,edges),true,max(1,restarts),iterations,rng)
        _,ub_dist = _local_search(wells,control_nodes,free_wells,fixed_pos,pos->total_distance(pos,edges),false,max(1,restarts),iterations,rng)
        _,lb_even = _local_search(wells,control_nodes,free_wells,fixed_pos,pos->total_evenness(wells,pos,edges),true,max(1,restarts),iterations,rng)
        _,ub_even = _local_search(wells,control_nodes,free_wells,fixed_pos,pos->total_evenness(wells,pos,edges),false,max(1,restarts),iterations,rng)
    end
    score = if objective == :distance
        pos -> total_distance(pos,edges)
    elseif objective == :evenness
        pos -> total_evenness(wells,pos,edges)
    else
        pos -> hybrid(wells,pos,edges;lambda=lambda,lb_dist=Float64(lb_dist),ub_dist=Float64(ub_dist),
                       lb_even=Float64(lb_even),ub_even=Float64(ub_even))
    end

    cpos,_ = _local_search(wells,control_nodes,free_wells,fixed_pos,score,minimize,restarts,iterations,rng)
    return merge(fixed_pos,cpos === nothing ? Dict{Any,CartesianIndex{2}}() : cpos)
end
