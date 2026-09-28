# CHESSDatabase API Reference

`CHESSDatabase` records every operation on `CHESSCore` objects in an append-only SQLite ledger and
rebuilds any location's state, at any point in history, by replaying it. The
[Tutorial](../tutorial.md) shows the whole cycle, and the CHESS Databases chapters of the manual
cover each part.

The functions most code uses:

- Setup: [`create_db`](@ref) and [`connect_SQLite`](@ref).
- Committing locations: [`generate_location`](@ref), [`commit_location!`](@ref), and
  [`release_location`](@ref).
- Recording operations: [`upload`](@ref), and [`update`](@ref) to amend history.
- Rebuilding state: [`reconstruct_location`](@ref) and [`reconstruct_location!`](@ref).
- The ledger itself: [`get_last_sequence_id`](@ref), [`get_sequence_id`](@ref), and
  [`append_ledger`](@ref)/[`insert_ledger`](@ref)/[`replace_ledger`](@ref).

The rest of this page also lists the lower-level upload, reconstruction, caching, and encumbrance
functions those build on.

```@autodocs
Modules = [CHESS.CHESSDatabase]
```
