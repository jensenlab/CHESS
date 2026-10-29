# Large requests

A request for a few locations is answered key first: the rows of each location are read through an index and the visibility rule is applied to them. When the keys own a large part of the ledger, one pass over the table is cheaper than a lookup per key.

## The plan

`plan_reconstruction(locs; kind=:transfers)` returns `(path, kind, rows, ledger_rows, fraction)`.

- `rows` is the number of rows the keys own in the tables of `kind`, counted through the indexes. The kinds are `:transfers`, `:environment`, `:observations`, `:movements`, `:locks`, `:activity` and `:reads`. Superseded revisions are counted. For `:transfers` only the transfers of the keys themselves are counted, so the estimate is a lower bound for a closure.
- `path` is `:global` when `rows` exceeds `fraction` of the number of ledger entries, or when `locs` is empty, and `:local` otherwise.
- `BULK_FRACTION[]` holds the fraction. The value 0.2 is provisional and is to be calibrated by the large-scale benchmark.

Up to `LOCAL_KEY_LIMIT[]` keys (200) always take the local path. Above it the plan decides. Requests for planned operations (`encumbrances=true`) and `reconstruction_mode[] == :legacy` use the original queries as before.

## Local path with many keys

The lookups that read key first in chunks of 500 (`get_environment_attributes`, `get_content_observations`, `get_last_movement_as_child`, `get_last_movements_as_parent`, `get_locks`, `get_activity`) stay local above the key limit when the plan finds few rows. The results are those of the original queries.

## Bulk path

The transfer closure (`get_transfer_ancestors`, `get_transfer_descendents`) has a bulk path of its own. One query reads every visible transfer and discard of the window (every transfer for the descendants, which follow transfers the window hides), the rows are indexed by well in memory, and the closure of [transfer closure](transfer_closure.md) runs over them. The result equals the local path, row for row and in the same order.

The other lookups use the retained whole-ledger queries on the global path. They need an implementation of their own before those queries are removed.

## Repairing caches after an amendment

`repair_content_caches(locs, sequence_id)` rewrites the content caches of the wells whose contents the amendment can change: `locs` and the wells reached by transfers that follow the change in time, the set `trace_forward` reports. A transfer out of a well at a slot before the material arrived is not followed. The set is a subset of the structural closure (`get_transfer_descendents`), which `time_respecting=false` selects. The function returns the number of caches it rewrote.
