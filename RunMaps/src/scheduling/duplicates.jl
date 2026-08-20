"""
    default_duplicate_id_factory(run, replicate_index::Int) -> Symbol

Default `duplicate_id_factory` for [`schedule_duplicates`](@ref). Produces a
readable, debuggable `Symbol` of the form `RUN_dupREPLICATE`, e.g.
`:A_dup1`, `:A_dup2`.
"""
default_duplicate_id_factory(run, replicate_index::Int) = Symbol("$(run)_dup$(replicate_index)")

"""
    schedule_duplicates(runs::Vector{R}, n_duplicates::Int;
                         duplicate_id_factory::Function=default_duplicate_id_factory) where {R} -> RunMap{N}

Build a brand-new `RunMap` linking every run in `runs` to `n_duplicates`
freshly created duplicate nodes via `link!(map, run, dup, :duplicate)` (run
is the edge's subject, the duplicate is its linked node).

Every run is registered even when `n_duplicates == 0`, so the run is still
present for a downstream stage (e.g. [`schedule_controls!`](@ref)) to see.

Since this builds a fresh map, `runs(map)` immediately after calling gives
exactly "originals + duplicates, nothing else yet" -- the natural
`active_runs` input for chaining into [`schedule_controls!`](@ref).

# Arguments
- `runs`: flat list of run node ids to duplicate.
- `n_duplicates`: number of duplicate nodes to create per run. Must be `>= 0`.

# Keyword Arguments
- `duplicate_id_factory`: `(run, replicate_index::Int) -> id` called once per
  duplicate node to create; defaults to [`default_duplicate_id_factory`](@ref).

# Node type resolution
The resulting `RunMap{N}` uses `N = promote_type(eltype(runs), typeof(first
generated id))`, falling back to `Any` whenever the run type and the
generated-id type don't coincide -- mirrors
[`schedule_uniform_controls`](@ref)'s resolution rule. When `runs` is empty
or `n_duplicates == 0`, no id is ever generated, so the result is typed
`RunMap{R}` directly.
"""
function schedule_duplicates(runs::Vector{R}, n_duplicates::Int;
                              duplicate_id_factory::Function=default_duplicate_id_factory) where {R}
    n_duplicates >= 0 || throw(DomainError(n_duplicates, "n_duplicates must be >= 0"))

    if isempty(runs) || n_duplicates == 0
        map = RunMap{R}()
        for r in runs
            add_run!(map, r)
        end
        return map
    end

    cached_first_id = duplicate_id_factory(runs[1], 1)
    id_type = typeof(cached_first_id)
    N = promote_type(R, id_type)

    map = RunMap{N}()
    for run in runs
        for i in 1:n_duplicates
            did = (run == runs[1] && i == 1) ? cached_first_id : duplicate_id_factory(run, i)
            link!(map, run, did, :duplicate)
        end
    end

    return map
end
