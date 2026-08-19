"""
    group_solvers

Predefined group-assignment solvers for [`schedule_uniform_controls`](@ref).
Maps a solver name to a function `(n::Int, capacity::Int; kwargs...) -> Vector{Int}`.
"""
const group_solvers = Dict(
    "greedy" => assign_groups_greedy,
    "MILP" => assign_groups_MILP,
)

"""
    default_control_id_factory(group_index::Int, role::Symbol, replicate_index::Int) -> Symbol

Default `control_id_factory` for [`schedule_uniform_controls`](@ref). Produces
a readable, debuggable `Symbol` of the form `role_gGROUP_REPLICATE`, e.g.
`:positive_g1_1`, `:positive_g1_2`, `:negative_g3_1`.

`group_index` is the group's 1-based position in the canonical, contiguously
renumbered group ordering used by [`schedule_uniform_controls`](@ref), not
necessarily any raw id returned by the underlying group-assignment solver.
`replicate_index` ranges over `1:role_counts[role]` within that group/role.
"""
default_control_id_factory(group_index::Int, role::Symbol, replicate_index::Int) =
    Symbol("$(role)_g$(group_index)_$(replicate_index)")

"""
    schedule_uniform_controls(runs::Vector{R}, role_counts, cap::Int;
                               solver::String="greedy",
                               control_id_factory::Function=default_control_id_factory,
                               kwargs...) where {R} -> ControlMap{R,C}

Build a brand-new `ControlMap` implementing "uniform shared controls"
scheduling: partition `runs` into groups capped at `cap` total nodes each
(matching [`n_nodes`](@ref)/[`component_sizes`](@ref)), and within each group
create `sum(values(role_counts))` new control nodes (counts given per role,
e.g. `Dict(:positive=>1, :negative=>1)`) linked to *every* run in that group
(dense bipartite within the group).

Controls are never shared across groups, so each resulting group is
automatically its own connected component -- recover the grouping later via
[`components`](@ref)/[`component_sizes`](@ref); no extra metadata is stored
on the map for this purpose.

# Arguments
- `runs`: flat list of run node ids to schedule. Duplicates are not
  deduplicated -- pass a `Vector` with the identity/multiplicity you intend.
- `role_counts`: number of controls to create per role, e.g.
  `Dict(:positive=>1, :negative=>1)`. Keys may be `Symbol` or
  `AbstractString` (canonicalized to `Symbol`, matching [`link!`](@ref));
  must be non-empty with strictly positive values.
- `cap`: maximum total node count (runs + controls) of any resulting
  group/component. Must exceed `sum(values(role_counts))`.

# Keyword Arguments
- `solver`: group-assignment algorithm, `"greedy"` (default) or `"MILP"`.
  For the homogeneous/unweighted runs handled here both are exact and
  produce the same number of groups; MILP is provided as an extensible
  scaffold rather than a better answer -- see [`assign_groups_MILP`](@ref).
- `control_id_factory`: `(group_index::Int, role::Symbol, replicate_index::Int) -> C`
  called once per control node to create; defaults to
  [`default_control_id_factory`](@ref).
- `kwargs...`: forwarded to the chosen solver (e.g. `optimizer`, `timelimit`
  for `"MILP"`).

See also: [`group_solvers`](@ref), [`components`](@ref).
"""
function schedule_uniform_controls(runs::Vector{R}, role_counts::AbstractDict, cap::Int;
                                    solver::String="greedy",
                                    control_id_factory::Function=default_control_id_factory,
                                    kwargs...) where {R}
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

    group_capacity = cap - C_count
    group_capacity >= 1 || throw(ArgumentError(
        "cap ($cap) must exceed the total controls per group ($C_count); got group_capacity = $group_capacity"))

    if isempty(runs)
        return ControlMap{R,Any}()
    end

    solver_fun = group_solvers[solver]
    raw_groups = solver_fun(length(runs), group_capacity; kwargs...)

    group_ids = sort(unique(raw_groups))
    group_index_of = Dict(g => i for (i, g) in enumerate(group_ids))

    first_role = sorted_roles[1][1]
    cached_first_id = control_id_factory(1, first_role, 1)
    C = typeof(cached_first_id)

    map = ControlMap{R,C}()

    for g in group_ids
        gi = group_index_of[g]
        group_runs = [runs[i] for i in eachindex(runs) if raw_groups[i] == g]
        for (role, count) in sorted_roles
            for rep in 1:count
                cid = (gi == 1 && role == first_role && rep == 1) ? cached_first_id : control_id_factory(gi, role, rep)
                for r in group_runs
                    link!(map, r, cid, role)
                end
            end
        end
    end

    return map
end
