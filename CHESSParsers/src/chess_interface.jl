"""
    record_reads!(labware::CHESSCore.Labware, lr::LabwareRead; well_map=identity, instrument=nothing)

Record every row of `lr.data` onto `labware` as a [`CHESSCore.Read`](@ref), via
[`CHESSCore.record_read!`](@ref). `lr.data` has `well`, `time`, and `value` columns;
`lr.metadata["read_kind"]` (constant for the whole `LabwareRead`) must already be a registered
`ReadKind` (see `CHESSCore.read_kinds`, populated by e.g. `CHESSLabConstants`).

`well_map` converts a row's `well` value to the well name used in `labware` (identity by default,
e.g. pass a function if the instrument's well-naming convention differs from `labware`'s).
`instrument` is forwarded to `record_read!` for capability checking.

Returns `labware`.
"""
function record_reads!(labware::Labware, lr::LabwareRead; well_map=identity, instrument::Union{Location,Nothing}=nothing)
    kind = read_kinds[Symbol(lr.metadata["read_kind"])]
    for row in eachrow(lr.data)
        well = labware[well_map(row.well)]
        value = is_quantitative(kind) ? row.value * kind.unit : row.value
        t = hasproperty(row, :time) ? row.time : nothing
        ismissing(t) && (t = nothing)
        record_read!(well, Read(kind, value, t); instrument)
    end
    return labware
end

"""
    record_reads!(labware::CHESSCore.Labware, lrs::Vector{LabwareRead}; kwargs...)

Call [`record_reads!`](@ref) for every `LabwareRead` in `lrs` (e.g. the result of
[`parse_instrument_file`](@ref), which returns one per plate/channel) against the same `labware`.
`kwargs` are forwarded to each call. Returns `labware`.
"""
function record_reads!(labware::Labware, lrs::Vector{LabwareRead}; kwargs...)
    for lr in lrs
        record_reads!(labware, lr; kwargs...)
    end
    return labware
end
