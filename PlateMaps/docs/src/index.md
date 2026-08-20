```@meta
CurrentModule = PlateMaps
```

# PlateMaps.jl

`PlateMaps` is the physical-placement half of plate scheduling in CHESS: given a set of nodes and the
edges that relate them, it decides *where on a plate* (or plates) each node goes.

The relationship half -- deciding *what* is connected to *what* (which run needs which controls, which
runs are duplicates of each other, and so on) -- is deliberately a separate concern, owned by the sibling
package [`RunMaps`](https://jensenlab.github.io/CHESS/runmaps/dev/). `PlateMaps` has no built-in notion of
"run" or "control": its core type, [`PlateMap`](@ref), just tracks which node occupies which well.

## Core type

```julia
struct PlateMap{T}
    wells::BitMatrix                     # which grid cells are usable
    occupant::Matrix{Union{Missing,T}}   # which node sits in each well
end
```

`T` is the caller-chosen node-identity type (an `Int`, a `Symbol`, a `RunMap` node id -- whatever the
edges use). `PlateMap` is the *solution* to a scheduling problem, not the problem statement.

## Three ways to use it

1. **Standalone, dependency-free.** Build your own edges with [`mkedge`](@ref) and call
   [`schedule_platemap`](@ref) directly -- no other CHESS package required.
2. **With [`RunMaps`](https://jensenlab.github.io/CHESS/runmaps/dev/).** A weak-dependency extension
   (loaded automatically when both packages are `using`'d) adds `schedule_platemap(wells, rm::RunMap,
   placeable_roles; kwargs...)`, plus `RunMap`-aware `describe`, `plot`, and `DataFrame` methods.
3. **With `CHESSCore`.** Another weak-dependency extension adds `wells_from_locationkind` and
   `schedule_platemap(kind::CHESSCore.LocationKind, ...)`, so a registered plate `LocationKind` can stand
   in for a hand-built `wells::BitMatrix` -- and composes with the `RunMaps` extension automatically
   (`schedule_platemap(kind, rm, placeable_roles; kwargs...)` works with both loaded).

Extension docstrings (`PlateMapsRunMapsExt`, `PlateMapsCHESSCoreExt`) aren't pulled into the
[API Reference](@ref) page's `@autodocs` block, since `Documenter` doesn't load weak-dependency extension
modules the way it loads `PlateMaps` itself -- see the [Quick Start Guide](@ref) for their usage instead.

See the [Quick Start Guide](@ref) for a full walkthrough, including multi-plate scheduling and the
DataFrame/JSON interfaces.
