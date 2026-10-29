# `reconstruct_history`

`reconstruct_history(location_id, facet; from, to, time, effective, order, limit, after, collapse, max_closure)` returns how one
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
| `:contents` | the `Stock` of a well | `false` only |

`encumbrances=true` adds planned operations (see [Planned operations](#Planned-operations)); it applies to every facet except
`:lot`, instrument settings and reads, which have no planned operations and are unchanged.

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

## Contents

The rows of `:contents` are the snapshots of the stock of a well that `reconstruct_contents` records while it replays
the transfers, observations and discards on the well and on the wells it was filled from. `Value` is the `Stock`
(`Empty()` for an empty well) and `Unit` is `missing`. `Event` is `transfer in`, `transfer out`, `discard`,
`observe_components` or `cache`. The stock at a slot equals `reconstruct_contents` at that slot and `time`.

The replay starts at the newest cache of the well at or before `from`, and starts again at every cache of the well in
`(from, to]`, because `reconstruct_contents` does the same for the slots after a cache. A location that is not a well has
no rows. With `collapse=true` a row whose stock equals the one before it is left out.

The cost is that of `reconstruct_contents` at `to`: it grows with the transfer ancestry of the well since its newest
cache. `max_closure=n` throws an `ArgumentError` when the ancestry has more than `n` rows. An ancestry too large for the
indexed queries falls back to the whole-ledger queries, as `reconstruct_contents` does.

## Planned operations

`encumbrances=true` returns the history that `reconstruct_*(...; encumbrances=true)` gives at every slot: for every slot
`s` and every `time`, `history_value_at(history, s)` equals the matching reconstruction with `encumbrances=true`.
`encumbrances=false` is unchanged.

How the reconstructions treat planned rows, which the history follows:

- A planned row (`EncumberedMovements`, `Locks`, `Activity`, `Environments`, `Transfers`) belongs to a protocol through its
  encumbrance. It receives the pseudo-slot `get_last_sequence_id() + EncumbranceID`. The pseudo-slot orders planned rows
  among themselves (the latest wins) and puts them after every real row; it is not a slot of the ledger.
- Planned rows are not windowed by `sequence_id`. They apply when the newest visible `ProtocolEnforcement` row of the
  protocol in the query window has `IsEnforced = 1`, and they replace every real value of the same key, including real
  events that come later. The effect therefore starts at the slot of the enforcement entry and ends at the slot of an entry
  that switches enforcement off; it can start again at a later entry.
- The cache getters read the window `[0, max_cache]`, the event getters `[foot, sequence_id]`, where `foot` is the
  smallest of the newest cache slots in the batch being reconstructed. A planned row is visible only through the event
  getters, so a cache written after the enforcement entry hides it, and the result for one location can depend on the
  other locations reconstructed with it. The effective attribute of a location reconstructs its whole parent chain
  together, so it depends on the smallest foot of the chain.

In the history:

- A key with planned rows is read at the slots at which its value can change: the rows of its sources, its enforcement
  entries and the first slot. The value at each is that of the reconstruction. Where it equals the row in force, that row is
  kept. Otherwise a row is written with the event `planned move`, `planned lock`, `planned activity`,
  `planned set_attribute` or `planned transfer`, the `LedgerID` of the enforcement entry that switched the protocol on and
  the slot of that entry. Where a planned row stops applying and the key is blank again, the row has the event
  `planned ended` and the `LedgerID` of the entry that switched enforcement off.
- Keys without planned rows (the large majority) take the unchanged path.
- The effective attribute is taken from the whole chain of the location (parents and attribute owners) and is probed with
  `reconstruct_environment`, so the origin is the location that owns the value in force.
- A well whose ancestry holds a planned transfer or a planned cache of contents is probed with `reconstruct_contents`.
- Rows after the last real slot do not exist as such: the pseudo-slot is not a position in the history. A planned operation
  enforced after the last real slot is a row at the slot of its enforcement entry, which may be the last slot.
- `collapse=false` skips the merging of rows that leave the value unchanged.
- Paging and `order=:desc` work as without planned rows.

## Cost

Every query goes through the indexes; none scans `Ledger` or builds the `ledger_subset` copy. The window is read by
walking the ledger slots or by scanning the key's series, whichever is shorter. An ascending first page costs the
same at 100k and 200k ledger rows. A descending page costs about the number of slots between `to` and the page's
oldest row, bounded by the length of the series. A key whose events all lie far before `to` (the retired incubator of
the benchmark) therefore costs time proportional to its series length, as `latest_visible_event` does.

## Not covered

- Effective forms of the facets other than attributes.
- Ties between two events at the same slot are ordered by row id; the reconstruction functions do not define a
  winner there either.
