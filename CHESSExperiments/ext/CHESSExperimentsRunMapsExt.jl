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

using CHESSExperiments, RunMaps, PlateMaps, DataFrames, CHESSCore

function __init__()
    CHESSExperiments.register_parameter!(:run_map, Vector; default = RunMaps.RunMap[])
    CHESSExperiments.register_parameter!(:plate_maps, Vector; default = Pair[])
end

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

    result = CHESSExperiments.with_parameter(experiment, :layout, lay)
    result = CHESSExperiments.with_parameter(result, :run_map, [rm])
    return CHESSExperiments.with_parameter(result, :plate_maps, collect(plates))
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

"""
    _duplicate_count(design, i) -> Int

Total physical wells design row `i` should get, including its own anchor well -- `missing`/`1` (or
`:duplicates` absent entirely) means just the one well.
"""
function _duplicate_count(design, i)
    hasproperty(design, :duplicates) || return 1
    n = design[i, :duplicates]
    return ismissing(n) ? 1 : n
end

"""
    _build_partition_runmap(design, rows) -> RunMaps.RunMap

Build one blocking-partition's `RunMap` directly from the (already-expanded) design, replacing the
old `RunMaps.schedule_uniform_controls`-based synthesis. Every row in `rows` (sample or control alike)
gets its own node, using its plain design-row index -- unchanged from the original node-identity
convention. A row with `_duplicate_count > 1` gets `n-1` extra auxiliary nodes (a `(row, copy)` named
tuple -- can never collide with a real `Int` row index), each linked to the row's own node via a
`:duplicate`-typed edge; `CHESSProcessing.aggregate` already knows how to collapse these
(`RunMaps.linked_runs(run_map, anchor; type=:duplicate)`), no new grouping mechanism needed.

Every sample row gets linked *to* every one of a control row's replicate nodes -- the control's own
anchor *and* every one of its duplicate nodes, not just the anchor -- labeled with the control's own
role. Both parts of this matter:
- **Direction**: `RunMaps.linked_runs(map, anchor; type)` returns nodes `anchor` points *to*
  (`RunMaps/src/query.jl`'s own docstring: "`run` is the subject of the edge"), and
  `CHESSProcessing.aggregate`/`normalize`/`flag` all query with the *sample* as `anchor` -- so the edge
  must run sample -> control, not control -> sample, for a sample's control group to be discoverable
  at all.
- **Full replicate set, not just the anchor**: if a sample only saw the control's anchor node, its
  `:positive`/`:negative`-linked "group" would have exactly one member -- `normalize` would then use
  only one of the control's 12 replicate wells (not their mean) as the control value, and `flag`'s
  `cv_threshold` rule (which needs >=2 values to compute a CV at all) would see nothing to judge. Every
  sample must see the whole replicate set directly for both to work as intended.

This is the same dense every-run-to-every-control linking `schedule_uniform_controls` already did,
just sourced from real, user-designated rows, covering their full duplicate set, and pointed the
direction `CHESSProcessing` expects.
"""
function _build_partition_runmap(design, rows)
    rm = RunMaps.RunMap{Any}()
    samples = Int[]
    control_nodes = Dict{Int,Vector{Any}}() # control row index -> [anchor, dup_node, dup_node, ...]
    for i in rows
        RunMaps.add_run!(rm, i)
        role = CHESSExperiments.control_role(design, i)

        nodes = Any[i]
        n = _duplicate_count(design, i)
        for copy_idx in 2:n
            dup_node = (row = i, copy = copy_idx)
            RunMaps.add_run!(rm, dup_node)
            RunMaps.link!(rm, i, dup_node, :duplicate)
            push!(nodes, dup_node)
        end

        ismissing(role) ? push!(samples, i) : (control_nodes[i] = nodes)
    end

    for s in samples, (c, nodes) in control_nodes
        role = CHESSExperiments.control_role(design, c)
        for node in nodes
            RunMaps.link!(rm, s, node, role)
        end
    end

    return rm
end

