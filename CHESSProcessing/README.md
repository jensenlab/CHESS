# CHESSProcessing.jl

[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/dev/manual/processing/)

`CHESSProcessing` turns plate readings into one value for each row of an experimental design. It
provides six composable operations: `resolve`, `aggregate`, `normalize`, `correct`, `flag`, and
`merge`. Every operation takes an `Experiment`, a `RunMap`, plate maps, and a dictionary of values,
and returns the experiment and new values. Each call appends a `ProcessingRecord` to the experiment,
so the processing log shows what was done and in what order. Operations can be chained, reordered,
or skipped.

## Installation

CHESSProcessing is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the CHESSProcessing environment:

```bash
julia --project=CHESSProcessing
```

The example below also uses `CHESSExperiments`, `RunMaps`, `PlateMaps`, and `CHESSParsers`, which
are in the same repository.

## Example

```julia
using CHESSProcessing, CHESSExperiments, RunMaps, PlateMaps, CHESSParsers
using DataFrames, Dates, Statistics

# Three runs on a 2x4 plate. Run 1 has two duplicate wells (nodes 5 and 6), and every run is
# linked to a negative control (node 100) and a positive control (node 200).
occupant = Matrix{Union{Missing,Int}}([1 5 6 100; 2 3 200 missing])
plates = ["Plate 1" => PlateMap{Int}(trues(2, 4), occupant)]

rm = RunMap{Int}()
link!(rm, 1, 5, :duplicate); link!(rm, 1, 6, :duplicate)
for r in 1:3; link!(rm, r, 100, :negative); link!(rm, r, 200, :positive); end

experiment = Experiment(DataFrame(treatment = ["low", "medium", "high"]))
plate_read = LabwareRead(Dict{String,Any}("read_kind" => "Absorbance"),
    DataFrame(well = ["A1", "A2", "A3", "A4", "B1", "B2", "B3"],
              time = fill(DateTime(2026, 1, 1), 7),
              value = [0.50, 0.52, 0.48, 0.05, 0.30, 0.80, 1.00]))

experiment, resolved = resolve(experiment, rm, plates, ["Plate 1" => plate_read])
experiment, averaged = aggregate(experiment, rm, plates, resolved; relation = :duplicate, fn = mean)
experiment, normalized = normalize(experiment, rm, plates, averaged; fn = subtract_and_normalize)

merge(experiment, rm, plates, :normalized => normalized)   # one row for each design row
```

## Documentation

The [manual page](https://jensenlab.github.io/CHESS/dev/manual/processing/) describes the
operations, missing data, and corrections. The
[API reference](https://jensenlab.github.io/CHESS/dev/api/processing/) lists every function.
