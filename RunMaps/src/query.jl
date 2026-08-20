"""
    linked_runs(map::RunMap, run; type=nothing) -> Vector

Nodes linked from `run` (i.e. `run` is the subject of the edge), optionally
filtered to one `relation_type`. Returns an empty vector if `run` is
unregistered or has no matching edges (unknown nodes are treated as having
zero edges, not an error).
"""
function linked_runs(map::RunMap{N}, run; type::Union{Symbol,AbstractString,Nothing}=nothing) where {N}
    haskey(map.forward, run) || return N[]
    run_dict = map.forward[run]
    if type === nothing
        result = Set{N}()
        for lset in values(run_dict)
            union!(result, lset)
        end
        return collect(result)
    else
        t = Symbol(type)
        return haskey(run_dict, t) ? collect(run_dict[t]) : N[]
    end
end

"""
    linking_runs(map::RunMap, linked_run; type=nothing) -> Vector

Runs for which `linked_run` is the linked node, optionally filtered to one
`relation_type`. Returns an empty vector if `linked_run` is unregistered or
has no matching edges.
"""
function linking_runs(map::RunMap{N}, linked_run; type::Union{Symbol,AbstractString,Nothing}=nothing) where {N}
    haskey(map.backward, linked_run) || return N[]
    linked_dict = map.backward[linked_run]
    if type === nothing
        result = Set{N}()
        for rset in values(linked_dict)
            union!(result, rset)
        end
        return collect(result)
    else
        t = Symbol(type)
        return haskey(linked_dict, t) ? collect(linked_dict[t]) : N[]
    end
end

"""
    runs(map::RunMap) -> Vector

Every registered node (the single pool).
"""
runs(map::RunMap) = collect(map.runs)

"""
    relation_types(map::RunMap, run) -> Vector{Symbol}

Distinct relation types linked from `run`.
"""
relation_types(map::RunMap, run) = haskey(map.forward, run) ? collect(keys(map.forward[run])) : Symbol[]

"""
    roles(map::RunMap, linked_run) -> Vector{Symbol}

Distinct relation types (roles) `linked_run` plays, across the runs that
link to it. Generic across relation kinds -- e.g. a `:duplicate` relation's
"role" reads just as naturally as a control's role.
"""
roles(map::RunMap, linked_run) = haskey(map.backward, linked_run) ? collect(keys(map.backward[linked_run])) : Symbol[]

"""
    roles(map::RunMap) -> Vector{Symbol}

Every distinct relation type used anywhere in `map` (e.g. `[:positive,
:negative, :duplicate]`), regardless of which nodes carry them. Empty if
`map` has no edges.
"""
function roles(map::RunMap)
    s = Set{Symbol}()
    for run_dict in values(map.forward)
        union!(s, keys(run_dict))
    end
    return collect(s)
end

"""
    has_run(map::RunMap, run) -> Bool

Whether `run` is a registered node.
"""
has_run(map::RunMap, run) = run in map.runs

"""
    has_link(map::RunMap, run, linked_run; type=nothing) -> Bool

Whether an edge exists from `run` to `linked_run`, optionally restricted to
one `relation_type`.
"""
function has_link(map::RunMap, run, linked_run; type::Union{Symbol,AbstractString,Nothing}=nothing)
    haskey(map.forward, run) || return false
    run_dict = map.forward[run]
    if type === nothing
        for lset in values(run_dict)
            linked_run in lset && return true
        end
        return false
    else
        t = Symbol(type)
        return haskey(run_dict, t) && linked_run in run_dict[t]
    end
end

"""
    edge_metadata(map::RunMap, run, linked_run, relation_type) -> Union{Nothing,Dict{Symbol,Any}}

Metadata attached to the `(run, linked_run, relation_type)` edge, or
`nothing` if that edge doesn't exist. An edge with no metadata set returns an
empty `Dict`, distinguishing "no edge" from "edge with no metadata."
"""
function edge_metadata(map::RunMap, run, linked_run, relation_type::Union{Symbol,AbstractString})
    t = Symbol(relation_type)
    has_link(map, run, linked_run; type=t) || return nothing
    return get(map.metadata, (run, linked_run, t), Dict{Symbol,Any}())
end

"""
    edges(map::RunMap) -> Vector{<:NamedTuple}

All edges as `(run, linked_run, relation_type, metadata)` named tuples.
"""
function edges(map::RunMap{N}) where {N}
    T = NamedTuple{(:run, :linked_run, :relation_type, :metadata),Tuple{N,N,Symbol,Dict{Symbol,Any}}}
    result = T[]
    for (r, run_dict) in map.forward
        for (t, lset) in run_dict
            for l in lset
                push!(result, (run=r, linked_run=l, relation_type=t, metadata=get(map.metadata, (r, l, t), Dict{Symbol,Any}())))
            end
        end
    end
    return result
end

"""
    n_runs(map::RunMap) -> Int

Number of registered nodes.
"""
n_runs(map::RunMap) = length(map.runs)

"""
    n_edges(map::RunMap) -> Int

Number of edges in the graph.
"""
n_edges(map::RunMap) = sum((length(lset) for run_dict in values(map.forward) for lset in values(run_dict)); init=0)

function Base.iterate(map::RunMap)
    e = edges(map)
    isempty(e) && return nothing
    return (e[1], (e, 2))
end

function Base.iterate(::RunMap, state)
    e, i = state
    i > length(e) && return nothing
    return (e[i], (e, i + 1))
end

Base.eltype(::Type{RunMap{N}}) where {N} =
    NamedTuple{(:run, :linked_run, :relation_type, :metadata),Tuple{N,N,Symbol,Dict{Symbol,Any}}}

Base.IteratorSize(::Type{<:RunMap}) = Base.SizeUnknown()
