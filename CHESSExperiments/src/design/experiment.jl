"""
    struct Experiment

The core fixture of `CHESSExperiments`. The governing rule for what belongs here versus in
`metadata`: **`design` is the plan -- the treatments under study. `metadata` is everything about
identifying, scheduling/executing, or processing that plan, not the plan itself.**

Fields:
- `design`: the design matrix itself -- one row per planned trial, one column per factor. Replication
  is structural: a treatment run 3x is just the same row appearing 3 times, not a separate field.
  Controls are deliberately **not** rows here -- an experimenter specifies how many controls they want
  (see [`register_parameter!`](@ref)/[`get_parameter`](@ref)), not additional design-matrix entries.
  This is the one field that can't collapse into `metadata`: it doesn't describe or annotate the plan,
  it *is* the plan.
- `metadata`: everything else -- name, layout (once scheduled), control counts, which QC methods
  apply, protocol notes, parsed/processed data once instruments produce it, whatever else describes,
  schedules, executes, or processes the design without being part of the design itself. See
  [`register_parameter!`](@ref)/[`get_parameter`](@ref) for typed, defaulted, validated access to
  specific keys here without `Experiment` needing to know about them in advance; unregistered keys are
  still just a raw `Dict` lookup. See [`with_parameter`](@ref) for setting a key.

Things that are already fully recoverable from `design` (e.g. "factors" = `names(design)`) don't get a
field or a registered parameter -- a plain function suffices, no storage needed either side.

A variable holding a whole `Experiment` should be named `experiment` (or `expt`), never `design` --
that name is specifically the DataFrame field (`experiment.design`).
"""
struct Experiment
    design::DataFrame
    metadata::Dict{Symbol,Any}
end

function Experiment(design::DataFrame; name::Union{AbstractString,Nothing} = nothing, metadata::AbstractDict = Dict{Symbol,Any}())
    md = Dict{Symbol,Any}(metadata)
    isnothing(name) || (md[:name] = String(name))
    return Experiment(design, md)
end

"""
    LAYOUT_COLUMNS

The required `layout` DataFrame columns. `well,row,col,run,positive,negative,run_index` are derived from
a scheduled `PlateMaps.PlateMap`/`RunMaps.RunMap` pair (see the `CHESSExperimentsRunMapsExt` extension);
`labware,location_id,metadata` are `CHESSExperiments`' own additions.
"""
const LAYOUT_COLUMNS = [:well, :row, :col, :run, :positive, :negative, :run_index, :labware, :location_id, :metadata]

function _check_layout_columns(layout::DataFrame)
    missing_cols = setdiff(LAYOUT_COLUMNS, Symbol.(names(layout)))
    isempty(missing_cols) || error("layout DataFrame is missing required columns: $missing_cols")
    return nothing
end
