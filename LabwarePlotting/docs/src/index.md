```@meta
CurrentModule = LabwarePlotting
```

# LabwarePlotting.jl

`LabwarePlotting` is the shared plate/grid plotting layer for CHESS: gridlines, lettered rows, shape
markers, heatmap overlays, and role-based coloring, factored out of the several packages that each
draw some version of "a grid of wells" on top of `Plots`.

`LabwarePlotting` is a dependency-free leaf package -- it knows nothing about `CHESSCore.Labware`,
`PlateMaps.PlateMap`, or any other domain type. Each package that has a grid-shaped type of its own
(`CHESSCore`, `PlateMaps`, `Pourfecto`, `CHESSProcessing`) adds its own `plot` method (or plotting
function) for that type, built on these primitives, via its own package-level extension or source
file. This keeps the dependency graph a simple star (everyone can depend on `LabwarePlotting`, nothing
circular) and makes the scheme extensible: a future package with a new grid-shaped type follows the
identical convention.

## Two layers

1. **Grid skeleton** ([`plot_grid`](@ref)/[`plot_grid!`](@ref)) -- axis limits, optional per-cell flat
   color fill, gridlines, and the standard lettered-row/numbered-column styling. This is the one
   skeleton every plate plot in the CHESS ecosystem shares.
2. **Markers and overlays** ([`place_shape!`](@ref), [`plot_heatmap!`](@ref)) -- for cases that don't
   fill a whole grid: highlighting specific wells, drawing deck-slot outlines, or overlaying a
   continuous-value heatmap on top of the skeleton.

[`letter_code`](@ref)/[`wellnames`](@ref) (bijective base-26 row naming) and [`role_palette`](@ref)
(a consistent role-to-color mapping) are the supporting naming/coloring primitives used by both
layers.

See the [Quick Start Guide](@ref) for a full walkthrough.
