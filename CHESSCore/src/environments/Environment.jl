
"""
    const _environment_cache

Evictable, external cache for [`environment`](@ref) results, keyed by object identity. Entries are
reclaimed automatically once a `Location` is garbage-collected.
"""
const _environment_cache = WeakKeyDict{Location,AttributeDict}()

"""
    invalidate_environment!(x::Location)

Clear the cached [`environment`](@ref) for `x` and every currently-resident descendant. Called
whenever `x`'s attributes or tree position change (`set_attribute!`, `move_into!`, `remove!`).
"""
function invalidate_environment!(x::Location)
    delete!(_environment_cache,x)
    c=children(x)
    for i in eachindex(c)
        isassigned(c,i) || continue
        invalidate_environment!(c[i])
    end
    return nothing
end

"""
    environment(x::Location)

Compute the environmental attributes of location `x`: `x`'s own non-`missing` attributes overriding
its parent's (already-computed, cached) environment.

`missing` attribute values mean "no local opinion, defer to the inherited value" and are skipped.
[`Unknown`](@ref) values are inserted like any concrete value — they assert "unknown here" down to
descendants unless a more proximal location overrides with a real reading or an explicit `missing`.

Results are cached (see [`invalidate_environment!`](@ref)); the cache is bounded by whatever's
currently resident in memory.
"""
function environment(x::Location)
    haskey(_environment_cache,x) && return _environment_cache[x]
    base = isnothing(AbstractTrees.parent(x)) ? AttributeDict() : environment(AbstractTrees.parent(x))
    out = copy(base)
    for attr in values(attributes(x))
        ismissing(value(attr)) && continue
        set_attribute!(out,attr)
    end
    _environment_cache[x]=out
    return out
end
