"""
    control_role(design, i) -> Union{Missing,Symbol}

The `:control_role` value for design row `i`, or `missing` if the column isn't present at all (an
ordinary sample-only design). `missing`/absent = an ordinary sample row.
"""
control_role(design::DataFrames.AbstractDataFrame, i::Integer) =
    hasproperty(design, :control_role) ? design[i, :control_role] : missing

"""
    _blocking_columns(design) -> Vector{Symbol}

Every registered blocking [`Factor`](@ref) present as a column in `design`, in a fixed sorted order.
The single source of truth for that order -- both [`expand_control_templates`](@ref) (which builds
`:_block_key` tuples in this order) and [`partition_by_blocking`](@ref) (which builds its group keys
in this order) must agree, or a control's tagged key and a sample row's freshly-computed key could
represent the same combination with values in different positions and silently fail to match.
"""
_blocking_columns(design) = sort([
    name for name in propertynames(design) if
    haskey(factor_registry, name) && is_blocking(factor_registry[name])
])

"""
    expand_control_templates(experiment::Experiment) -> Experiment

Materialize every control template row (a row with a non-missing `:control_role`) into one concrete
row per distinct blocking-column combination that actually occurs among the design's sample rows
(never a full cross-product of each blocking column's values independently -- only combinations that
are actually tested). A template's own `missing` cells (its wildcards, excluding
[`RESERVED_DESIGN_COLUMNS`](@ref)) get filled in from each combination; a cell the template already
gave an explicit value stays exactly as written, even across different combinations -- this is what
lets a control's own composition (e.g. "no carbon source") stay fixed while it still gets one
replicate per real block. A template with no wildcard cells at all is kept exactly as written (a
single, fully-concrete control, no `:_block_key` needed). Every ordinary sample row is validated along
the way: a `missing` value in a *blocking* factor column is only legitimate on a control template (the
wildcard signal) -- on a sample row it's an error, since a sample must specify every blocking factor's
concrete value.

Every expanded copy is tagged with a reserved `:_block_key` column recording which blocking
combination it's meant to join -- read by [`partition_by_blocking`](@ref) instead of the row's own
column values, since (as above) those can deliberately disagree with the block it belongs to. Runs
before `partition_by_blocking` in the scheduling pipeline.

Narrowed from an earlier, more general design: wildcard traversal is scoped to *registered blocking
columns* specifically (not any arbitrary missing column) -- needed to make `:_block_key` well-defined.
"""
function expand_control_templates(experiment::Experiment)
    design = experiment.design
    blocking_cols = _blocking_columns(design)

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

    combos = isempty(blocking_cols) ? [()] : unique(Tuple(design[r, c] for c in blocking_cols) for r in sample_idx)

    rows = DataFrames.DataFrame[]
    for i in 1:DataFrames.nrow(design)
        if !(i in template_idx)
            push!(rows, design[i:i, :])
            continue
        end
        wildcard_cols = [c for c in blocking_cols if ismissing(design[i, c])]
        if isempty(wildcard_cols)
            push!(rows, design[i:i, :])
            continue
        end
        isempty(combos) && throw(ArgumentError(
            "control row $i wildcards $(wildcard_cols) but no sample row provides a concrete " *
            "combination to traverse",
        ))
        for combo in combos
            r = copy(design[i:i, :])
            for (c, v) in zip(blocking_cols, combo)
                c in wildcard_cols && (r[1, c] = v)
            end
            r[!, :_block_key] = [combo]
            push!(rows, r)
        end
    end

    return Experiment(vcat(rows...; cols = :union), copy(experiment.metadata))
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

A row's group membership comes from its `:_block_key` value when [`expand_control_templates`](@ref)
set one (non-missing) -- otherwise from plain equality across `blocking_cols`, unchanged. This lets an
expanded control row join the block it's meant to serve even when its own column values (deliberately
fixed, e.g. "no carbon source") disagree with that block's real values.
"""
function partition_by_blocking(experiment::Experiment)
    design = experiment.design
    blocking_cols = _blocking_columns(design)
    has_block_key = hasproperty(design, :_block_key)

    groups = Dict{Tuple,Vector{Int}}()
    for i in 1:DataFrames.nrow(design)
        tagged = has_block_key ? design[i, :_block_key] : missing
        key = ismissing(tagged) ? Tuple(design[i, c] for c in blocking_cols) : tagged
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
