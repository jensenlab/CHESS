"""
    normalize(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
              values::AbstractDict{N,V}; relations=[:positive, :negative], combine=Statistics.mean,
              fn, on_missing=:error, nodes=nothing) -> (Experiment, Dict{N,Union{Missing,V}}) where {N,V}

Rescale each anchor node's own value against its linked control groups. Unlike [`aggregate`](@ref),
which collapses one relation's linked group down to a replacement for the anchor's own value,
`normalize` keeps the anchor's own value and combines it *with* one or more relation-linked control
groups via `fn`.

For each anchor node (default every node in `run_map`; see `nodes`): if its own `values` entry is
`missing`, the output is `missing` (nothing to normalize) and `fn` is never called. Otherwise, for
each `relation` in `relations`, that relation's linked control nodes' `values` are reduced to one
number via `combine` (using [`combine_group`](@ref)'s missing-data policy, `on_missing`; a relation
with no linked nodes contributes `missing`). The per-relation results become `groups::Dict{Symbol,V}`,
passed to `fn(own_value, groups) -> V` alongside the anchor's own value. If a control node's own
replicate structure needs collapsing first (e.g. a control with `:duplicate`-linked replicate
controls), that's [`aggregate`](@ref)'s job, run on the control nodes beforehand -- `combine` here only
reduces across *distinct* linked control nodes for one relation, a different reduction level from
`aggregate`'s, and (unlike `aggregate`'s output) never recorded on its own.

`plate_maps` is accepted but unused -- part of the uniform six-operation signature.

Appends a [`ProcessingRecord`](@ref) (`:normalize`, params `relations`/`combine`/`fn`/`on_missing`,
this call's output `values`) to `experiment` and returns `(experiment, values)`.

See [`subtract_and_normalize`](@ref) for the repo's one existing normalization method, expressed
against this signature.
"""
function normalize(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                    values::AbstractDict{N,V};
                    relations::AbstractVector=[:positive, :negative],
                    combine::Function=mean,
                    fn::Function,
                    on_missing::Symbol=:error,
                    nodes::Union{Nothing,AbstractVector{N}}=nothing) where {N,V}
    relation_types = Symbol.(relations)
    anchors = nodes === nothing ? RunMaps.runs(run_map) : nodes
    out = Dict{N,Union{Missing,V}}()
    for anchor in anchors
        own = get(values, anchor, missing)
        if own === missing
            out[anchor] = missing
            continue
        end
        groups = Dict{Symbol,Any}()
        for relation in relation_types
            linked = RunMaps.linked_runs(run_map, anchor; type=relation)
            groups[relation] = isempty(linked) ? missing :
                                combine_group([get(values, n, missing) for n in linked], combine; on_missing=on_missing)
        end
        out[anchor] = fn(own, groups)
    end
    params = Dict{Symbol,Any}(:relations => relation_types, :combine => combine, :fn => fn, :on_missing => on_missing)
    experiment = append_record(experiment, :normalize, params, out)
    return experiment, out
end

"""
    subtract_and_normalize(own, groups::AbstractDict{Symbol}) -> Any

`(own - groups[:negative]) / (groups[:positive] - groups[:negative])` -- the repo's one existing
normalization method (previously `CHESSQC.subtract_and_normalize`), expressed as a `normalize` `fn`.
Use with `relations=[:positive, :negative]` (the default).
"""
subtract_and_normalize(own, groups::AbstractDict{Symbol}) = (own - groups[:negative]) / (groups[:positive] - groups[:negative])
