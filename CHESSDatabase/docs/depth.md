# The `depth` keyword of `reconstruct_location`

`reconstruct_location(id; depth=d)` rebuilds only the fields of levels 0 to `d`. A depth never changes the value of a
field it fills; it only leaves later fields at the defaults of a new location. Without `depth` the call is the
whole location, as before (`depth=:legacy`).

| depth | fields filled (cumulative) | functions behind it |
|---|---|---|
| 0 | name, kind | `get_location_info` |
| 1 | parent as an id-only shell, `is_active`, `is_locked`, lot | `reconstruct_parent!`, `reconstruct_activity!`, `reconstruct_lock!`, `reconstruct_lot!` |
| 2 | whole ancestor chain, attributes (`environment`) | `reconstruct_environment!` |
| 3 | children, stock of a well | `reconstruct_children!`, `reconstruct_contents!` |
| 4 | nothing more on the location (see below) | |
| 5 | reads | `reconstruct_reads!` |

Depth 0 to 2 read the caches and events of the location and its ancestors through the indexes, so their cost does
not depend on the length of the ledger.

Without `depth` the code path is the original composition, which fills the same fields as depth 5.

## Keywords

- `report=true`: `reconstruct_location` returns `(location, report)` and `reconstruct_location!` returns the report.
  Without it the return value is the one it always had (the location, and `nothing`).
- `max_closure=n`: a well whose transfer ancestry has more than `n` rows keeps an empty stock; `report.truncated`
  contains `:contents` and `report.depth_reached` is 2. The size of the ancestry is in `report.closure_rows`.
- `children_limit=n`: a `GenericLocation` keeps its first `n` children (`:children`, `depth_reached` 2). The children
  are still found in full, so this bounds the size of the result, not the time.
- `reads_limit=n`: only the newest `n` reads are read, recorded oldest first (`:reads`; `depth_reached` is not
  lowered). The cost is that of a page of `n` reads.

A limit keyword without `depth` asks for depth 5 with the limit.

## `ReconstructionReport`

`depth_requested`, `depth_reached`, `truncated::Vector{Symbol}`, `closure_rows::Union{Int,Nothing}`,
`notes::Vector{String}`. `depth_reached` is smaller than `depth_requested` only when `max_closure` or
`children_limit` cut the work. The report is not stored on the location (a `Location` is defined in CHESSCore).

## Not covered

- Barcodes are not a field of a `Location`; they are read with `get_barcode`/`find_locations(barcode=...)`.
- Depth 4 (lineage: `trace_contents`, `trace_cost`) has no field on a `Location` to hold its result, so it adds
  nothing to the location and the report says so in `notes`.
- The history of a facet over time (section 5b of the plan) is a separate function.

## Tests

`test/test_depth.jl` compares each depth with the full reconstruction field by field on a planted state (parent chain,
attributes, lock, deactivated well, lot, transfers, reads) and tests the report and the three budgets. The equivalence
harness (`test/equivalence/test_equivalence.jl`) repeats the comparison at every generated query point for depths
0, 1, 2 and (at one point in four) 5. `benchmarks/ledger_scale/run.jl` times depth 0, 1 and 2 on a plate, a well and an
incubator.
