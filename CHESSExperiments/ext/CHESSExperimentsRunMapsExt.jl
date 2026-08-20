"""
    CHESSExperimentsRunMapsExt

Schedules an `Experiment`'s design-matrix rows onto one or more solved `PlateMaps.PlateMap`s, using a
`RunMaps.RunMap` for the run/control relationship structure. Neither `RunMaps` nor `PlateMaps` depends on
`CHESSExperiments` -- this extension only loads when all three packages are loaded.

**Node identity convention**: the `RunMap` passed in must register its run nodes as exactly
`1:nrow(experiment.design)` (`Int` identities, one per design row). This is the whole trick that replaces
`PlateArrays`' separate `run_index` field: a well's `PlateMap` occupant *is* its `run_index` when that
occupant is one of these `Int` nodes -- there is no ordering to compute or validate beyond "did every
design row's node get placed exactly once."

The `:layout` metadata this produces keeps `CHESSExperiments.LAYOUT_COLUMNS`' exact shape
(`well,row,col,run,positive,negative,run_index,labware,location_id,metadata`), derived from
`PlateMaps.DataFrame(::PlateMap, ::RunMap)`'s `occupant`/`incoming_roles` columns, so every existing
`CHESSQC` consumer (`control_bitmatrix`, `data_correction`, `control_summary`, ...) needs no changes.
"""
module CHESSExperimentsRunMapsExt

using CHESSExperiments, RunMaps, PlateMaps, DataFrames

_has_role(::Missing, ::Symbol) = false
_has_role(roles, role::Symbol) = role in roles

function _layout_from_platemap(pm::PlateMaps.PlateMap, rm::RunMaps.RunMap, n_runs::Int, labware_name)
    df = PlateMaps.DataFrame(pm, rm)
    df.run = [occ isa Int && 1 <= occ <= n_runs for occ in df.occupant]
    df.positive = _has_role.(df.incoming_roles, :positive)
    df.negative = _has_role.(df.incoming_roles, :negative)
    df.run_index = [r ? occ : missing for (r, occ) in zip(df.run, df.occupant)]
    df.labware = Vector{Union{String,Missing}}(fill(labware_name, DataFrames.nrow(df)))
    return select(df, CHESSExperiments.LAYOUT_COLUMNS[1:8]) # well,row,col,run,positive,negative,run_index,labware -- location_id/metadata added below
end

"""
    schedule_layout(experiment::CHESSExperiments.Experiment,
                     plates::AbstractVector{<:Pair{<:Union{AbstractString,Missing},<:PlateMaps.PlateMap}},
                     rm::RunMaps.RunMap) -> CHESSExperiments.Experiment

Concatenate each `labware_name => pm` pair's layout (tagged with `labware = labware_name`) into a single
layout, and return a new `Experiment` with `:layout` metadata populated. `rm` is the `RunMap` every `pm`
in `plates` was scheduled from (shared across plates for a multi-plate schedule). Every design row's node
(`1:nrow(experiment.design)`) must appear across the given plates exactly once, with none missing,
duplicated, or unplaced.
"""
function CHESSExperiments.schedule_layout(experiment::CHESSExperiments.Experiment,
        plates::AbstractVector{<:Pair}, rm::RunMaps.RunMap)
    isempty(plates) && throw(ArgumentError("at least one plate is required"))
    n_runs = DataFrames.nrow(experiment.design)

    lay = reduce(vcat, (_layout_from_platemap(pm, rm, n_runs, labware_name) for (labware_name, pm) in plates))

    n_placed_runs = count(lay.run)
    n_placed_runs == n_runs || throw(ArgumentError(
        "plates have $n_placed_runs run wells across them but experiment.design has $n_runs rows -- they must match"))

    assigned = sort(collect(skipmissing(lay.run_index)))
    assigned == collect(1:n_runs) || throw(ArgumentError(
        "run_index values across the given plates must be exactly 1:$(n_runs) with no gaps, overlaps, or duplicates -- got $assigned"))

    lay.location_id = Vector{Union{Int,Missing}}(missing, DataFrames.nrow(lay))
    lay.metadata = [Dict{Symbol,Any}() for _ in 1:DataFrames.nrow(lay)]

    return CHESSExperiments.with_parameter(experiment, :layout, lay)
end

"""
    schedule_layout(experiment::CHESSExperiments.Experiment, pm::PlateMaps.PlateMap, rm::RunMaps.RunMap;
                     labware=missing) -> CHESSExperiments.Experiment

Single-plate convenience form: schedules `experiment` onto the one plate `pm` (already produced by
[`PlateMaps.schedule_platemap`](@ref) from `rm`), tagged with `labware`.
"""
function CHESSExperiments.schedule_layout(experiment::CHESSExperiments.Experiment,
        pm::PlateMaps.PlateMap, rm::RunMaps.RunMap; labware = missing)
    return CHESSExperiments.schedule_layout(experiment, [labware => pm], rm)
end

"""
    schedule_layout(experiment::CHESSExperiments.Experiment, rm::RunMaps.RunMap, wells::BitMatrix,
                     placeable_roles; labware_names=nothing, kwargs...) -> CHESSExperiments.Experiment

Convenience form that schedules `rm` itself via [`PlateMaps.schedule_platemap`](@ref) (auto-splitting
across as many `wells`-shaped plates as needed), then builds the layout. `labware_names`, if given, must
have one name per plate `schedule_platemap` returns (in order); `nothing` leaves every plate's `labware`
as `missing` (fine for a single, unnamed plate).
"""
function CHESSExperiments.schedule_layout(experiment::CHESSExperiments.Experiment, rm::RunMaps.RunMap,
        wells::BitMatrix, placeable_roles; labware_names = nothing, kwargs...)
    pms = PlateMaps.schedule_platemap(wells, rm, placeable_roles; kwargs...)
    names = labware_names === nothing ? fill(missing, length(pms)) : labware_names
    length(names) == length(pms) || throw(ArgumentError(
        "labware_names has $(length(names)) entries but schedule_platemap returned $(length(pms)) plates"))
    return CHESSExperiments.schedule_layout(experiment, Pair.(names, pms), rm)
end

end # module CHESSExperimentsRunMapsExt
