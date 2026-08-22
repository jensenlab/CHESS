"""
    aggregate(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
              values::AbstractDict{N,V}; relation=:duplicate, fn=Statistics.mean, on_missing=:error,
              nodes=nothing) -> (Experiment, Dict{N,Union{Missing,V}}) where {N,V}

Collapse a `RunMap` relation: for each anchor node (default every node in `run_map`; see `nodes`),
reduces its `relation`-linked group's `values` down to one number with `fn`. `RunMap` has no intrinsic
"run" node type -- an anchor is simply any node with outgoing `relation` edges, so a control with its
own `:duplicate`-linked replicate controls collapses exactly the same way a design row's duplicates do.

An anchor with no outgoing `relation` edges passes its own `values` entry through unchanged (a lone
node's "aggregate" is just itself); a missing anchor entry in that case stays `missing`. Group
reduction follows [`combine_group`](@ref)'s missing-data policy (`on_missing`).

`nodes` scopes which anchors are processed, but note that the output `Dict` only contains entries for
those anchors -- a downstream call reading this output (e.g. `normalize` looking up a control node's
value) won't find any node `aggregate` didn't process, even one that would have just passed through
unchanged. The default (`nodes=nothing`, every node in `run_map`) avoids this by construction; scope
`nodes` only when a caller genuinely doesn't need the rest of the graph's values to survive into the
next call.

`plate_maps` is accepted but unused -- part of `CHESSProcessing`'s uniform
`(experiment, run_map, plate_maps, values; ...)` signature shared by all six operations, so any
operation can sit in any slot of a chain without the caller checking which context arguments a
particular operation actually needs.

Appends a [`ProcessingRecord`](@ref) (`:aggregate`, params `relation`/`fn`/`on_missing`, this call's
output `values`) to `experiment` and returns `(experiment, values)` -- the returned `values` is the
live thing a caller passes as the next operation's `values` argument; the record is provenance only.
"""
function aggregate(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                    values::AbstractDict{N,V};
                    relation::Union{Symbol,AbstractString}=:duplicate,
                    fn::Function=mean,
                    on_missing::Symbol=:error,
                    nodes::Union{Nothing,AbstractVector{N}}=nothing) where {N,V}
    relation_type = Symbol(relation)
    anchors = nodes === nothing ? RunMaps.runs(run_map) : nodes
    out = Dict{N,Union{Missing,V}}()
    for anchor in anchors
        linked = RunMaps.linked_runs(run_map, anchor; type=relation_type)
        out[anchor] = if isempty(linked)
            get(values, anchor, missing)
        else
            combine_group([get(values, n, missing) for n in linked], fn; on_missing=on_missing)
        end
    end
    params = Dict{Symbol,Any}(:relation => relation_type, :fn => fn, :on_missing => on_missing)
    experiment = append_record(experiment, :aggregate, params, out)
    return experiment, out
end
