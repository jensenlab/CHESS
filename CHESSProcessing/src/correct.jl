"""
    abstract type CorrectionMethod end

Common supertype for `correct`'s pluggable correction methods (see `CHESSProcessingGPExt`'s
`GPCorrection`), mirroring `CHESSExperiments.QCMethod`'s extensibility pattern. Every concrete
`CorrectionMethod` implements [`apply_correction`](@ref).
"""
abstract type CorrectionMethod end

"""
    apply_correction(method::CorrectionMethod, data::Matrix{Float64}, present::BitMatrix,
                      role_masks::Dict{Symbol,BitMatrix}) -> Matrix{Float64}

Extension point: given one plate's `data` (only meaningful where `present[i,j]` is `true` -- other
entries are placeholders, not real values), and one `BitMatrix` per relation in `role_masks` marking
that relation's control positions (e.g. `role_masks[:negative]`), return a same-shape matrix of
corrected values. `correct` only reads the returned matrix at positions where `present` was `true`.
Every concrete [`CorrectionMethod`](@ref) implements this -- no fallback.
"""
function apply_correction end

"""
    struct GPCorrection <: CorrectionMethod

Two-stage spatial correction (see `CHESSProcessingGPExt` for the actual fit, ported from
`CHESSQC.gp_correction`): first fits a Gaussian process to the *absolute* deviation of
`negative`-relation control wells from their median, corrects every present well by it, then fits a
second GP to the *relative* deviation of `positive`-relation control wells (on the already
negative-corrected data) and corrects by that. `negative`/`positive` name which keys of `correct`'s
`role_masks` each stage uses -- default `:negative`/`:positive`, matching `normalize`'s default
`relations`.

Defined here in the base package (its fields need nothing from `GaussianProcesses`) so it's nameable
without `GaussianProcesses` loaded; only [`apply_correction`](@ref)'s actual numerical fit, in
`CHESSProcessingGPExt`, needs the weak dependency.

`lengthscale`/`lb_lengthscale`/`ub_lengthscale` are the isotropic Matern(5/2) kernel's lengthscale
and its optimization bounds (same defaults as `CHESSQC`).
"""
struct GPCorrection <: CorrectionMethod
    negative::Symbol
    positive::Symbol
    lengthscale::Float64
    lb_lengthscale::Float64
    ub_lengthscale::Float64
end
GPCorrection(; negative::Symbol=:negative, positive::Symbol=:positive,
             lengthscale::Real=3.0, lb_lengthscale::Real=2.0, ub_lengthscale::Real=6.0) =
    GPCorrection(negative, positive, lengthscale, lb_lengthscale, ub_lengthscale)

"""
    correct(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
            values::AbstractDict{N,V}; method::CorrectionMethod, relations=[:positive, :negative],
            nodes=nothing) -> (Experiment, Dict{N,Union{Missing,V}}) where {N,V}

Positional/spatial correction: unlike [`normalize`](@ref) (which rescales a run's value against its
*specific* linked controls via `run_map` edges), `correct` corrects for plate-position effects using
`plate_maps` for well position and `run_map` only to know which wells, among all wells *on that
plate*, count as controls for the correction fit -- a node counts as a `relation` control if
`relation in RunMaps.roles(run_map, node)` (the same "is this node the target of at least one
`relation` edge from anything" check `normalize`'s control groups use, but here applied per-plate
rather than per-run).

Processed **per plate** (unlike `CHESSQC`'s single-plate-only `gp_correction`) -- spatial effects
are plate-specific, so each `plate_maps` entry is corrected independently; a duplicate/control
cluster spanning multiple plates (already guaranteed not to happen by `PlateMaps`/`RunMaps`
scheduling) isn't a concern here regardless. A well with a `missing` (or unresolved) `values` entry
is excluded from both the correction fit and the output for that plate -- there's no missing-data
*policy* to arbitrate here (unlike `aggregate`/`normalize`'s `on_missing`); a spatial fit simply can't
train on or correct a point it has no value for.

`nodes`, if given, restricts which occupant nodes are eligible to participate at all (fit or
correction) -- an occupant not in `nodes` is treated as if its well were empty.

Appends a [`ProcessingRecord`](@ref) (`:correct`, params `method`/`relations`, this call's output
`values`) to `experiment` and returns `(experiment, values)`.
"""
function correct(experiment::Experiment, run_map::RunMap, plate_maps::AbstractVector{<:Pair},
                  values::AbstractDict{N,V};
                  method::CorrectionMethod,
                  relations::AbstractVector=[:positive, :negative],
                  nodes::Union{Nothing,AbstractVector{N}}=nothing) where {N,V}
    relation_types = Symbol.(relations)
    allowed = nodes === nothing ? nothing : Set(nodes)
    out = Dict{N,Union{Missing,V}}()

    for (_, pm) in plate_maps, (node, _) in pm
        out[node] = missing
    end

    for (_, pm) in plate_maps
        df = PlateMaps.DataFrame(pm)
        R, C = size(pm.wells)
        data = zeros(Float64, R, C)
        present = falses(R, C)
        role_masks = Dict(r => falses(R, C) for r in relation_types)
        node_at = Dict{Tuple{Int,Int},N}()

        for row in eachrow(df)
            ismissing(row.occupant) && continue
            node = row.occupant
            allowed !== nothing && !(node in allowed) && continue
            v = get(values, node, missing)
            ismissing(v) && continue
            node_at[(row.row, row.col)] = node
            data[row.row, row.col] = v
            present[row.row, row.col] = true
            node_roles = RunMaps.roles(run_map, node)
            for r in relation_types
                r in node_roles && (role_masks[r][row.row, row.col] = true)
            end
        end

        any(present) || continue # nothing resolvable on this plate

        corrected = apply_correction(method, data, present, role_masks)
        for ((r, c), node) in node_at
            out[node] = corrected[r, c]
        end
    end

    params = Dict{Symbol,Any}(:method => method, :relations => relation_types)
    experiment = append_record(experiment, :correct, params, out)
    return experiment, out
end
