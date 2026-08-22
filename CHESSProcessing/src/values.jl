"""
    combine_group(group_values::AbstractVector, fn::Function; on_missing::Symbol) -> Union{Missing,Any}

Shared missing-data policy for reducing a group of linked nodes' values (`aggregate`'s `:duplicate`
group, `normalize`'s per-relation control group) down to one number with `fn`. Every
`CHESSProcessing` operation that reduces a group uses this, so the policy vocabulary is identical
everywhere:

- A **fully missing** group (nothing present) always returns `missing`, regardless of `on_missing` --
  this isn't unexpected data loss, it's "there was never anything here" (e.g. a run with no duplicates
  scheduled), and forcing an error there would punish the normal case.
- A **partially missing** group (some but not all present) is governed by `on_missing`:
  - `:error` (the default) throws -- partial data loss is exactly the surprise a caller should be
    forced to notice, not silently average over.
  - `:skip` reduces over whatever's present.
  - `:propagate` returns `missing` the moment any input is missing, regardless of how much of the
    group survives.
- A **fully present** group is always reduced with `fn`, independent of `on_missing`.
"""
function combine_group(group_values::AbstractVector, fn::Function; on_missing::Symbol)
    on_missing in (:error, :skip, :propagate) ||
        throw(ArgumentError("on_missing must be :error, :skip, or :propagate, got :$on_missing"))
    present = collect(skipmissing(group_values))
    isempty(present) && return missing
    length(present) == length(group_values) && return fn(present)
    on_missing === :error &&
        throw(ArgumentError("group has $(length(group_values) - length(present)) of $(length(group_values)) values missing; pass on_missing=:skip or :propagate to allow"))
    on_missing === :propagate && return missing
    return fn(present) # :skip
end
