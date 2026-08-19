"""
    controls(map::ControlMap, run; type=nothing) -> Vector

Controls linked to `run`, optionally filtered to one `control_type`. Returns
an empty vector if `run` is unregistered or has no matching edges (unknown
nodes are treated as having zero edges, not an error).
"""
function controls(map::ControlMap{R,C}, run; type::Union{Symbol,AbstractString,Nothing}=nothing) where {R,C}
    haskey(map.forward, run) || return C[]
    run_dict = map.forward[run]
    if type === nothing
        result = Set{C}()
        for cset in values(run_dict)
            union!(result, cset)
        end
        return collect(result)
    else
        t = Symbol(type)
        return haskey(run_dict, t) ? collect(run_dict[t]) : C[]
    end
end

"""
    controls(map::ControlMap) -> Vector

All registered control nodes.
"""
controls(map::ControlMap) = collect(map.controls)

"""
    runs(map::ControlMap, control; type=nothing) -> Vector

Runs linked to `control`, optionally filtered to one `control_type`. Returns
an empty vector if `control` is unregistered or has no matching edges.
"""
function runs(map::ControlMap{R,C}, control; type::Union{Symbol,AbstractString,Nothing}=nothing) where {R,C}
    haskey(map.backward, control) || return R[]
    control_dict = map.backward[control]
    if type === nothing
        result = Set{R}()
        for rset in values(control_dict)
            union!(result, rset)
        end
        return collect(result)
    else
        t = Symbol(type)
        return haskey(control_dict, t) ? collect(control_dict[t]) : R[]
    end
end

"""
    runs(map::ControlMap) -> Vector

All registered run nodes.
"""
runs(map::ControlMap) = collect(map.runs)

"""
    control_types(map::ControlMap, run) -> Vector{Symbol}

Distinct control types currently linked to `run`.
"""
control_types(map::ControlMap, run) = haskey(map.forward, run) ? collect(keys(map.forward[run])) : Symbol[]

"""
    roles(map::ControlMap, control) -> Vector{Symbol}

Distinct control types (roles) `control` plays, across the runs it's linked
to. Named `roles` rather than `run_types` -- runs have no type in this model;
what's being enumerated is which role(s) the control fills (positive,
negative, blank, ...).
"""
roles(map::ControlMap, control) = haskey(map.backward, control) ? collect(keys(map.backward[control])) : Symbol[]

"""
    has_run(map::ControlMap, run) -> Bool

Whether `run` is a registered node.
"""
has_run(map::ControlMap, run) = run in map.runs

"""
    has_control(map::ControlMap, control) -> Bool

Whether `control` is a registered node.
"""
has_control(map::ControlMap, control) = control in map.controls

"""
    has_link(map::ControlMap, run, control; type=nothing) -> Bool

Whether an edge exists between `run` and `control`, optionally restricted to
one `control_type`.
"""
function has_link(map::ControlMap, run, control; type::Union{Symbol,AbstractString,Nothing}=nothing)
    haskey(map.forward, run) || return false
    run_dict = map.forward[run]
    if type === nothing
        for cset in values(run_dict)
            control in cset && return true
        end
        return false
    else
        t = Symbol(type)
        return haskey(run_dict, t) && control in run_dict[t]
    end
end

"""
    edge_metadata(map::ControlMap, run, control, control_type) -> Union{Nothing,Dict{Symbol,Any}}

Metadata attached to the `(run, control, control_type)` edge, or `nothing` if
that edge doesn't exist. An edge with no metadata set returns an empty
`Dict`, distinguishing "no edge" from "edge with no metadata."

Named `edge_metadata` rather than `metadata` to avoid colliding with
`DataAPI.metadata`/`DataFrames.metadata`, which every realistic consumer of
this package will also have loaded.
"""
function edge_metadata(map::ControlMap, run, control, control_type::Union{Symbol,AbstractString})
    t = Symbol(control_type)
    has_link(map, run, control; type=t) || return nothing
    return get(map.metadata, (run, control, t), Dict{Symbol,Any}())
end

"""
    edges(map::ControlMap) -> Vector{<:NamedTuple}

All edges as `(run, control, control_type, metadata)` named tuples.
"""
function edges(map::ControlMap{R,C}) where {R,C}
    T = NamedTuple{(:run, :control, :control_type, :metadata),Tuple{R,C,Symbol,Dict{Symbol,Any}}}
    result = T[]
    for (r, run_dict) in map.forward
        for (t, cset) in run_dict
            for c in cset
                push!(result, (run=r, control=c, control_type=t, metadata=get(map.metadata, (r, c, t), Dict{Symbol,Any}())))
            end
        end
    end
    return result
end

"""
    n_runs(map::ControlMap) -> Int

Number of registered run nodes.
"""
n_runs(map::ControlMap) = length(map.runs)

"""
    n_controls(map::ControlMap) -> Int

Number of registered control nodes.
"""
n_controls(map::ControlMap) = length(map.controls)

"""
    n_edges(map::ControlMap) -> Int

Number of edges in the graph.
"""
n_edges(map::ControlMap) = sum((length(cset) for run_dict in values(map.forward) for cset in values(run_dict)); init=0)

function Base.iterate(map::ControlMap)
    e = edges(map)
    isempty(e) && return nothing
    return (e[1], (e, 2))
end

function Base.iterate(::ControlMap, state)
    e, i = state
    i > length(e) && return nothing
    return (e[i], (e, i + 1))
end

Base.eltype(::Type{ControlMap{R,C}}) where {R,C} =
    NamedTuple{(:run, :control, :control_type, :metadata),Tuple{R,C,Symbol,Dict{Symbol,Any}}}

Base.IteratorSize(::Type{<:ControlMap}) = Base.SizeUnknown()
