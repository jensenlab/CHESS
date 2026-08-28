module PlateMapsRunMapsExt

using PlateMaps, RunMaps, DataFrames, LabwarePlotting, Plots

# --- edges adapter -----------------------------------------------------------------------------
# RunMap.edges() returns (run, linked_run, relation_type, metadata) NamedTuples -- almost exactly
# PlateMaps' own native (node1, node2, role, metadata) edge shape, just different field names, so this
# really is just a field-rename, not a real conversion.
_as_platemaps_edges(rm::RunMap) = [PlateMaps.mkedge(e.run,e.linked_run,e.relation_type;metadata=e.metadata) for e in RunMaps.edges(rm)]

function _placeable_nodes(rm::RunMap,placeable_roles)
    roles_set = placeable_roles isa Symbol ? Set{Symbol}([placeable_roles]) : Set{Symbol}(placeable_roles)
    placeable = Set{Any}()
    for e in RunMaps.edges(rm)
        e.relation_type in roles_set && push!(placeable,e.linked_run)
    end
    return placeable
end

"""
    schedule_platemap(wells::BitMatrix, rm::RunMap, placeable_roles; kwargs...) -> Vector{PlateMap}

Schedule a `RunMap` directly. `RunMap` doesn't distinguish "run" vs "control" nodes structurally --
every node is just a node connected by typed `relation_type` edges (which may include e.g. `:duplicate`
alongside control-style roles like `:positive`/`:negative`). `placeable_roles` (a `Symbol` or a collection
of `Symbol`s) designates which relation_type(s) mark a node as optimizable: any node that *serves* one of
those roles -- i.e. is the linked (target) node of an edge whose `relation_type` is in `placeable_roles`,
`RunMaps.roles(rm,node)`'s sense of "role," not `relation_types`' -- is placed by the control-placement
stage; every other node is fixed first via [`place_runs`](@ref). This mirrors
`schedule_platemap(wells,edges,fixed_nodes;kwargs...)`'s own explicit-fixed-nodes design, since `RunMaps`
deliberately leaves run/control semantics to the caller rather than tracking them itself.

Just builds `edges`/`fixed_nodes` and forwards to the core `schedule_platemap(wells,edges,fixed_nodes;
kwargs...)`, so it inherits multi-plate scheduling for free: if `rm`'s edge-connected components don't fit
on one `wells` plate, this returns one `PlateMap` per plate needed (see the core method's docstring).
"""
function PlateMaps.schedule_platemap(wells::BitMatrix,rm::RunMap,placeable_roles;kwargs...)
    edges = _as_platemaps_edges(rm)
    placeable = _placeable_nodes(rm,placeable_roles)
    fixed_nodes = collect(setdiff(RunMaps.runs(rm),placeable))
    return PlateMaps.schedule_platemap(wells,edges,fixed_nodes;kwargs...)
end

# --- identity resolution -------------------------------------------------------------------------

"""
    describe(pm::PlateMap, rm::RunMap, node)
    describe(pm::PlateMap, rm::RunMap, i, j)
    describe(pm::PlateMap, rm::RunMap, I::CartesianIndex)

Relationship summary for a node (or a well's occupant): `(registered=Bool, outgoing_roles=[...],
incoming_roles=[...], linked_runs=[...], linking_runs=[...])`. `RunMaps` doesn't classify nodes into a
run/control "kind" -- this reports the honest relationship structure instead: which relation_types the
node is the subject of (`outgoing_roles`) vs. the target of (`incoming_roles`), and its neighbors in each
direction. `nothing` for an empty well.
"""
function PlateMaps.describe(pm::PlateMap,rm::RunMap,node)
    RunMaps.has_run(rm,node) || return (registered=false,outgoing_roles=Symbol[],incoming_roles=Symbol[],linked_runs=[],linking_runs=[])
    return (registered=true,
            outgoing_roles=RunMaps.relation_types(rm,node),
            incoming_roles=RunMaps.roles(rm,node),
            linked_runs=RunMaps.linked_runs(rm,node),
            linking_runs=RunMaps.linking_runs(rm,node))
