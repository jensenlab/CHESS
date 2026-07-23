# Caching & Repair

[Reconstruction](reconstruction.md) can always replay a location's entire history from nothing --
caching exists to bound how much of that history it actually has to replay.

## Taking a cache

`cache` (`loc, sequence_id=nothing, time=now()`) is an explicit, manually-invoked snapshot --
not automatic on every write, and not on any scheduler. It asserts `loc` (and everything nested
within it) is already committed before writing anything:

```julia-repl
julia> cache(committed)

julia> preview = reconstruct_location(CHESSCore.location_id(committed))
```

A call to `cache` writes one row per applicable sub-state table -- parent, children, environment,
lock/activity, and (for a `Well` only) contents -- each stamped with the `Ledger` revision current
at `sequence_id`. It doesn't recurse into children automatically; callers decide what to snapshot
and when.

## Deduplicating expensive sub-objects

The sub-objects most expensive to store repeatedly -- a location's child set, its attribute set, a
well's stock -- are shared automatically when identical: `CachedChildSets`, `CachedAttributeSets`,
and `CachedStocks` each store one copy of a given child-set, attribute-set, or stock, so many
locations that happen to have an identical one at cache time reuse that same stored copy instead of
duplicating it:

```julia-repl
julia> sid1 = cache(big_stock)

julia> sid2 = cache(big_stock)

julia> sid1 == sid2
true
```

## Repair: keeping caches correct as history changes

Amending history (via `update` with [`replace_ledger`](@ref)/[`insert_ledger`](@ref), see
[Committing & Uploading](committing-uploading.md)) can invalidate a cache taken after the amended
point. `process_update` runs two steps automatically, in order:

**`validate(ledger_id)`** -- forces a full forward replay of everything downstream of the edit, all
the way to `get_last_sequence_id()`, with the relevant cache masked out (`max_cache` set to just
before it). This exists purely to let any physically-impossible state the edit created (a negative
stock, an overfilled well) surface as a real error rather than silently persisting.

**`cache_repair(ledger_id)`** -- figures out what kind of operation was edited
(`isa_transfer`/`isa_movement`/`isa_environment_attribute`/`isa_lock`/`isa_activity`) and repairs
the matching cache. It finds every cache reachable from the edited sequence point onward, and for
each, recomputes the value with that specific cache masked out (`max_cache = cache_seq_id - 1`). If
the recomputed value differs from what the stale cache held -- or the cache's own history has
itself since been amended -- a new cache row is written to supersede the old one **going forward
only**. The old row is never deleted, so a reconstruction query asking "as of an earlier moment"
still sees exactly what it saw before the repair.

## A real repair sequence

`test_cache_repair.jl`'s own exercise (no assertions -- its only job is to not throw):

```julia
cr_a = reconstruct_location(27, 53)
cr_b = reconstruct_location(25, 53)
update(transfer!, cr_a, cr_b, 1u"g"; ledger_id=replace_ledger(54))

cache(cr_a)
cache(cr_b)

cr_a = reconstruct_location(27, 53)
cr_b = reconstruct_location(25, 53)
update(transfer!, cr_a, cr_b, 7u"g"; ledger_id=insert_ledger(54))
```

The first `update` amends an existing transfer; the two `cache` calls snapshot the result; the
second `update` inserts a brand-new transfer earlier in the same history, exercising repair against
caches that were themselves just taken.

[Encumbrances](encumbrances.md) covers the next topic: non-binding, future-dated reservations that
sit alongside this same ledger without touching the canonical history tables at all.
