# CHESSExperiments.jl

[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/dev/manual/experiments/)

`CHESSExperiments` describes what an experiment is meant to test before anything is prepared. An
`Experiment` holds a design matrix with one row for each planned trial and one column for each
factor, together with the metadata that describes, schedules, or processes the design. The package
reads a design from a spreadsheet, resolves each row into a `CHESSCore` stock and per-plate
conditions, expands control templates for each blocking combination, and, with `RunMaps` and
`PlateMaps` loaded, schedules the design onto plates.

## Installation

CHESSExperiments is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the CHESSExperiments environment:

```bash
julia --project=CHESSExperiments
```

## Example

```julia
using CHESSExperiments, DataFrames

expt = Experiment(DataFrame(glucose = [10, 5]); name = "glucose screen")

get_parameter(expt, :name)   # "glucose screen"
expt.design                  # the design matrix
```

## Documentation

The [manual page](https://jensenlab.github.io/CHESS/dev/manual/experiments/) describes design
columns, factors, parsing a spreadsheet, controls and replicates, and scheduling onto plates. The
[API reference](https://jensenlab.github.io/CHESS/dev/api/experiments/) lists every function.
