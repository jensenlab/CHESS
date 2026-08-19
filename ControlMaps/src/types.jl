"""
    ControlMap{R,C}

A bipartite multimap relating "run" nodes of type `R` to "control" nodes of
type `C`, where each edge is labeled with a `Symbol` control type (e.g.
`:positive`, `:negative`, `:blank`, or any caller-defined label) and may carry
optional metadata.

Both endpoint types are opaque and caller-supplied -- `ControlMap` has no
notion of what a run or control actually represents.

See also: [`link!`](@ref), [`controls`](@ref), [`runs`](@ref).
"""
struct ControlMap{R,C}
    runs::Set{R}
    controls::Set{C}
    forward::Dict{R,Dict{Symbol,Set{C}}}
    backward::Dict{C,Dict{Symbol,Set{R}}}
    metadata::Dict{Tuple{R,C,Symbol},Dict{Symbol,Any}}
end

ControlMap{R,C}() where {R,C} = ControlMap{R,C}(
    Set{R}(), Set{C}(),
    Dict{R,Dict{Symbol,Set{C}}}(), Dict{C,Dict{Symbol,Set{R}}}(),
    Dict{Tuple{R,C,Symbol},Dict{Symbol,Any}}(),
)

ControlMap() = ControlMap{Any,Any}()
