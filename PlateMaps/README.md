# PlateMaps.jl

[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/platemaps/dev/)

`PlateMaps` places nodes on plates. Given a set of nodes and the edges that relate them, it decides
which well on which plate each node occupies. A set of nodes connected by edges is never split
across plates. The core type, `PlateMap`, records which node occupies which well. `PlateMaps` works
alone, and package extensions add support for `RunMaps` and for `CHESSCore` plate kinds.

## Installation

PlateMaps is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the PlateMaps environment:

```bash
julia --project=PlateMaps
```

## Example

```julia
using PlateMaps

wells = trues(4, 4)
run_nodes = [Symbol("run$i") for i in 1:4]
edges = [mkedge(Symbol("run$i"), :pos1, :positive) for i in 1:4]
append!(edges, [mkedge(Symbol("run$i"), :neg1, :negative) for i in 1:4])

pms = schedule_platemap(wells, edges, run_nodes)   # one PlateMap for each plate used
pm = only(pms)

well_position(pm, :run1)   # the well of run1
nodes(pm)                  # every placed node
```

## Documentation

The [documentation](https://jensenlab.github.io/CHESS/platemaps/dev/) includes a Quick Start with
the `RunMaps` and `CHESSCore` extensions, multi-plate scheduling, and the table and JSON formats.
