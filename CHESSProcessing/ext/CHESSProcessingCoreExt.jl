"""
    CHESSProcessingCoreExt

Adds a [`CHESSProcessing.resolve`](@ref) overload for callers who already attached reads to
`CHESSCore.Labware`/`Well` objects via `CHESSParsers.record_reads!`, instead of working from raw
`CHESSParsers.LabwareRead`s. Loads only when `CHESSCore` is also loaded -- `CHESSProcessing`'s base
package has no `CHESSCore` dependency, since `resolve`'s primary data model is `LabwareRead` (see
`resolve.jl`).
"""
module CHESSProcessingCoreExt

using CHESSProcessing, CHESSCore, PlateMaps, RunMaps, DataFrames

import CHESSProcessing: Experiment, RunMap, PlateMap, _node_type, _well_to_node, append_record

"""
    resolve(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
            labware::AbstractVector{<:Pair}; read_kind::Symbol) -> (Experiment, Dict{N,Union{Missing,Number}}) where {N}

`CHESSCore`-object variant of [`CHESSProcessing.resolve`](@ref): `labware` is a labeled `Pair`
vector, `[labware_name => CHESSCore.Labware, ...]`, matching `plate_maps`' own shape -- the caller
pairs each `Labware` with the plate it belongs to, same convention as the base `LabwareRead` method.

For each occupied well on a matched `plate_maps` entry, looks up the corresponding `Well` on the
paired `Labware` (`labware[well_name]`) and requires *exactly one* `Read` of `read_kind` recorded on
it (via `CHESSParsers.record_reads!`) -- zero or more than one throws, since `resolve` has no
missing-data policy of its own to arbitrate between candidate reads (that's `aggregate`'s job, one
level up, for genuinely repeated measurements; here it signals an ambiguous/incomplete `record_reads!`
call). A well with no occupant node is silently skipped, same as the base method.

Appends a [`CHESSProcessing.ProcessingRecord`](@ref) (`:resolve`, params `read_kind`, this call's
output `values`) to `experiment` and returns `(experiment, values)`.
"""
function CHESSProcessing.resolve(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                                  labware::AbstractVector{<:Pair{<:Any,<:CHESSCore.Labware}}; read_kind::Symbol)
    isempty(plate_maps) && throw(ArgumentError("plate_maps must not be empty"))
    N = _node_type(last(first(plate_maps)))
    out = Dict{N,Union{Missing,Number}}()

    plates_by_label = Dict(string(label) => pm for (label, pm) in plate_maps)
    for (_, pm) in plate_maps, (node, _) in pm
        out[node] = missing
    end

    for (labware_name, lw) in labware
        label = string(labware_name)
        haskey(plates_by_label, label) ||
            throw(ArgumentError("labware \"$label\" not found in plate_maps"))
        well_to_node = _well_to_node(plates_by_label[label])
        for (well_name, node) in well_to_node
            well = lw[well_name]
            matching = filter(r -> r.kind.name == read_kind, well.reads)
            isempty(matching) && continue # nothing recorded for this well/read_kind -- stays missing
            length(matching) == 1 ||
                throw(ArgumentError("well \"$well_name\" on \"$label\" has $(length(matching)) :$read_kind reads; resolve needs exactly one"))
            out[node] = matching[1].value
        end
    end

    experiment = append_record(experiment, :resolve, Dict{Symbol,Any}(:read_kind => read_kind), out)
    return experiment, out
end

end # module CHESSProcessingCoreExt
