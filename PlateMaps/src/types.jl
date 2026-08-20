"""
    struct PlacementError <: Exception

Thrown when a `PlateMap`'s `occupant` field is invalid: a node assigned to an inactive well, or the
same node assigned to more than one well.
"""
struct PlacementError <: Exception
    msg::AbstractString
end

"""
    struct PlateMap{T}
        wells::BitMatrix
        occupant::Matrix{Union{Missing,T}}
    end

A `PlateMap` is the physical realization of a scheduling problem: which node (of caller-chosen
identity type `T`) occupies which well of a plate. It stores nothing about *why* -- no roles, no
run/control distinction, no relationships between nodes -- only *where*. `PlateMap` is deliberately the
solution, not the problem statement; combine it with whatever produced the schedule (e.g. a
`RunMaps.RunMap`, sharing the same node identities) to resolve what any given occupant actually
is.

`occupant` is `missing` at every unassigned well (including every inactive one).
"""
struct PlateMap{T}
    wells::BitMatrix
    occupant::Matrix{Union{Missing,T}}
    function PlateMap{T}(wells::AbstractMatrix,occupant::AbstractMatrix) where T
        wells = BitMatrix(wells)
        occupant = Matrix{Union{Missing,T}}(occupant)
        size(wells) == size(occupant) || throw(DimensionMismatch("wells and occupant must have the same size"))
        assigned = .!ismissing.(occupant)
        any(assigned .&& .!wells) && throw(PlacementError("occupant can only be assigned at active wells"))
        vals = collect(skipmissing(occupant))
        length(vals) == length(unique(vals)) || throw(PlacementError("each node may occupy at most one well"))
        return new{T}(wells,occupant)
    end
end

PlateMap(wells::AbstractMatrix,occupant::AbstractMatrix{Union{Missing,T}}) where T = PlateMap{T}(wells,occupant)

"""
    PlateMap{T}(wells::AbstractMatrix) where T

Construct an empty `PlateMap` (no nodes placed) over the given active-well mask.
"""
PlateMap{T}(wells::AbstractMatrix) where T = PlateMap{T}(wells, Matrix{Union{Missing,T}}(missing,size(wells)))

Base.size(pm::PlateMap) = size(pm.wells)

Base.:(==)(a::PlateMap,b::PlateMap) = a.wells == b.wells && isequal(a.occupant,b.occupant)

"""
    describe(pm::PlateMap, cm, node)

Resolve what `node` (or the occupant at a given well) actually *is*, using whatever produced the
schedule -- e.g. a `RunMaps.RunMap` (what relation_types touch it? what metadata?). `PlateMap`
itself stores none of this; it's provided by the `RunMaps` package extension (`using RunMaps`
activates it) rather than the core, since it needs both structures at once.
"""
function describe end

"""
    wells_from_locationkind(kind)

Derive an active-well `BitMatrix` from a registered plate kind's shape. Provided by the `CHESSCore`
package extension (`using CHESSCore` activates it).
"""
function wells_from_locationkind end
