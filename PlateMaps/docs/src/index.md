```@meta
CurrentModule = PlateMaps
```

# PlateMaps.jl

`PlateMaps` places nodes on plates. Given a set of nodes and the edges that relate them, it decides
which well on which plate each node occupies. It is the placement half of plate scheduling in CHESS.

The relationships between nodes, such as which run needs which controls and which runs are
duplicates, belong to the separate package
[`RunMaps`](https://jensenlab.github.io/CHESS/dev/manual/runmaps/). `PlateMaps` has no notion of a
run or a control. Its core type, [`PlateMap`](@ref), records which node occupies which well.

## Core type

```julia
struct PlateMap{T}
    wells::BitMatrix                     # which grid cells are usable
    occupant::Matrix{Union{Missing,T}}   # which node sits in each well
end
```

`T` is the type that identifies a node. It is chosen by the caller and matches the edges, for example
an `Int`, a `Symbol`, or a `RunMap` node id. A `PlateMap` is the solution of a scheduling problem and
does not describe the problem.

## Ways to use PlateMaps

1. **Standalone.** [`mkedge`](@ref) builds edges and [`schedule_platemap`](@ref) places them. No
   other CHESS package is needed.
2. **With [`RunMaps`](https://jensenlab.github.io/CHESS/dev/manual/runmaps/).** A package extension
   that is active when both packages are loaded adds `schedule_platemap(wells, rm::RunMap,
   placeable_roles; kwargs...)` and methods of `describe`, `plot`, and `DataFrame` for a `RunMap`.
3. **With `CHESSCore`.** Another package extension adds `wells_from_locationkind` and
   `schedule_platemap(kind::CHESSCore.LocationKind, ...)`. A registered plate `LocationKind` then
   replaces a hand-built `wells::BitMatrix`. This combines with the `RunMaps` extension, so
   `schedule_platemap(kind, rm, placeable_roles; kwargs...)` works when both are loaded.

The docstrings of the extensions (`PlateMapsRunMapsExt` and `PlateMapsCHESSCoreExt`) are not part of
the [API Reference](@ref), because Documenter does not load package extensions as it loads
`PlateMaps`. The [Quick Start](@ref) shows how to use them. It also covers scheduling across
several plates and the DataFrame and JSON interfaces.

## Installation

PlateMaps is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the PlateMaps environment:

```bash
julia --project=PlateMaps
```

and load the package:

```julia
using PlateMaps
```