"""
    schedule_blocked_layout(experiment::CHESSExperiments.Experiment, wells::BitMatrix, placeable_roles;
                             plate_solver="greedy", reagent_context=CHESSCore, org_context=CHESSCore,
                             kwargs...) -> CHESSExperiments.Experiment

Expand every control template (see [`CHESSExperiments.expand_control_templates`](@ref)), partition the
result by every blocking `Factor` (see [`CHESSExperiments.partition_by_blocking`](@ref)), and schedule
each blocking-homogeneous group independently -- its own `RunMap` (built directly from the design's
`:control_role`/`:duplicates` columns, see [`_build_partition_runmap`](@ref)) and its own
`PlateMaps.schedule_platemap` call, which may itself split one group across multiple physical plates
on capacity grounds. Since every node (including duplicate/control auxiliary nodes) is already
identified by its real (expanded) design-row index -- or a `(row, copy)` tuple for a duplicate well --
no local-to-global renumbering is needed merging groups back together, unlike the old
`schedule_uniform_controls`-based approach.

Returns a new `Experiment` (built from the *expanded* design, since control templates may have
produced more rows than the original) with `:layout`, `:plate_conditions` (one entry per resulting
`labware`, holding that group's shared blocking-factor values), `:run_map`/`:plate_maps` (one `RunMap`
per partition, one `labware => PlateMap` pair per resulting plate -- persisted rather than discarded,
since `CHESSProcessing.aggregate` needs the *same* `RunMap` later to know what to average), and
`:well_conditions` (via [`CHESSExperiments.populate_well_conditions`](@ref)) all set.

A blocking group that can't be scheduled (a control linked to samples spanning more physical wells
than `wells`' capacity allows even after splitting across plates, say) surfaces as an `ArgumentError`
naming which group failed, wrapping whatever `RunMaps`/`PlateMaps` raised -- no new feasibility
pre-check is done; those functions already refuse to silently misplace anything.
"""
function CHESSExperiments.schedule_blocked_layout(experiment::CHESSExperiments.Experiment,
        wells::BitMatrix, placeable_roles; plate_solver::String = "greedy",
        reagent_context = CHESSCore, org_context = CHESSCore, kwargs...)
    expanded = CHESSExperiments.expand_control_templates(experiment)
    design = expanded.design
    n_total = DataFrames.nrow(design)
    blocking_cols, groups = CHESSExperiments.partition_by_blocking(expanded)

    run_maps = RunMaps.RunMap[]
    plate_maps = Pair[]
    layouts = DataFrames.DataFrame[]
    plate_conditions = Dict{Any,Dict{Symbol,Any}}()

    for (gi, group) in enumerate(groups)
        try
            rm = _build_partition_runmap(design, group.rows)
            pms = PlateMaps.schedule_platemap(wells, rm, placeable_roles; plate_solver = plate_solver, kwargs...)
            names = ["g$(gi)_p$(pi)" for pi in 1:length(pms)]

            for (name, pm) in zip(names, pms)
                push!(layouts, _layout_from_platemap(pm, rm, n_total, name))
                push!(plate_maps, name => pm)
            end
            push!(run_maps, rm)

            cond = Dict{Symbol,Any}(zip(blocking_cols, group.key))
            for name in names
                plate_conditions[name] = cond
            end
        catch e
            throw(ArgumentError("blocking group $gi (key $(group.key)) could not be scheduled: $(sprint(showerror, e))"))
        end
    end

    merged = reduce(vcat, layouts)
    merged.location_id = Vector{Union{Int,Missing}}(missing, DataFrames.nrow(merged))
    merged.metadata = [Dict{Symbol,Any}() for _ in 1:DataFrames.nrow(merged)]

    n_placed = count(merged.run)
    n_placed == n_total || throw(ArgumentError(
        "scheduled $n_placed run wells across all blocking groups but experiment.design has $n_total rows -- they must match"))
    assigned = sort(collect(skipmissing(merged.run_index)))
    assigned == collect(1:n_total) || throw(ArgumentError(
        "run_index values across all blocking groups must be exactly 1:$(n_total) with no gaps, overlaps, or duplicates -- got $assigned"))

    result = CHESSExperiments.with_parameter(expanded, :layout, merged)
    result = CHESSExperiments.with_parameter(result, :plate_conditions, plate_conditions)
    result = CHESSExperiments.with_parameter(result, :run_map, run_maps)
    result = CHESSExperiments.with_parameter(result, :plate_maps, plate_maps)
    return CHESSExperiments.populate_well_conditions(result; reagent_context = reagent_context, org_context = org_context)
end

end # module CHESSExperimentsRunMapsExt
