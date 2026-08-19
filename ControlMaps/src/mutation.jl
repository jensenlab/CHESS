"""
    add_run!(map::ControlMap, run) -> map

Register `run` as a node with no edges. Idempotent -- a no-op if `run` is
already registered.
"""
function add_run!(map::ControlMap, run)
    push!(map.runs, run)
    return map
end

"""
    add_control!(map::ControlMap, control) -> map

Register `control` as a node with no edges. Idempotent.
"""
function add_control!(map::ControlMap, control)
    push!(map.controls, control)
    return map
end

"""
    link!(map::ControlMap, run, control, control_type; metadata=nothing) -> map

Create an edge between `run` and `control` labeled `control_type` (a `Symbol`
or `AbstractString`, canonicalized to `Symbol`). Implicitly registers `run`
and `control` if they aren't already known.

Idempotent on graph structure -- relinking an existing edge does not
duplicate it. If `metadata` is given, it is merged into the edge's existing
metadata rather than replacing it, so a repeated `link!` call can't silently
drop metadata a previous call attached.
"""
function link!(map::ControlMap{R,C}, run, control, control_type::Union{Symbol,AbstractString};
                metadata::Union{Nothing,AbstractDict}=nothing) where {R,C}
    add_run!(map, run)
    add_control!(map, control)
    t = Symbol(control_type)

    run_dict = get!(() -> Dict{Symbol,Set{C}}(), map.forward, run)
    push!(get!(() -> Set{C}(), run_dict, t), control)

    control_dict = get!(() -> Dict{Symbol,Set{R}}(), map.backward, control)
    push!(get!(() -> Set{R}(), control_dict, t), run)

    if metadata !== nothing
        existing = get!(() -> Dict{Symbol,Any}(), map.metadata, (run, control, t))
        for (k, v) in metadata
            existing[Symbol(k)] = v
        end
    end

    return map
end

"""
    unlink!(map::ControlMap, run, control, control_type=nothing) -> map

Remove the edge between `run` and `control` labeled `control_type`, along
with its metadata. If `control_type` is `nothing` (the default), removes all
edges between `run` and `control` regardless of type.

No-op if no matching edge exists. `run` and `control` remain registered nodes
even if this leaves them without any edges.
"""
function unlink!(map::ControlMap, run, control, control_type::Union{Symbol,AbstractString,Nothing}=nothing)
    haskey(map.forward, run) || return map
    run_dict = map.forward[run]

    types_to_check = control_type === nothing ? collect(keys(run_dict)) : Symbol[Symbol(control_type)]

    for t in types_to_check
        haskey(run_dict, t) || continue
        cset = run_dict[t]
        control in cset || continue

        delete!(cset, control)
        isempty(cset) && delete!(run_dict, t)

        if haskey(map.backward, control) && haskey(map.backward[control], t)
            rset = map.backward[control][t]
            delete!(rset, run)
            isempty(rset) && delete!(map.backward[control], t)
        end

        delete!(map.metadata, (run, control, t))
    end

    isempty(run_dict) && delete!(map.forward, run)
    haskey(map.backward, control) && isempty(map.backward[control]) && delete!(map.backward, control)

    return map
end

"""
    remove_run!(map::ControlMap, run) -> map

Deregister `run`, cascading to unlink every edge that touches it (and their
metadata). No-op if `run` was never registered.
"""
function remove_run!(map::ControlMap, run)
    if haskey(map.forward, run)
        for (t, cset) in collect(map.forward[run])
            for control in collect(cset)
                unlink!(map, run, control, t)
            end
        end
    end
    delete!(map.runs, run)
    return map
end

"""
    remove_control!(map::ControlMap, control) -> map

Deregister `control`, cascading to unlink every edge that touches it. No-op
if `control` was never registered.
"""
function remove_control!(map::ControlMap, control)
    if haskey(map.backward, control)
        for (t, rset) in collect(map.backward[control])
            for run in collect(rset)
                unlink!(map, run, control, t)
            end
        end
    end
    delete!(map.controls, control)
    return map
end

"""
    set_metadata!(map::ControlMap, run, control, control_type, data::AbstractDict) -> map

Merge `data` into the metadata of an *existing* edge. Throws `ArgumentError`
if `(run, control, control_type)` is not an edge in `map`.
"""
function set_metadata!(map::ControlMap, run, control, control_type::Union{Symbol,AbstractString}, data::AbstractDict)
    t = Symbol(control_type)
    has_link(map, run, control; type=t) ||
        throw(ArgumentError("no such edge ($run, $control, $t) in ControlMap"))

    existing = get!(() -> Dict{Symbol,Any}(), map.metadata, (run, control, t))
    for (k, v) in data
        existing[Symbol(k)] = v
    end
    return map
end
