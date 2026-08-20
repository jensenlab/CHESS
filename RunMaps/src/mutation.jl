"""
    add_run!(map::RunMap, run) -> map

Register `run` as a node with no edges. Idempotent -- a no-op if `run` is
already registered. The only registration function: every node, regardless
of what role(s) it ends up playing in any edge, is a "run."
"""
function add_run!(map::RunMap, run)
    push!(map.runs, run)
    return map
end

"""
    link!(map::RunMap, run, linked_run, relation_type; metadata=nothing) -> map

Create an edge from `run` to `linked_run` labeled `relation_type` (a `Symbol`
or `AbstractString`, canonicalized to `Symbol`). Implicitly registers `run`
and `linked_run` if they aren't already known.

Idempotent on graph structure -- relinking an existing edge does not
duplicate it. If `metadata` is given, it is merged into the edge's existing
metadata rather than replacing it, so a repeated `link!` call can't silently
drop metadata a previous call attached.
"""
function link!(map::RunMap{N}, run, linked_run, relation_type::Union{Symbol,AbstractString};
                metadata::Union{Nothing,AbstractDict}=nothing) where {N}
    add_run!(map, run)
    add_run!(map, linked_run)
    t = Symbol(relation_type)

    run_dict = get!(() -> Dict{Symbol,Set{N}}(), map.forward, run)
    push!(get!(() -> Set{N}(), run_dict, t), linked_run)

    linked_dict = get!(() -> Dict{Symbol,Set{N}}(), map.backward, linked_run)
    push!(get!(() -> Set{N}(), linked_dict, t), run)

    if metadata !== nothing
        existing = get!(() -> Dict{Symbol,Any}(), map.metadata, (run, linked_run, t))
        for (k, v) in metadata
            existing[Symbol(k)] = v
        end
    end

    return map
end

"""
    unlink!(map::RunMap, run, linked_run, relation_type=nothing) -> map

Remove the edge from `run` to `linked_run` labeled `relation_type`, along
with its metadata. If `relation_type` is `nothing` (the default), removes
all edges between `run` and `linked_run` regardless of type.

No-op if no matching edge exists. `run` and `linked_run` remain registered
nodes even if this leaves them without any edges.
"""
function unlink!(map::RunMap, run, linked_run, relation_type::Union{Symbol,AbstractString,Nothing}=nothing)
    haskey(map.forward, run) || return map
    run_dict = map.forward[run]

    types_to_check = relation_type === nothing ? collect(keys(run_dict)) : Symbol[Symbol(relation_type)]

    for t in types_to_check
        haskey(run_dict, t) || continue
        lset = run_dict[t]
        linked_run in lset || continue

        delete!(lset, linked_run)
        isempty(lset) && delete!(run_dict, t)

        if haskey(map.backward, linked_run) && haskey(map.backward[linked_run], t)
            rset = map.backward[linked_run][t]
            delete!(rset, run)
            isempty(rset) && delete!(map.backward[linked_run], t)
        end

        delete!(map.metadata, (run, linked_run, t))
    end

    isempty(run_dict) && delete!(map.forward, run)
    haskey(map.backward, linked_run) && isempty(map.backward[linked_run]) && delete!(map.backward, linked_run)

    return map
end

"""
    remove_run!(map::RunMap, run) -> map

Deregister `run`, cascading to unlink every edge that touches it -- both
edges where `run` is the subject (`forward[run]`) and edges where `run` is
the linked node of some other run (`backward[run]`), since a node's edges
are no longer segregated by role. No-op if `run` was never registered.
"""
function remove_run!(map::RunMap, run)
    if haskey(map.forward, run)
        for (t, lset) in collect(map.forward[run])
            for linked_run in collect(lset)
                unlink!(map, run, linked_run, t)
            end
        end
    end
    if haskey(map.backward, run)
        for (t, rset) in collect(map.backward[run])
            for other_run in collect(rset)
                unlink!(map, other_run, run, t)
            end
        end
    end
    delete!(map.runs, run)
    return map
end

"""
    set_metadata!(map::RunMap, run, linked_run, relation_type, data::AbstractDict) -> map

Merge `data` into the metadata of an *existing* edge. Throws `ArgumentError`
if `(run, linked_run, relation_type)` is not an edge in `map`.
"""
function set_metadata!(map::RunMap, run, linked_run, relation_type::Union{Symbol,AbstractString}, data::AbstractDict)
    t = Symbol(relation_type)
    has_link(map, run, linked_run; type=t) ||
        throw(ArgumentError("no such edge ($run, $linked_run, $t) in RunMap"))

    existing = get!(() -> Dict{Symbol,Any}(), map.metadata, (run, linked_run, t))
    for (k, v) in data
        existing[Symbol(k)] = v
    end
    return map
end
