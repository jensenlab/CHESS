# RunMaps.jl

[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/dev/manual/runmaps/)

`RunMaps` records how the runs of an experiment relate to each other: which controls validate which
sample and which wells are duplicates of the same treatment. A `RunMap` is a set of nodes joined by
directed, labeled links. The package also schedules controls and duplicates for common layouts, with
a greedy algorithm or an optimization model, and converts a run map to a table or to JSON. It does
not decide where anything goes on a plate. `PlateMaps` places a run map onto plates.

## Installation

RunMaps is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the RunMaps environment:

```bash
julia --project=RunMaps
```

## Example

```julia
using RunMaps

rm = RunMap{Symbol}()
for r in (:A, :B, :pos, :neg); add_run!(rm, r); end
link!(rm, :A, :pos, :positive)
link!(rm, :A, :neg, :negative)
link!(rm, :B, :pos, :positive)

sort(linked_runs(rm, :A))       # [:neg, :pos]
sort(linking_runs(rm, :pos))    # [:A, :B]

# Six runs, one positive and one negative control per group, at most five nodes per group
groups = schedule_uniform_controls([1, 2, 3, 4, 5, 6], Dict(:positive => 1, :negative => 1), 5)
n_components(groups)            # 2
```

The `solver = "MILP"` option of the scheduling functions needs a Gurobi license.

## Documentation

The [manual page](https://jensenlab.github.io/CHESS/dev/manual/runmaps/) describes runs and links,
scheduling, and the table and JSON formats. The
[API reference](https://jensenlab.github.io/CHESS/dev/api/runmaps/) lists every function.
