# `reconstruct_history`

`reconstruct_history(location_id, facet; from, to, time, effective, order, limit, after, collapse)` returns how one
facet of a location changed between two ledger slots, as a `DataFrame`. The value at a slot `s` is the `Value` of the
last row with `SequenceID <= s`; `history_value_at(history, s)` does this lookup. For every facet, slot and `time`
that value equals the one the matching `reconstruct_*` function gives at that slot and time.

## Facets

| facet | value | `effective` |
|---|---|---|
| attribute kind or name (`:Temperature`) | the attribute value | `true` (default): nearest ancestor-or-self with a value; `false`: own events only |
| `:parent` | id of the parent, `missing` for none | `false` only |
| `:locked`, `:active` | `Bool` | `false` only |
| `:lot` | supplier, catalog number and lot of the observed lot | `false` only |
| `(:setting, name)` | value of an instrument setting (`location_id` is the instrument) | `false` only |
| a read kind | the reads of that kind, by time of the read | `false` only |

`:contents` is not available (contents history is a later phase). `encumbrances=true` throws an `ArgumentError`.

## Columns

`SequenceID`, `LedgerID`, `Time`, `Value`, `Unit`, `Origin`, `Event`.

- `Origin` is the location whose value this is. For an effective attribute it is the ancestor the value was inherited
  from; for every other history it is the location itself.
- `Event` is the operation that produced the row (`set_attribute`, `observe_attribute`, `move`, `observe_parent`,
  `set_lock`, `observe_lock`, `set_activity`, `observe_activity`, `observe_lot`, `set_instrument_setting`, `read`),
  or `cache` where a cache snapshot gives the value. For an effective attribute it is the event that changed the
  value, which can be a move of the location or of one of its ancestors.
- A history has at most one row per slot.

The first row is the state in force at `from`, carrying the slot of the event that last set it, which can lie
before `from`. A facet that was never set has no row; its default applies.

## Collapse

With `collapse=true` (default) a row is kept only if its `Value`, `Unit` or `Origin` differs from the row before.
`collapse=false` keeps every event and cache row of an own facet. An effective history is always collapsed.

## Paging

`limit` returns at most that many rows. `after` is the `SequenceID` of the last row of the previous page (the `Time`
for a read kind); the next page holds the rows after it in the chosen `order` (`:asc` or `:desc`). Only the slots
a page needs are read: the window starts small and grows until the page is full. Concatenated pages equal the
whole history in either order.

## Cost

Every query goes through the indexes; none scans `Ledger` or builds the `ledger_subset` copy. The window is read by
walking the ledger slots or by scanning the key's series, whichever is shorter. An ascending first page costs the
same at 100k and 200k ledger rows. A descending page costs about the number of slots between `to` and the page's
oldest row, bounded by the length of the series. A key whose events all lie far before `to` (the retired incubator of
the benchmark) therefore costs time proportional to its series length, as `latest_visible_event` does.

## Not covered

- Contents history, planned operations (`encumbrances`).
- Effective forms of the facets other than attributes.
- Ties between two events at the same slot are ordered by row id; the reconstruction functions do not define a
  winner there either.