end
function PlateMaps.describe(pm::PlateMap,rm::RunMap,I::CartesianIndex)
    occ = pm[I]
    return ismissing(occ) ? nothing : PlateMaps.describe(pm,rm,occ)
end
PlateMaps.describe(pm::PlateMap,rm::RunMap,i,j) = PlateMaps.describe(pm,rm,CartesianIndex(i,j))

# --- role-aware visualization ---------------------------------------------------------------------

"""
    plot(pm::PlateMap, rm::RunMap; role_colors=Dict{Symbol,Any}(), inactive="darkgray",
         empty_color="white", default_color="steelblue")

Role-aware layout visualization: colors each occupied well by its (first) incoming role per `rm`
(`RunMaps.roles(rm,node)`, empty for a node nothing links to), or `default_color` otherwise. Auto-assigned
from a palette unless overridden via `role_colors`.
"""
function PlateMaps.plot(pm::PlateMap,rm::RunMap;role_colors::Dict{Symbol,<:Any}=Dict{Symbol,Any}(),
        inactive="darkgray",empty_color="white",default_color="steelblue")
    all_roles = Symbol[]
    for n in PlateMaps.nodes(pm)
        append!(all_roles,RunMaps.roles(rm,n))
    end
    unique!(all_roles)
    colors = LabwarePlotting.role_palette(all_roles;overrides=role_colors)

    fillcolors = map(CartesianIndices(pm.wells)) do I
        if !pm.wells[I]
            inactive
        elseif ismissing(pm[I])
            empty_color
        else
            rs = RunMaps.roles(rm,pm[I])
            isempty(rs) ? default_color : colors[first(rs)]
        end
    end
    return LabwarePlotting.plot_grid(pm.wells;fillcolors=fillcolors)
end

# --- joined DataFrame view -------------------------------------------------------------------------

"""
    DataFrame(pm::PlateMap, rm::RunMap) -> DataFrame

`DataFrame(pm)` plus `registered`, `outgoing_roles`, and `incoming_roles` columns, resolved per well via
`rm` (see [`describe`](@ref)).
"""
function PlateMaps.DataFrame(pm::PlateMap,rm::RunMap)
    df = PlateMaps.DataFrame(pm)
    registered = Vector{Union{Missing,Bool}}(missing,DataFrames.nrow(df))
    outgoing = Vector{Any}(missing,DataFrames.nrow(df))
    incoming = Vector{Any}(missing,DataFrames.nrow(df))
    for (i,occ) in enumerate(df.occupant)
        ismissing(occ) && continue
        d = PlateMaps.describe(pm,rm,occ)
        registered[i] = d.registered
        outgoing[i] = d.outgoing_roles
        incoming[i] = d.incoming_roles
    end
    df.registered = registered
    df.outgoing_roles = outgoing
    df.incoming_roles = incoming
    return df
end

"""
    DataFrame(pms::Vector{PlateMap}, rm::RunMap) -> DataFrame

Multi-plate form of [`DataFrame(pm::PlateMap, rm::RunMap)`](@ref): each plate's joined `DataFrame`,
stacked with a leading `plate` column (1-based, matching `pms`' order), same pattern as
[`DataFrame(pms::Vector{PlateMap})`](@ref).
"""
function PlateMaps.DataFrame(pms::Vector{PlateMap},rm::RunMap)
    dfs = DataFrames.DataFrame[]
    for (i,pm) in enumerate(pms)
        df = PlateMaps.DataFrame(pm,rm)
        DataFrames.insertcols!(df,1,:plate=>i)
        push!(dfs,df)
    end
    return DataFrames.vcat(dfs...)
end

end # module PlateMapsRunMapsExt
