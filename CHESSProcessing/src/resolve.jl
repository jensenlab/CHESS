_node_type(::PlateMap{T}) where {T} = T

function _well_to_node(pm::PlateMap{T}) where {T}
    df = PlateMaps.DataFrame(pm)
    d = Dict{String,T}()
    for row in eachrow(df)
        ismissing(row.occupant) && continue
        d[row.well] = row.occupant
    end
    return d
end

"""
    resolve(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
            reads::AbstractVector{<:Pair}) -> (Experiment, Dict{N,Union{Missing,Float64}}) where {N}

The one operation with no `values` input -- it's where a value first enters the model. Reads are
inherently well-scoped, so `resolve` resolves against `plate_maps` (position), not `run_map`
(`run_map` is accepted but unused, part of the uniform six-operation signature).

`reads` is a labeled `Pair` vector, `[labware_name => LabwareRead, ...]`, mirroring `plate_maps`'
own `labware_name => PlateMap` shape -- the caller pairs each `CHESSParsers.LabwareRead` with the
plate it belongs to, exactly the way `CHESSParsers.record_reads!` already requires the caller to
pair one `LabwareRead` with one `CHESSCore.Labware` per call, rather than `resolve` guessing a
pairing from `LabwareRead.metadata["plate"]`. Pass multiple pairs sharing the same `labware_name` for
multiple channels/reads on one plate (mirroring `record_reads!`'s `Vector{LabwareRead}` overload,
which just loops).

For each `(labware_name, lr)` pair: matches `plate_maps` by `labware_name`, builds that plate's
well-to-node mapping from `PlateMaps.DataFrame(pm)` (well-label generation lives in `PlateMaps`
itself -- `CHESSCore`-free), and assigns `lr.data.value` to the matching node for each well. `lr.data`
must have exactly one row per well (an endpoint read); a kinetic `LabwareRead` with multiple
timepoints per well needs a separate future reduction step first, per `CHESSProcessing`'s
scalars-only model. A well with no occupant node on its plate (never scheduled) is silently skipped
-- nothing to attach that reading to; a well claimed by more than one `reads` pair throws (a data
integrity conflict, not a missing-data policy question).

Output is keyed over *every* node each matched `PlateMap` knows about, seeded `missing` before
`reads` are applied -- run nodes and duplicate/control nodes alike, since `resolve` doesn't know or
care about role, only position. A `CHESSProcessingCoreExt` extension (loaded when `CHESSCore` is
present) adds an overload for callers who already attached reads to `CHESSCore.Labware`/`Well`
objects via `record_reads!` instead of working from raw `LabwareRead`s.

Appends a [`ProcessingRecord`](@ref) (`:resolve`, no params, this call's output `values`) to
`experiment` and returns `(experiment, values)`.
"""
function resolve(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                  reads::AbstractVector{<:Pair{<:Any,<:CHESSParsers.LabwareRead}})
    isempty(plate_maps) && throw(ArgumentError("plate_maps must not be empty"))
    N = _node_type(last(first(plate_maps)))
    out = Dict{N,Union{Missing,Float64}}()

    plates_by_label = Dict(string(label) => pm for (label, pm) in plate_maps)
    for (_, pm) in plate_maps, (node, _) in pm
        out[node] = missing
    end

    well_to_node_cache = Dict{String,Dict{String,N}}()
    for (labware_name, lr) in reads
        label = string(labware_name)
        haskey(plates_by_label, label) ||
            throw(ArgumentError("reads references labware \"$label\" not found in plate_maps"))
        length(unique(lr.data.well)) == nrow(lr.data) ||
            throw(ArgumentError("resolve expects one row per well (an endpoint read); reduce a kinetic LabwareRead to a scalar first"))
        well_to_node = get!(() -> _well_to_node(plates_by_label[label]), well_to_node_cache, label)
        for row in eachrow(lr.data)
            haskey(well_to_node, row.well) || continue # unoccupied well on this plate -- nothing to attach to
            node = well_to_node[row.well]
            ismissing(out[node]) || throw(ArgumentError("node $node already has a resolved value; multiple reads reference the same well"))
            out[node] = row.value
        end
    end

    experiment = append_record(experiment, :resolve, Dict{Symbol,Any}(), out)
    return experiment, out
end
