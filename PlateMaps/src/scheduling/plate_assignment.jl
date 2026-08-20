"""
    _component_groups(edges, fixed_nodes) -> Vector{Set}

The atomic node-groups a multi-plate schedule must never split: every edge-connected component of
`edges` (see [`components`](@ref)), plus a singleton `Set` for any `fixed_nodes` entry not already
covered by one (a fixed node with no edges at all is still its own atomic unit of size 1).
"""
function _component_groups(edges,fixed_nodes)
    comps = components(edges)
    covered = Set{Any}()
    for c in comps
        union!(covered,c)
    end
    groups = Vector{Set{Any}}(comps)
    for n in fixed_nodes
        n in covered && continue
        push!(groups,Set{Any}([n]))
        push!(covered,n)
    end
    return groups
end

"""
    _plate_assign_greedy(weights::Vector{Int}, capacity::Int; kwargs...) -> Vector{Int}

Partition items (given by `weights`, e.g. atomic-component sizes) into groups (plates) whose total weight
never exceeds `capacity`, using first-fit-decreasing (FFD): sort items by weight descending, place each
into the first group with enough remaining capacity, opening a new group otherwise. Exact optimal group
count for uniform weights; a good heuristic (not guaranteed exact) for mixed weights -- see
[`_plate_assign_MILP`](@ref) for an exact alternative. Throws `ArgumentError` if any weight exceeds
`capacity` (a component that can never fit on any plate). Accepts and ignores extra `kwargs` so it is
interchangeable with [`_plate_assign_MILP`](@ref) behind [`plate_solvers`](@ref).
"""
function _plate_assign_greedy(weights::Vector{Int},capacity::Int;kwargs...)
    isempty(weights) && return Int[]
    maximum(weights) <= capacity || throw(ArgumentError(
        "a component's size ($(maximum(weights))) exceeds plate capacity ($capacity): cannot fit on any plate"))

    n = length(weights)
    order = sortperm(weights;rev=true)
    bin_remaining = Int[]
    groups = Vector{Int}(undef,n)

    for i in order
        w = weights[i]
        placed = false
        for (b,rem) in enumerate(bin_remaining)
            if rem >= w
                bin_remaining[b] -= w
                groups[i] = b
                placed = true
                break
            end
        end
        if !placed
            push!(bin_remaining,capacity-w)
            groups[i] = length(bin_remaining)
        end
    end

    return groups
end

"""
    _plate_assign_MILP(weights::Vector{Int}, capacity::Int; optimizer=_default_optimizer[], timelimit=100) -> Vector{Int}

MILP formulation of the same weighted plate-assignment problem as [`_plate_assign_greedy`](@ref):
partition items into the minimum number of plates whose total weight never exceeds `capacity`. Exact
(given enough time) for general/mixed weights, unlike the greedy heuristic. The candidate plate count `G`
is sized from running greedy first as a valid upper bound. Throws `ArgumentError` if any weight exceeds
`capacity`. Accepts and ignores extra `kwargs` (e.g. the control solver's `objective`/`restarts`/...),
same as [`_plate_assign_greedy`](@ref), since [`schedule_platemap`](@ref) forwards one shared keyword bag
to both the plate solver and the control solver.
"""
function _plate_assign_MILP(weights::Vector{Int},capacity::Int;optimizer=_default_optimizer[],timelimit=100,kwargs...)
    isempty(weights) && return Int[]
    maximum(weights) <= capacity || throw(ArgumentError(
        "a component's size ($(maximum(weights))) exceeds plate capacity ($capacity): cannot fit on any plate"))

    n = length(weights)
    G = length(unique(_plate_assign_greedy(weights,capacity))) # warm upper bound

    model = Model(optimizer)
    set_time_limit_sec(model,Float64(timelimit))

    @variable(model,assign[1:n,1:G],Bin)
    @variable(model,used[1:G],Bin)

    for i in 1:n
        @constraint(model,sum(assign[i,g] for g in 1:G)==1)
    end
    for g in 1:G
        @constraint(model,sum(weights[i]*assign[i,g] for i in 1:n)<=capacity*used[g])
    end
    for g in 1:(G-1)
        @constraint(model,used[g]>=used[g+1])
    end

    @objective(model,Min,sum(used))
    optimize!(model)

    groups = Vector{Int}(undef,n)
    for i in 1:n
        for g in 1:G
            if round(Int,JuMP.value(assign[i,g])) == 1
                groups[i] = g
                break
            end
        end
    end
    return groups
end

"""
    plate_solvers

Maps a `plate_solver` string to the function that implements it: `"greedy"` =>
[`_plate_assign_greedy`](@ref), `"MILP"` => [`_plate_assign_MILP`](@ref). Selected via
[`schedule_platemap`](@ref)'s `plate_solver` keyword.
"""
const plate_solvers = Dict(
    "greedy" => _plate_assign_greedy,
    "MILP" => _plate_assign_MILP,
)
