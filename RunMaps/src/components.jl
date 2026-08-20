function _explore!(map::RunMap{N}, start::N, visited::Set{N}) where {N}
    comp = Set{N}()
    stack = N[start]
    push!(visited, start)

    while !isempty(stack)
        n = pop!(stack)
        push!(comp, n)
        if haskey(map.forward, n)
            for nbrs in values(map.forward[n]), nb in nbrs
                if nb ∉ visited
                    push!(visited, nb)
                    push!(stack, nb)
                end
            end
        end
        if haskey(map.backward, n)
            for nbrs in values(map.backward[n]), nb in nbrs
                if nb ∉ visited
                    push!(visited, nb)
                    push!(stack, nb)
                end
            end
        end
    end

    return comp
end

function _component_node_sets(map::RunMap{N}) where {N}
    comps = Set{N}[]
    visited = Set{N}()
    for n0 in map.runs
        n0 in visited && continue
        push!(comps, _explore!(map, n0, visited))
    end
    return comps
end

function _materialize(map::RunMap{N}, comp::Set{N}) where {N}
    sub = RunMap{N}()
    for n in comp
        add_run!(sub, n)
    end
    for n in comp
        haskey(map.forward, n) || continue
        for (t, nbrs) in map.forward[n]
            for nb in nbrs
                link!(sub, n, nb, t; metadata=edge_metadata(map, n, nb, t))
            end
        end
    end
    return sub
end

"""
    components(map::RunMap{N}) -> Vector{RunMap{N}}

Connected components of `map`, treated as an undirected graph over its
single node pool (an edge of any `relation_type` connects its two endpoints
regardless of direction). Each component is returned as an independent
`RunMap{N}` containing exactly that component's nodes, edges (with their
original `relation_type` labels), and edge metadata.

A node registered via [`add_run!`](@ref) but never linked to anything forms
its own singleton component of size 1.

`map` is not mutated, and the returned maps share no mutable state with it.
Order of the returned vector is unspecified.

See also: [`n_components`](@ref), [`n_nodes`](@ref), [`component_sizes`](@ref).
"""
function components(map::RunMap{N}) where {N}
    return [_materialize(map, comp) for comp in _component_node_sets(map)]
end

"""
    n_components(map::RunMap) -> Int

Number of connected components in `map` (see [`components`](@ref)). Computed
without materializing the component sub-maps.
"""
n_components(map::RunMap) = length(_component_node_sets(map))

"""
    n_nodes(map::RunMap) -> Int

Total number of registered nodes in `map`. An alias for [`n_runs`](@ref),
kept as a separate name for capacity-accounting call sites (e.g. "how many
wells does this component need") that don't want to imply every node is
semantically a "run."
"""
n_nodes(map::RunMap) = n_runs(map)

"""
    component_sizes(map::RunMap) -> Vector{Int}

Size (total node count) of each connected component in `map`, equivalent to
`n_nodes.(components(map))` but computed without materializing the component
sub-maps.
"""
component_sizes(map::RunMap) = [length(comp) for comp in _component_node_sets(map)]
