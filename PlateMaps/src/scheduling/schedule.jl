const control_solvers = Dict(
    "exchange" => _exchange_solve,
    "MILP" => _milp_solve,
)

"""
    _schedule_single_plate(wells, edges, fixed_nodes; solver, run_restarts, run_iterations, rng, kwargs...)
        -> PlateMap

Two-stage single-plate scheduler: fix `fixed_nodes`' positions first (via [`place_runs`](@ref), clustering
edge-connected groups of them together), then place every other node referenced by `edges` around them,
minimizing (or maximizing) the chosen objective. [`schedule_platemap`](@ref) is the public entry point;
this is the per-plate primitive it calls once per plate a multi-plate schedule needs.

This two-stage shape is what makes an exact solver viable: `PlateArrays`' old MILP solver was tractable
specifically because run positions were fixed before it ran; an earlier, fully-joint design of this
package (every node placed simultaneously) made exact solving intractable even at modest scale.
"""
function _schedule_single_plate(wells::BitMatrix,edges,fixed_nodes;solver::String="exchange",
        run_restarts::Int=10,run_iterations::Int=1000,rng::AbstractRNG=Random.default_rng(),kwargs...)
    haskey(control_solvers,solver) || throw(ArgumentError("solver must be one of $(collect(keys(control_solvers)))"))
    ns = collect(edge_nodes(edges))
    T = isempty(ns) ? Any : mapreduce(typeof,typejoin,ns)

    fixed_pos = place_runs(wells,fixed_nodes,edges;restarts=run_restarts,iterations=run_iterations,rng=rng)
    solver_fun = control_solvers[solver]
    full_pos = solver_fun(wells,edges,fixed_pos;rng=rng,kwargs...)

    occupant = Matrix{Union{Missing,T}}(missing,size(wells))
    for (n,I) in full_pos
        occupant[I] = n
    end
    return PlateMap{T}(wells,occupant)
end

"""
    schedule_platemap(wells::BitMatrix, edges, fixed_nodes; plate_solver::String="greedy",
                       solver::String="exchange", run_restarts::Int=10, run_iterations::Int=1000,
                       rng::AbstractRNG=Random.default_rng(), kwargs...) -> Vector{PlateMap}

Schedule `edges`/`fixed_nodes` across one or more identically-shaped `wells` plates. Edge-connected
components (see [`components`](@ref)) are atomic -- each one lands wholly on a single plate, never split
-- so the first stage is a bin-packing problem (which components share which plate, minimizing plate
count), and the second stage is [`_schedule_single_plate`](@ref)'s existing two-stage placement, run once
per plate on that plate's subset of `edges`/`fixed_nodes`.

Returns one `PlateMap` per plate actually used (never zero -- an entirely empty `edges`/`fixed_nodes`
input still returns a 1-element vector holding one empty `PlateMap`).

# Arguments
- `wells`: active-well mask, shared by every plate (this package doesn't support heterogeneous plate
  shapes in one call).
- `edges`: an iterable of `(node1,node2,role,metadata)`-shaped `NamedTuple`s (see [`mkedge`](@ref)).
- `fixed_nodes`: the nodes to place first on their plate, before any optimization (typically "runs").

# Keyword Arguments
- `plate_solver`: `"greedy"` (default, first-fit-decreasing, exact for uniform component sizes) or
  `"MILP"` (exact minimum plate count) -- see [`plate_solvers`](@ref)/[`_plate_assign_greedy`](@ref)/
  [`_plate_assign_MILP`](@ref). Throws `ArgumentError` if any single component is larger than one plate's
  active-well count.
- `solver`: `"exchange"` (default, heuristic, supports every `objective`) or `"MILP"` (exact,
  `objective=:distance` only -- see [`_milp_solve`](@ref)'s docstring for why, and its bipartite
  requirement on `edges`).
- `run_restarts`/`run_iterations`/`rng`: passed to [`place_runs`](@ref) to fix `fixed_nodes`' positions
  on each plate (kept separate from the control solver's own `restarts`/`iterations` below).
- other keywords (`objective`, `minimize`, `restarts`, `iterations`, `lambda`, `timelimit`, `optimizer`,
  ...) are forwarded to the chosen `solver` (and, for `plate_solver="MILP"`, to `_plate_assign_MILP` too --
  `optimizer`/`timelimit` are shared across both MILP stages when both are selected).
"""
function schedule_platemap(wells::BitMatrix,edges,fixed_nodes;plate_solver::String="greedy",kwargs...)
    haskey(plate_solvers,plate_solver) || throw(ArgumentError("plate_solver must be one of $(collect(keys(plate_solvers)))"))

    groups = _component_groups(edges,fixed_nodes)
    isempty(groups) && return PlateMap[_schedule_single_plate(wells,edges,fixed_nodes;kwargs...)]

    weights = length.(groups)
    capacity = sum(wells)
    raw_groups = plate_solvers[plate_solver](weights,capacity;kwargs...)
    group_ids = sort(unique(raw_groups))

    plates = PlateMap[]
    for g in group_ids
        node_set = union((groups[i] for i in eachindex(groups) if raw_groups[i]==g)...)
        plate_edges = [e for e in edges if e.node1 in node_set && e.node2 in node_set]
        plate_fixed = [n for n in fixed_nodes if n in node_set]
        push!(plates,_schedule_single_plate(wells,plate_edges,plate_fixed;kwargs...))
    end
    return plates
end
