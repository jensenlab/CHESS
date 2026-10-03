# Processing Experiment Data

```@meta
DocTestSetup = :(using CHESSProcessing, CHESSExperiments, RunMaps, PlateMaps, CHESSParsers, DataFrames, Dates, Statistics)
```

`CHESSProcessing` turns plate readings into one value per design row. It works on the pieces an
[experimental design](experiments.md) produces when it is scheduled: the `Experiment`, its
[run map](runmaps.md), and its plate maps. It is a separate package that is loaded separately from
`CHESS`.

## Operations

Processing is a chain of six small operations:

| Operation | What it does |
|:--|:--|
| [`resolve`](@ref) | Assigns each well's reading to the run-map node in that well. |
| [`aggregate`](@ref) | Collapses a group of linked nodes, such as a run and its duplicates, into one value. |
| [`normalize`](@ref) | Rescales each run against its linked control groups. |
| [`correct`](@ref) | Applies a spatial correction to each plate. |
| [`flag`](@ref) | Judges a group (for example, too variable to trust) without changing any values. |
| [`merge`](@ref) | Joins values and flags back onto the design, one row per design row. |

Every operation takes the same arguments, `(experiment, run_map, plate_maps, values; ...)`, and
returns `(experiment, values)`. `values` is a `Dict` from run-map node to number. Because the shape
is shared, operations can be chained, reordered, or skipped freely. Each call also appends a
[`ProcessingRecord`](@ref) to the experiment, so [`processing_log`](@ref) shows exactly what was
done.

## Example

Three design rows are laid out on a 2×4 plate. Run 1 has two duplicate wells (nodes 5 and 6), and
every run is linked to one negative control (node 100) and one positive control (node 200). The
plate map says which node is in each well:

```jldoctest processing
julia> using CHESSProcessing, CHESSExperiments, RunMaps, PlateMaps, CHESSParsers, DataFrames, Dates, Statistics

julia> occupant = Matrix{Union{Missing,Int}}([1 5 6 100; 2 3 200 missing]);

julia> plates = ["Plate 1" => PlateMap{Int}(trues(2, 4), occupant)];

julia> rm = RunMap{Int}();

julia> link!(rm, 1, 5, :duplicate); link!(rm, 1, 6, :duplicate);

julia> for r in 1:3; link!(rm, r, 100, :negative); link!(rm, r, 200, :positive); end

julia> experiment = Experiment(DataFrame(treatment = ["low", "medium", "high"]));
```

The plate reading is a `LabwareRead` from [CHESSParsers](parsing-instrument-files.md), built here by
hand. A real one comes from `parse_instrument_file`:

```jldoctest processing
julia> plate_read = LabwareRead(Dict{String,Any}("read_kind" => "Absorbance"),
           DataFrame(well = ["A1", "A2", "A3", "A4", "B1", "B2", "B3"],
                     time = fill(DateTime(2026, 1, 1), 7),
                     value = [0.50, 0.52, 0.48, 0.05, 0.30, 0.80, 1.00]));
```

`resolve` assigns each reading to its node, `aggregate` averages run 1 with its duplicates,
`normalize` rescales each run so the negative control is 0 and the positive control is 1, and `flag`
checks that each duplicate group's coefficient of variation is under 10%:

```jldoctest processing
julia> experiment, resolved = resolve(experiment, rm, plates, ["Plate 1" => plate_read]);

julia> experiment, averaged = aggregate(experiment, rm, plates, resolved; relation = :duplicate, fn = mean);

julia> experiment, normalized = normalize(experiment, rm, plates, averaged; fn = subtract_and_normalize);

julia> experiment, _ = flag(experiment, rm, plates, resolved; relation = :duplicate, rule = cv_threshold(0.1));

julia> [r.operation for r in processing_log(experiment)]
4-element Vector{Symbol}:
 :resolve
 :aggregate
 :normalize
 :flag
```

`merge` puts it together, one row per design row. Each named `values` result becomes a column, and
each `flag` call adds a column of its judgments, named after its position in the log and the
relation it judged (`missing` where a run had no duplicates to judge):

```jldoctest processing
julia> merge(experiment, rm, plates, :absorbance => averaged, :normalized => normalized)
3×5 DataFrame
 Row │ treatment  run_index  absorbance  normalized  flag_4_duplicate
     │ String     Int64      Float64     Float64     Bool?
─────┼────────────────────────────────────────────────────────────────
   1 │ low                1         0.5    0.473684              true
   2 │ medium             2         0.3    0.263158           missing
   3 │ high               3         0.8    0.789474           missing
```

## Missing data

When a group is only partly present (one duplicate well failed to read, say), `aggregate` and
`normalize` follow the `on_missing` keyword, shared through [`combine_group`](@ref): `:error` (the
default) throws, `:skip` uses what is present, and `:propagate` returns `missing`. A group with
nothing present is always `missing`, since that usually means nothing was scheduled.

## Corrections and plots

[`correct`](@ref) takes a [`CorrectionMethod`](@ref). [`GPCorrection`](@ref) fits Gaussian processes
to each plate's control wells to remove spatial effects such as edge evaporation; it needs the
`GaussianProcesses` package loaded. New methods implement [`apply_correction`](@ref).
[`plot_plate_data`](@ref) and [`plot_control_data`](@ref) draw values on the plate layout when
`Plots` and `LabwarePlotting` are loaded.

The [CHESSProcessing API reference](../api/processing.md) lists every function.
