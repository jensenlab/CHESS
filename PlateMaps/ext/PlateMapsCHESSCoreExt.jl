module PlateMapsCHESSCoreExt

using PlateMaps, CHESSCore

"""
    wells_from_locationkind(kind::CHESSCore.LocationKind) -> BitMatrix

Derive an active-well `BitMatrix` from a registered plate `LocationKind`'s `shape` -- geometry only
(not the well's contents/capacity/stocks), so a caller with a real plate kind registered (e.g. via
`CHESSLabConstants`) doesn't have to hand-build `trues(R,C)`.
"""
function PlateMaps.wells_from_locationkind(kind::CHESSCore.LocationKind)
    kind.shape === nothing && throw(ArgumentError("LocationKind $(kind.name) has no shape (not Labware-like)"))
    return trues(kind.shape...)
end

"""
    schedule_platemap(kind::CHESSCore.LocationKind, edges, fixed_nodes; kwargs...) -> Vector{PlateMap}

Schedule directly on a registered plate `LocationKind`, deriving `wells` via
[`wells_from_locationkind`](@ref) instead of requiring the caller to hand-build a `BitMatrix`.
Equivalent to `schedule_platemap(wells_from_locationkind(kind), edges, fixed_nodes; kwargs...)`.
`edges`/`fixed_nodes` are left untyped, same as the core method, so this composes with the `RunMaps`
extension automatically when both are loaded: `schedule_platemap(kind, rm::RunMap, placeable_roles;
kwargs...)` dispatches here for `wells`-derivation, then the inner call re-dispatches to
`PlateMapsRunMapsExt`'s more specific `(::BitMatrix, ::RunMap, placeable_roles)` method. Inherits the core
method's multi-plate behavior for free: returns one `PlateMap` per plate needed (never a bare `PlateMap`).
"""
function PlateMaps.schedule_platemap(kind::CHESSCore.LocationKind,edges,fixed_nodes;kwargs...)
    return PlateMaps.schedule_platemap(PlateMaps.wells_from_locationkind(kind),edges,fixed_nodes;kwargs...)
end

end # module PlateMapsCHESSCoreExt
