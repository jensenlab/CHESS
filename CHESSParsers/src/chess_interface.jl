"""
    record_reads!(labware::CHESSCore.Labware, lr::LabwareRead; well_map=identity, instrument=nothing, layout=nothing)
    record_reads!(labware::CHESSCore.Labware, lrs::Vector{LabwareRead}; kwargs...)

Record every row of `lr.data` (or every `LabwareRead` in `lrs`, e.g. the result of
[`parse_instrument_file`](@ref)) onto `labware` as a `CHESSCore.Read`, via `CHESSCore.record_read!`.
`lr.data` has `well`, `time`, and `value` columns; `lr.metadata["read_kind"]` (constant for the whole
`LabwareRead`) must already be a registered `ReadKind` (see `CHESSCore.read_kinds`, populated by
e.g. `CHESSLabConstants`).

`well_map` converts a row's `well` value to the well name used in `labware` (identity by default,
e.g. pass a function if the instrument's well-naming convention differs from `labware`'s).
`instrument` is forwarded to `record_read!` for capability checking.

`layout`, if given, is a `CHESSExperiments.Experiment`'s `:layout` metadata DataFrame (one row per
well, with a `well` column and a per-well `metadata::Dict{Symbol,Any}` column). The rest of
`lr.metadata` (everything but `"read_kind"`, which is already consumed structurally as a `ReadKind`)
is merged into the matching row's `metadata`, namespaced under `"chessparsers."` -- otherwise this
would be silently dropped on the way into `CHESSCore` since `Read` has nowhere to carry free-form
metadata; a layout row's `metadata` is the intended carrier for it. Wells with no matching row in
`layout` are recorded as before, without attaching metadata anywhere.

A design's `layout` can span multiple plates, and well names (e.g. `"A1"`) repeat across them -- when
`layout` has a `labware` column, rows are matched on `(labware, well)` (`labware` compared against
`CHESSCore.name(labware)`, this call's own `labware` argument), not `well` alone, so metadata never
lands on the wrong plate's row. Layouts without a `labware` column fall back to matching on `well`
only.

Returns `labware`.

Provided by the `CHESSCore` package extension (`using CHESSCore` activates it) -- CHESSParsers itself
has no dependency on `CHESSCore`, so this function has no methods until then. Recording also needs
`CHESSCore.read_kinds` to already contain whatever `lr.metadata["read_kind"]` names, which is the
caller's responsibility (typically via `using CHESSLabConstants` or another package that registers
the relevant `ReadKind`s) -- CHESSParsers doesn't register any itself.
"""
function record_reads! end
