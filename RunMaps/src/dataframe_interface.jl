"""
    DataFrame(map::RunMap) -> DataFrame

One row per edge, with columns `run`, `linked_run`, `relation_type::Symbol`,
and `metadata::Dict{Symbol,Any}` (an empty `Dict` where none was set, never
`missing`).

See also: [`RunMap(::DataFrames.AbstractDataFrame)`](@ref).
"""
function DataFrame(map::RunMap)
    e = edges(map)
    return DataFrame(
        run=[x.run for x in e],
        linked_run=[x.linked_run for x in e],
        relation_type=[x.relation_type for x in e],
        metadata=[x.metadata for x in e],
    )
end

"""
    RunMap(df::DataFrames.AbstractDataFrame; run_col=:run, linked_run_col=:linked_run,
           type_col=:relation_type, metadata_col=:metadata) -> RunMap

Reverse of `DataFrame(::RunMap)` -- reconstructs a `RunMap` by `link!`-ing
every row. `N` is `promote_type(eltype(run_col), eltype(linked_run_col))`;
falls back to `Any` when the two columns don't share a common concrete type
(a single node pool can't be `Int`-and-`String`-but-not-`Any`).
`metadata_col` defaults to `:metadata` to match `DataFrame(::RunMap)`'s
output column, so the two are round-trip compatible by default; pass
`metadata_col=nothing` to ignore a metadata column.
"""
function RunMap(df::DataFrames.AbstractDataFrame; run_col=:run, linked_run_col=:linked_run,
                type_col=:relation_type, metadata_col=:metadata)
    required = (run_col, linked_run_col, type_col)
    all(c -> String(c) in names(df), required) ||
        error("DataFrame must have the following columns: $(required)")

    N = promote_type(eltype(df[!, run_col]), eltype(df[!, linked_run_col]))
    map = RunMap{N}()

    has_metadata_col = metadata_col !== nothing && String(metadata_col) in names(df)
    for row in eachrow(df)
        md = has_metadata_col ? row[metadata_col] : nothing
        link!(map, row[run_col], row[linked_run_col], row[type_col]; metadata=md)
    end
    return map
end
