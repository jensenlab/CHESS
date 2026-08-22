"""
    merge(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
          labeled_values::Pair{Symbol,<:AbstractDict}...) -> DataFrame

The terminal consolidator: joins `experiment.design` against whichever `values` result(s) a caller
names, one output column per `Pair` (`column_name => values`), plus a trust column per `:flag` record
found on `experiment`'s append-only log. `run_map`/`plate_maps` are accepted but unused -- part of
the uniform six-operation signature; the join itself needs neither, since a `values`/judgment `Dict`
is already keyed by the same node identity `schedule_layout` fixed as `1:nrow(experiment.design)`.

Every other operation only ever *writes* to `experiment`'s append-only log; `merge` is the one
deliberate, narrow exception that *reads* it back -- specifically for `:flag` records, since `flag`
is a null operation on `values` and never returns its judgment as something a caller could hand to
`merge` as a `values` Pair the way every other operation's output can be. Flag columns are named
`Symbol("flag_\$(i)_\$(relation)")` (1-based index over matching log records, in log order, plus the
`relation` that call judged) so multiple `flag` calls -- even against the same relation with
different rules -- get distinct columns.

A design row's node (`1:nrow(design)`) missing from a given `values`/flag `Dict` becomes `missing` in
that column, not an error -- `merge` doesn't require every input to cover every row.
"""
function merge(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                labeled_values::Pair{Symbol,<:AbstractDict}...)
    n = nrow(experiment.design)
    result = copy(experiment.design)
    result.run_index = 1:n

    for (name, values) in labeled_values
        result[!, name] = [get(values, i, missing) for i in 1:n]
    end

    for (i, record) in enumerate(processing_log(experiment))
        record.operation === :flag || continue
        relation = get(record.params, :relation, :unknown)
        col = Symbol("flag_$(i)_$(relation)")
        result[!, col] = [get(record.values, row, missing) for row in 1:n]
    end

    return result
end
