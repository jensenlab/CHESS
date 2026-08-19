"""
    DataFrame(map::ControlMap) -> DataFrame

One row per edge, with columns `run`, `control`, `control_type::Symbol`, and
`metadata::Dict{Symbol,Any}` (an empty `Dict` where none was set, never
`missing`).

See also: [`ControlMap(::DataFrames.AbstractDataFrame)`](@ref).
"""
function DataFrame(map::ControlMap)
    e = edges(map)
    return DataFrame(
        run=[x.run for x in e],
        control=[x.control for x in e],
        control_type=[x.control_type for x in e],
        metadata=[x.metadata for x in e],
    )
end

"""
    ControlMap(df::DataFrames.AbstractDataFrame; run_col=:run, control_col=:control,
               type_col=:control_type, metadata_col=:metadata) -> ControlMap

Reverse of `DataFrame(::ControlMap)` -- reconstructs a `ControlMap` by
`link!`-ing every row. `R`/`C` are inferred from the `run_col`/`control_col`
columns' `eltype`. `metadata_col` defaults to `:metadata` to match
`DataFrame(::ControlMap)`'s output column, so the two are round-trip
compatible by default; pass `metadata_col=nothing` to ignore a metadata
column, or a different name for a differently-shaped DataFrame.
"""
function ControlMap(df::DataFrames.AbstractDataFrame; run_col=:run, control_col=:control,
                     type_col=:control_type, metadata_col=:metadata)
    required = (run_col, control_col, type_col)
    all(c -> String(c) in names(df), required) ||
        error("DataFrame must have the following columns: $(required)")

    R = eltype(df[!, run_col])
    C = eltype(df[!, control_col])
    map = ControlMap{R,C}()

    has_metadata_col = metadata_col !== nothing && String(metadata_col) in names(df)
    for row in eachrow(df)
        md = has_metadata_col ? row[metadata_col] : nothing
        link!(map, row[run_col], row[control_col], row[type_col]; metadata=md)
    end
    return map
end
