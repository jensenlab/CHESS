# LabwarePlotting.jl

[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/labwareplotting/dev/)

`LabwarePlotting` is the shared plate and grid plotting layer of CHESS. It draws gridlines, lettered
rows, shape markers, heatmap overlays, and role-based colors on top of `Plots`. It depends on no
other CHESS package. Packages with their own grid-shaped type, such as `CHESSCore`, `PlateMaps`,
`Pourfecto`, and `CHESSProcessing`, build their `plot` methods on these functions.

## Installation

LabwarePlotting is a package of the [CHESS](https://github.com/jensenlab/CHESS) repository and is installed with it. Follow the [CHESS installation instructions](https://jensenlab.github.io/CHESS/dev/#Installation), then, in the clone, start Julia with the LabwarePlotting environment:

```bash
julia --project=LabwarePlotting
```

## Example

```julia
using LabwarePlotting, Plots

active = trues(8, 12)
colors = fill("white", 8, 12)
colors[2, 3] = "steelblue"

plot_grid(active; fillcolors = colors, title = "Example plate")
```

## Documentation

The [documentation](https://jensenlab.github.io/CHESS/labwareplotting/dev/) describes the grid
skeleton, markers and overlays, and the naming and color functions.
