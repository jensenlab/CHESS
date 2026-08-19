function _explore!(map::ControlMap{R,C}, start_run, start_control,
                    visited_runs::Set{R}, visited_controls::Set{C}) where {R,C}
    comp_runs = Set{R}()
    comp_controls = Set{C}()
    run_stack = R[]
    control_stack = C[]

    if start_run !== nothing
        push!(run_stack, start_run)
        push!(visited_runs, start_run)
    else
        push!(control_stack, start_control)
        push!(visited_controls, start_control)
    end

    while !isempty(run_stack) || !isempty(control_stack)
        while !isempty(run_stack)
            r = pop!(run_stack)
            push!(comp_runs, r)
            if haskey(map.forward, r)
                for cset in values(map.forward[r]), c in cset
                    if c ∉ visited_controls
                        push!(visited_controls, c)
                        push!(control_stack, c)
                    end
                end
            end
        end
        while !isempty(control_stack)
            c = pop!(control_stack)
            push!(comp_controls, c)
            if haskey(map.backward, c)
                for rset in values(map.backward[c]), r in rset
                    if r ∉ visited_runs
                        push!(visited_runs, r)
                        push!(run_stack, r)
                    end
                end
            end
        end
    end

    return (comp_runs, comp_controls)
end

function _component_node_sets(map::ControlMap{R,C}) where {R,C}
    comps = Tuple{Set{R},Set{C}}[]
    visited_runs = Set{R}()
    visited_controls = Set{C}()

    for r0 in map.runs
        r0 in visited_runs && continue
        push!(comps, _explore!(map, r0, nothing, visited_runs, visited_controls))
    end
    for c0 in map.controls
        c0 in visited_controls && continue
        push!(comps, _explore!(map, nothing, c0, visited_runs, visited_controls))
    end

    return comps
end

function _materialize(map::ControlMap{R,C}, comp_runs::Set{R}, comp_controls::Set{C}) where {R,C}
    sub = ControlMap{R,C}()
    for r in comp_runs
        add_run!(sub, r)
    end
    for c in comp_controls
        add_control!(sub, c)
    end
    for r in comp_runs
        haskey(map.forward, r) || continue
        for (t, cset) in map.forward[r]
            for c in cset
                link!(sub, r, c, t; metadata=edge_metadata(map, r, c, t))
            end
        end
    end
    return sub
end

"""
    components(map::ControlMap{R,C}) -> Vector{ControlMap{R,C}}

Connected components of `map`, treated as an undirected bipartite graph over
runs and controls (an edge of any `control_type` connects its run and
control). Each component is returned as an independent `ControlMap{R,C}`
containing exactly that component's runs, controls, edges (with their
original `control_type` labels), and edge metadata.

A node registered via [`add_run!`](@ref)/[`add_control!`](@ref) but never
linked to anything forms its own singleton component of size 1.

`map` is not mutated, and the returned maps share no mutable state with it.
Order of the returned vector is unspecified.

See also: [`n_components`](@ref), [`n_nodes`](@ref), [`component_sizes`](@ref).
"""
function components(map::ControlMap{R,C}) where {R,C}
    return [_materialize(map, rs, cs) for (rs, cs) in _component_node_sets(map)]
end

"""
    n_components(map::ControlMap) -> Int

Number of connected components in `map` (see [`components`](@ref)). Computed
without materializing the component sub-maps.
"""
n_components(map::ControlMap) = length(_component_node_sets(map))

"""
    n_nodes(map::ControlMap) -> Int

Total number of registered nodes in `map` -- runs plus controls. Works on any
`ControlMap`, including a component returned by [`components`](@ref), so
`n_nodes.(components(map))` gives the size of every component.
"""
n_nodes(map::ControlMap) = n_runs(map) + n_controls(map)

"""
    component_sizes(map::ControlMap) -> Vector{Int}

Size (total node count) of each connected component in `map`, equivalent to
`n_nodes.(components(map))` but computed without materializing the component
sub-maps.
"""
function component_sizes(map::ControlMap)
    return [length(rs) + length(cs) for (rs, cs) in _component_node_sets(map)]
end
