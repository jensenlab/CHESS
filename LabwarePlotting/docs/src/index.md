```@meta
CurrentModule = LabwarePlotting
```

# LabwarePlotting.jl

`LabwarePlotting` is the shared plate and grid plotting layer of CHESS. It provides gridlines,
lettered rows, shape markers, heatmap overlays, and role-based colors on top of `Plots`. The several
packages that draw a grid of wells share it.

`LabwarePlotting` is a leaf package with no dependencies on other CHESS packages. It has no knowledge
of `CHESSCore.Labware`, `PlateMaps.PlateMap`, or any other domain type. Each package with its own
grid-shaped type (`CHESSCore`, `PlateMaps`, `Pourfecto`, and `CHESSProcessing`) adds a `plot` method
or plotting function for that type, built on these primitives, in a package extension or a source
file. Every package can depend on `LabwarePlotting` without a circular dependency. A new package with
a grid-shaped type follows the same convention.

## Two layers

1. **Grid skeleton.** [`plot_grid`](@ref) and [`plot_grid!`](@ref) draw the axis limits, an optional
   flat color for each cell, the gridlines, and the standard styling with lettered rows and numbered
   columns. Every plate plot in CHESS shares this skeleton.
2. **Markers and overlays.** [`place_shape!`](@ref) and [`plot_heatmap!`](@ref) handle cases that do
   not fill a whole grid: highlighting specific wells, drawing deck-slot outlines, and overlaying a
   heatmap of continuous values on the skeleton.

[`letter_code`](@ref) and [`wellnames`](@ref) name rows in bijective base 26, and
[`role_palette`](@ref) maps roles to consistent colors. Both layers use them.

The [Quick Start](@ref) shows each of these.

## Installation

LabwarePlotting is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the LabwarePlotting environment:

```bash
julia --project=LabwarePlotting
```

and load the package:

```julia
using LabwarePlotting
```
