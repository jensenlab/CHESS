module CHESSParsersCHESSCoreExt

using CHESSParsers, CHESSCore, DataFrames

function CHESSParsers.record_reads!(labware::Labware, lr::LabwareRead; well_map=identity, instrument::Union{Location,Nothing}=nothing,
        layout::Union{Nothing,DataFrame}=nothing)
    kind = read_kinds[Symbol(lr.metadata["read_kind"])]
    match_labware = !isnothing(layout) && hasproperty(layout, :labware)
    labware_name = match_labware ? name(labware) : nothing
    for row in eachrow(lr.data)
        wellname = well_map(row.well)
        well = labware[wellname]
        value = is_quantitative(kind) ? row.value * kind.unit : row.value
        t = hasproperty(row, :time) ? row.time : nothing
        ismissing(t) && (t = nothing)
        record_read!(well, Read(kind, value, t); instrument)
        if !isnothing(layout)
            idx = if match_labware
                findfirst(i -> layout.well[i] == wellname && isequal(layout.labware[i], labware_name), 1:nrow(layout))
            else
                findfirst(==(wellname), layout.well)
            end
            if !isnothing(idx)
                row_metadata = layout.metadata[idx]
                for (k, v) in lr.metadata
                    k == "read_kind" && continue
                    row_metadata[Symbol("chessparsers.$k")] = v
                end
            end
        end
    end
    return labware
end

function CHESSParsers.record_reads!(labware::Labware, lrs::Vector{LabwareRead}; kwargs...)
    for lr in lrs
        CHESSParsers.record_reads!(labware, lr; kwargs...)
    end
    return labware
end

end # module CHESSParsersCHESSCoreExt
