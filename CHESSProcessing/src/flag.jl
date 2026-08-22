"""
    flag(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
         values::AbstractDict{N,V}; relation, rule, nodes=nothing) -> (Experiment, Dict{N,Union{Missing,V}}) where {N,V}

A **null operation on `values`**: judges a `relation`-linked group without transforming any data,
unlike every other value-producing operation. `flag`'s own return value is `values`, completely
unchanged, so it can be inserted anywhere in a chain (before, after, or interleaved with
`aggregate`/`normalize`/`correct`) without perturbing the data at all.

For each anchor node (default every node in `run_map`; see `nodes`), gathers its `relation`-linked
group's raw `values` (no missing-data policy applied here -- `rule` sees exactly what's present,
including any `missing` entries, since a rule like a CV threshold needs to know when data is
literally absent to judge it) and calls `rule(group_values) -> judgment`. An anchor with no linked
group gets `missing` (nothing to judge). `judgment` can be any type `rule` returns (a `Bool`, a
category, a `(passed, reason)` tuple) -- unlike every other operation's `values`, a flag judgment is
never constrained to the `V` value type, because it's never meant to flow into `values` at all.

The judgment is written *only* into the [`ProcessingRecord`](@ref) appended to `experiment` (as that
record's `values` field, despite the name -- flag is the one operation where the record holds
something other than what the function itself returns). This is the one deliberate exception to "the
log is write-only": `merge` is the sanctioned reader of `:flag` records, since a flag's judgment
otherwise has no way to reach a caller who wants it, given `flag` never returns it as a `values` Pair.

`plate_maps` is accepted but unused -- part of the uniform six-operation signature.

See [`cv_threshold`](@ref) for a ready-made `rule`.
"""
function flag(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
               values::AbstractDict{N,V};
               relation::Union{Symbol,AbstractString},
               rule::Function,
               nodes::Union{Nothing,AbstractVector{N}}=nothing) where {N,V}
    relation_type = Symbol(relation)
    anchors = nodes === nothing ? RunMaps.runs(run_map) : nodes
    judgments = Dict{N,Any}()
    for anchor in anchors
        linked = RunMaps.linked_runs(run_map, anchor; type=relation_type)
        judgments[anchor] = isempty(linked) ? missing : rule([get(values, n, missing) for n in linked])
    end
    params = Dict{Symbol,Any}(:relation => relation_type, :rule => rule)
    experiment = append_record(experiment, :flag, params, judgments)
    return experiment, values
end

"""
    cv_threshold(max_cv::Real) -> Function

A ready-made [`flag`](@ref) `rule`: returns `true` (trustworthy) when the coefficient of variation
(`std/mean`) of a group's present values is `<= max_cv`, `false` otherwise. Returns `missing` when
fewer than two values are present (a CV needs at least two points) or when the group mean is zero
(CV undefined). Missing entries in the group are dropped before computing CV, mirroring
`combine_group`'s `:skip` behavior, but without erroring on partial missingness -- flagging a
low-replicate group as untrustworthy is `rule`'s job, not a missing-data policy violation.
"""
function cv_threshold(max_cv::Real)
    return function (group_values::AbstractVector)
        present = collect(skipmissing(group_values))
        length(present) < 2 && return missing
        m = mean(present)
        iszero(m) && return missing
        return (std(present) / m) <= max_cv
    end
end
