"""
    RunMap{N}

A multimap over a single pool of nodes of type `N`, expressing directed,
typed relationships between them (e.g. "run X is validated by control Y",
"run X is a duplicate of run Y"). Each edge is labeled with an open/extensible
`Symbol` `relation_type` (e.g. `:positive`, `:negative`, `:blank`,
`:duplicate`, or any caller-defined label) and may carry optional metadata.

Any node may simultaneously be the *subject* of some edges and the
*linked node* of others -- role is purely relative to a given edge, never a
node-level property. `N` is opaque and caller-supplied -- `RunMap` has no
notion of what a node represents.

See also: [`link!`](@ref), [`linked_runs`](@ref), [`linking_runs`](@ref),
[`runs`](@ref).
"""
struct RunMap{N}
    runs::Set{N}
    forward::Dict{N,Dict{Symbol,Set{N}}}
    backward::Dict{N,Dict{Symbol,Set{N}}}
    metadata::Dict{Tuple{N,N,Symbol},Dict{Symbol,Any}}
end

RunMap{N}() where {N} = RunMap{N}(
    Set{N}(),
    Dict{N,Dict{Symbol,Set{N}}}(), Dict{N,Dict{Symbol,Set{N}}}(),
    Dict{Tuple{N,N,Symbol},Dict{Symbol,Any}}(),
)

RunMap() = RunMap{Any}()
