# Reconstruction

`CHESSDatabase` never stores "what's currently where" directly -- it stores the history of
operations, and rebuilds any state by replaying it. [`reconstruct_location(location_id,
sequence_id=get_last_sequence_id(), time=now(), max_cache=sequence_id; encumbrances=false)`](@ref)
is the entry point:

```julia-repl
julia> preview = reconstruct_location(CHESSCore.location_id(committed))

julia> CHESSCore.location_id(preview) == CHESSCore.location_id(committed)
true
```

Every call builds a **fresh, independent** object graph -- nothing returned is shared with any live
object. This makes it the sanctioned way to preview a hypothetical mutation on an already-persisted
location without side effects, mirroring the role `build_location` plays for locations that don't
exist yet:

```julia-repl
julia> real_well = children(plate1)[1,1]

julia> preview = reconstruct_location(location_id(real_well))

julia> original_stock = stock(real_well)

julia> drain!(preview)

julia> stock(real_well) == original_stock
true
```

## The cache-then-replay algorithm

Every sub-reconstruction (`reconstruct_parent`, `reconstruct_children`, `reconstruct_attributes`,
`reconstruct_contents`, `reconstruct_lock`, `reconstruct_activity`) works the same way: find the
most recent usable snapshot at or before `max_cache`, then replay only the history recorded after
that snapshot, up to `sequence_id`. `max_cache` defaults to `sequence_id`, but can be set lower on
purpose -- this is exactly how [Caching & Repair](caching-repair.md) asks "what would this look
like if this particular snapshot didn't exist yet?"

`reconstruct_location!` calls these in one bundled pass: environment first (parent chain plus
attributes), then children, contents, lock, activity, and reads.

## Environment: walking the whole ancestor chain

`reconstruct_environment` is the one genuinely different case -- it doesn't just reconstruct one
location's own overrides, it walks the full ancestor chain generation by generation, batching every
location at the same generation into one query round, until it reaches the root. Only then does it
run a single batched attribute reconstruction across the whole ancestor set, and rewire each node's
parent reference to point at the (now attribute-populated) ancestor already collected -- producing a
real, connected chain suitable for `environment(loc)` to resolve inheritance against.

## Reads: no cache layer at all

Reads never supersede each other, only accumulate -- so there is nothing to cache. `get_reads`
queries `Reads` directly, and `reconstruct_reads!` deserializes each row depending on what's stored:

- `ismissing(row.Value)` -> `missing` (no result).
- `ismissing(row.Unit)` -> the raw string as-is (the qualitative path).
- otherwise -> `parse(Float64, row.Value) * Unitful.uparse(row.Unit)` (the quantitative path).

Rows are sorted by `InstrumentTime`, falling back to the upload `Time` when the instrument didn't
report one -- the same ordering [Reads & Instrument Measurements](reads.md) relies on for `reads(loc,
kind)` to behave as a time series.

## Labware children: a correctness requirement, not just an optimization

`fetch_child_cache` **errors** outright if no child-set cache exists at all for a `Labware`:
its children are a fixed-shape grid, and that shape can't be derived from `Movements` alone --
caching a `Labware`'s children isn't optional the way it is for other reconstructions.

## Reconstructing contents: following transfer provenance

`reconstruct_contents` is the most involved reconstruction, since a well's current stock can depend
on transfers several hops removed from any single cached snapshot. It:

1. Fetches each requested well's content cache (or starts from `Empty()`, cost `0`, if none exists).
2. Finds the earliest cached snapshot among the requested set, and searches `Transfers` (and
   `EncumberedTransfers`, if `encumbrances=true`) to find every transfer that could have contributed
   material to any requested well, however many transfers back that takes.
3. Replays those transfers in the order they happened, working from an independent, temporary copy
   of each well involved -- safe here specifically because these temporary copies are standalone (no
   parent, no children) and never part of a live, connected lab.

[Caching & Repair](caching-repair.md) covers what keeps the caches this whole process leans on
correct as history gets amended.
