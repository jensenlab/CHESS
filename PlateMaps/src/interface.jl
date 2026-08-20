"""
    Base.getindex(pm::PlateMap, i, j)
    Base.getindex(pm::PlateMap, I::CartesianIndex)

Return the node occupying well `(i,j)`, or `missing` if that well is empty/inactive. Reserved strictly
for well-based access -- for the reverse lookup (given a node, which well is it in), see [`well_position`](@ref);
`pm[node]` is deliberately not defined, since if the node identity type `T` is e.g. `Int`, `pm[5]` would
be ambiguous between "well 5" and "node 5".
"""
Base.getindex(pm::PlateMap,i,j) = pm.occupant[i,j]
Base.getindex(pm::PlateMap,I::CartesianIndex) = pm.occupant[I]

"""
    nodes(pm::PlateMap{T}) where T -> Vector{T}

All nodes currently placed on `pm`, in no particular order.
"""
nodes(pm::PlateMap) = collect(skipmissing(pm.occupant))

"""
    well_position(pm::PlateMap, node) -> Union{CartesianIndex,Nothing}

The well `node` occupies, or `nothing` if it isn't placed on `pm`. A linear scan (`O(wells)`) -- plate
sizes here are small enough (hundreds of wells) that a cached reverse index isn't worth the complexity.
"""
function well_position(pm::PlateMap,node)
    for I in CartesianIndices(pm.occupant)
        v = pm.occupant[I]
        !ismissing(v) && v == node && return I
    end
    return nothing
end

"""
    Base.iterate(pm::PlateMap)

Iterate over `pm`'s occupied wells as `node => well` pairs (`CartesianIndex`), skipping empty/inactive
wells -- mirrors `ControlMap`'s own philosophy of iterating over the meaningful relationships rather than
the raw underlying matrix.
"""
function Base.iterate(pm::PlateMap,state=1)
    idxs = CartesianIndices(pm.occupant)
    while state <= length(idxs)
        I = idxs[state]
        v = pm.occupant[I]
        if !ismissing(v)
            return (v => I, state+1)
        end
        state += 1
    end
    return nothing
end
Base.eltype(::Type{PlateMap{T}}) where T = Pair{T,CartesianIndex{2}}
Base.IteratorSize(::Type{<:PlateMap}) = Base.HasLength()
Base.length(pm::PlateMap) = count(!ismissing,pm.occupant)
