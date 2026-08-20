function _induced_clusters(map::RunMap{N}, active_runs::Vector{N}) where {N}
    active_set = Set(active_runs)
    visited = Set{N}()
    clusters = Vector{N}[]

    for a in active_runs
        a in visited && continue
        comp = N[]
        stack = N[a]
        push!(visited, a)
        while !isempty(stack)
            n = pop!(stack)
            push!(comp, n)
            if haskey(map.forward, n)
                for nbrs in values(map.forward[n]), nb in nbrs
                    if nb in active_set && nb ∉ visited
                        push!(visited, nb)
                        push!(stack, nb)
                    end
                end
            end
            if haskey(map.backward, n)
                for nbrs in values(map.backward[n]), nb in nbrs
                    if nb in active_set && nb ∉ visited
                        push!(visited, nb)
                        push!(stack, nb)
                    end
                end
            end
        end
        push!(clusters, comp)
    end

    return clusters
end

"""
    schedule_controls!(map::RunMap, active_runs::Vector, control_pools::AbstractDict,
                        role_counts::AbstractDict, cap::Int;
                        solver::String="greedy", kwargs...) -> map

Extend `map` in place with "pooled controls" scheduling: partition
`active_runs` into groups capped at `cap` total nodes each (matching
[`n_nodes`](@ref)/[`component_sizes`](@ref)), and within each group, claim an
*exclusive* subset of each role's supplied control pool
(`control_pools[role]`, sized by `role_counts[role]`) and `link!` every run
in the group to every control claimed for that group (dense within the
group, same semantics as [`schedule_uniform_controls`](@ref)). Since linking
is dense, each group's `role_counts` values are the guaranteed *minimum*
number of controls (per role) every run in that group receives.

Controls are claimed exclusively per group (never shared across groups), so
each resulting group remains its own connected component, the same
disjoint-component property [`schedule_uniform_controls`](@ref)'s groups
have. `control_pools` itself is never mutated -- an internal cursor tracks
how much of each role's pool has been claimed.

**Cluster-aware partitioning**: nodes among `active_runs` that are already
connected via edges `map` has (e.g. `:duplicate` edges from
[`schedule_duplicates`](@ref)) are grouped as one atomic unit -- the
partitioner never splits an existing cluster across groups, so a group's
size and connected-component identity are preserved exactly as intended even
when chaining after a stage that already created edges. This is implemented
by treating each cluster's size as its weight in a weighted bin-packing
problem (see [`assign_groups_greedy`](@ref)/[`assign_groups_MILP`](@ref)).
With no prior edges among `active_runs` (the common non-chained case), every
cluster is a singleton and this reduces to the original unweighted
partitioning.

A new function alongside (not replacing) [`schedule_uniform_controls`](@ref):
this one draws controls from a caller-supplied, finite pool of existing runs
(e.g. runs meant to serve as controls) and extends an already-built map --
the mechanism that makes it possible to chain after
[`schedule_duplicates`](@ref), e.g.
`schedule_controls!(schedule_duplicates(runs, 2), ...)` (after capturing
`active_runs = runs(map)` from the duplicate stage's output).

# Arguments
- `map`: existing `RunMap` to extend, e.g. the output of
  [`schedule_duplicates`](@ref).
- `active_runs`: the runs that need controls (e.g. `runs(map)` right after
  `schedule_duplicates`, before anything else has been added).
- `control_pools`: `Dict{Symbol,Vector}` mapping role -> the pool of existing
  run ids available to serve that role.
- `role_counts`: number of controls to claim per role per group, e.g.
  `Dict(:positive=>1, :negative=>1)`. Same validation as
  `schedule_uniform_controls`: non-empty, positive values, `Symbol`/
  `AbstractString` keys canonicalized to `Symbol`, no duplicates after
  canonicalization. Every role must also have a matching key in
  `control_pools`.
- `cap`: maximum total node count (runs + controls) of any resulting
  group/component. Must exceed `sum(values(role_counts))`, and no existing
  cluster among `active_runs` may exceed `cap - sum(values(role_counts))`
  (else `ArgumentError` -- a cluster too large to fit in any group cannot be
  silently split).

# Keyword Arguments
- `solver`: group-assignment algorithm, `"greedy"` (default) or `"MILP"`.
- `kwargs...`: forwarded to the chosen solver.

Throws `ArgumentError` if any role's pool has insufficient supply for the
number of groups the partition requires. `active_runs` empty is a no-op.
"""
function schedule_controls!(map::RunMap, active_runs::Vector, control_pools::AbstractDict,
                             role_counts::AbstractDict, cap::Int;
                             solver::String="greedy", kwargs...)
    isempty(role_counts) && throw(ArgumentError("role_counts must not be empty"))
    canon = Dict{Symbol,Int}()
    for (role, count) in role_counts
        role isa Union{Symbol,AbstractString} || throw(ArgumentError("role_counts keys must be Symbol or AbstractString, got $(typeof(role))"))
        count isa Integer && count > 0 || throw(ArgumentError("role_counts values must be positive integers, got $role => $count"))
        s = Symbol(role)
        haskey(canon, s) && throw(ArgumentError("role_counts contains duplicate role after Symbol canonicalization: :$s"))
        canon[s] = count
    end
    sorted_roles = sort(collect(canon); by=first)
    C_count = sum(count for (_, count) in sorted_roles)

    for (role, _) in sorted_roles
        haskey(control_pools, role) || throw(ArgumentError("control_pools is missing role :$role required by role_counts"))
    end

    group_capacity = cap - C_count
    group_capacity >= 1 || throw(ArgumentError(
        "cap ($cap) must exceed the total controls per group ($C_count); got group_capacity = $group_capacity"))

    isempty(active_runs) && return map

    clusters = _induced_clusters(map, active_runs)
    weights = length.(clusters)
    maximum(weights) <= group_capacity || throw(ArgumentError(
        "an existing cluster of size $(maximum(weights)) exceeds group_capacity ($group_capacity); " *
        "cannot partition without splitting a group of already-linked runs"))

    solver_fun = group_solvers[solver]
    raw_groups = solver_fun(weights, group_capacity; kwargs...)

    group_ids = sort(unique(raw_groups))
    n_groups = length(group_ids)

    for (role, count) in sorted_roles
        needed = n_groups * count
        available = length(control_pools[role])
        available >= needed || throw(ArgumentError(
            "insufficient supply for role :$role: need $needed, control_pools has $available"))
    end

    cursor = Dict(role => 1 for (role, _) in sorted_roles)

    for g in group_ids
        cluster_indices = findall(==(g), raw_groups)
        group_runs = vcat((clusters[ci] for ci in cluster_indices)...)
        for (role, count) in sorted_roles
            pool = control_pools[role]
            claimed = pool[cursor[role]:(cursor[role]+count-1)]
            cursor[role] += count
            for cid in claimed
                for r in group_runs
                    link!(map, r, cid, role)
                end
            end
        end
    end

    return map
end
