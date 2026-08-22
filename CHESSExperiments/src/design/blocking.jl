"""
    control_role(design, i) -> Union{Missing,Symbol}

The `:control_role` value for design row `i`, or `missing` if the column isn't present at all (an
ordinary sample-only design). `missing`/absent = an ordinary sample row.
"""
control_role(design::DataFrames.AbstractDataFrame, i::Integer) =
    hasproperty(design, :control_role) ? design[i, :control_role] : missing

"""
    expand_control_templates(experiment::Experiment) -> Experiment

Materialize every control template row (a row with a non-missing `:control_role`) into one or more
concrete rows, resolving its wildcard cells -- its own `missing` values, excluding
[`RESERVED_DESIGN_COLUMNS`](@ref) -- against whatever distinct joint combinations of those same
columns actually occur among the design's sample rows (never a full cross-product of each wildcarded
column's values independently -- only combinations that are actually tested). A template with no
wildcard cells at all is kept exactly as written (a single, fully-concrete control). Every ordinary
sample row is validated along the way: a `missing` value in a *blocking* factor column is only
legitimate on a control template (the wildcard signal) -- on a sample row it's an error, since a
sample must specify every blocking factor's concrete value.

Deliberately generic, not blocking-specific: a control's wildcard columns can be any columns left
`missing`, not only registered blocking factors -- so a control can traverse any axis the design
actually varies, with "traverse blocking combinations" simply the common case. Runs before
[`partition_by_blocking`](@ref) in the scheduling pipeline, so everything downstream sees only
fully-concrete rows and needs no control-specific handling.
"""
function expand_control_templates(experiment::Experiment)
    design = experiment.design
    blocking_cols = [
        name for name in propertynames(design) if
        haskey(factor_registry, name) && is_blocking(factor_registry[name])
    ]

    sample_idx = Int[]
    template_idx = Int[]
    for i in 1:DataFrames.nrow(design)
        if ismissing(control_role(design, i))
            push!(sample_idx, i)
        else
            push!(template_idx, i)
        end
    end

    for i in sample_idx, c in blocking_cols
        ismissing(design[i, c]) && throw(ArgumentError(
            "row $i has no :control_role but is missing a value for blocking factor :$c -- only a " *
            "designated control row may leave a blocking factor unspecified",
        ))
    end

    isempty(template_idx) && return experiment

    rows = DataFrames.DataFrame[]
    for i in 1:DataFrames.nrow(design)
        if !(i in template_idx)
            push!(rows, design[i:i, :])
            continue
        end
        wildcard_cols = [
            c for c in propertynames(design) if
            !(c in RESERVED_DESIGN_COLUMNS) && ismissing(design[i, c])
        ]
        if isempty(wildcard_cols)
            push!(rows, design[i:i, :])
            continue
        end
        combos = unique(Tuple(design[r, c] for c in wildcard_cols) for r in sample_idx)
        isempty(combos) && throw(ArgumentError(
            "control row $i wildcards $(wildcard_cols) but no sample row provides a concrete " *
            "combination to traverse",
        ))
        for combo in combos
            r = copy(design[i:i, :])
            for (c, v) in zip(wildcard_cols, combo)
                r[1, c] = v
            end
            push!(rows, r)
        end
    end

    return Experiment(reduce(vcat, rows), copy(experiment.metadata))
end

"""
    partition_by_blocking(experiment::Experiment) -> (blocking_cols::Vector{Symbol}, groups)

Group `experiment.design`'s row indices by equality across every column that's a registered
[`Factor`](@ref) with [`is_blocking`](@ref)`(f) == true` -- two rows land in the same group iff they
agree on every blocking factor's value. If there are no blocking factors at all, every row lands in
one group together (nothing to keep apart). Assumes `experiment` has already been through
[`expand_control_templates`](@ref) -- every row here is expected to have a concrete blocking value.

Returns `blocking_cols` (the blocking column names, in the fixed sorted order used to build each
group's key) alongside `groups`, a vector of `(key, rows)` named tuples -- `key` is a `Tuple` of that
group's shared blocking-factor values (in `blocking_cols` order), `rows` its design-row indices.
Groups are ordered by their first row index, for determinism.
"""
function partition_by_blocking(experiment::Experiment)
    design = experiment.design
    blocking_cols = sort([
        name for name in propertynames(design) if
        haskey(factor_registry, name) && is_blocking(factor_registry[name])
    ])

    groups = Dict{Tuple,Vector{Int}}()
    for i in 1:DataFrames.nrow(design)
        key = Tuple(design[i, c] for c in blocking_cols)
        push!(get!(groups, key, Int[]), i)
    end

    ordered = sort(collect(groups); by = kv -> first(kv[2]))
    return blocking_cols, [(key = k, rows = r) for (k, r) in ordered]
end

"""
    schedule_blocked_layout end

Partition `experiment` into blocking-homogeneous groups (see [`partition_by_blocking`](@ref)),
schedule each group independently, and merge the results into one `:layout` -- plus `:plate_conditions`
and `:well_conditions` metadata. Only available once `RunMaps` and `PlateMaps` are also loaded
(implemented in the `CHESSExperimentsRunMapsExt` package extension), same as [`schedule_layout`](@ref).
"""
function schedule_blocked_layout end
