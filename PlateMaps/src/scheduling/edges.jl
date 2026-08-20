"""
    mkedge(node1, node2, role::Symbol=:default; metadata=Dict{Symbol,Any}())

Construct an edge in PlateMaps' native, dependency-free scheduling input format: a `NamedTuple`
`(node1=.., node2=.., role=.., metadata=..)`. This shape deliberately mirrors `RunMaps.edges(rm)`'s
`(run, linked_run, relation_type, metadata)` output (with neutral field names, since `PlateMaps` doesn't
know about a run/control distinction) -- a `RunMap`'s edges can be handed to the scheduler with only a
field-name translation, no real conversion logic.

Any iterable of NamedTuples with `node1`/`node2`/`role`/`metadata` fields is a valid `edges` argument to
[`schedule_platemap`](@ref); this constructor is just a convenience for hand-building them.
"""
mkedge(node1,node2,role::Symbol=:default;metadata=Dict{Symbol,Any}()) = (node1=node1,node2=node2,role=role,metadata=metadata)

"""
    edge_nodes(edges) -> Set

The distinct nodes referenced by `edges` (either endpoint).
"""
function edge_nodes(edges)
    ns = Set()
    for e in edges
        push!(ns,e.node1)
        push!(ns,e.node2)
    end
    return ns
end

"""
    roles(edges) -> Set{Symbol}

The distinct roles referenced by `edges`.
"""
roles(edges) = Set(e.role for e in edges)

"""
    components(edges) -> Vector{Set}

The connected components of the graph formed by `edges` (both endpoints of every edge, regardless of
role) -- a plain union-find over node identities. Nodes that never appear in `edges` are not included.
"""
function components(edges)
    parent = Dict{Any,Any}()
    function find(x)
        while parent[x] != x
            parent[x] = parent[parent[x]]
            x = parent[x]
        end
        return x
    end
    for e in edges
        haskey(parent,e.node1) || (parent[e.node1] = e.node1)
        haskey(parent,e.node2) || (parent[e.node2] = e.node2)
        ra,rb = find(e.node1),find(e.node2)
        ra != rb && (parent[ra] = rb)
    end
    groups = Dict{Any,Set{Any}}()
    for n in keys(parent)
        push!(get!(() -> Set{Any}(),groups,find(n)),n)
    end
    return collect(values(groups))
end
