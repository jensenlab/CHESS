```@meta
CurrentModule = LabwarePlotting
```

# Quick Start Guide

## A flat-colored grid

```julia
using LabwarePlotting, Plots

active = trues(8,12)
colors = fill("white",8,12)
colors[2,3] = "steelblue"

plot_grid(active; fillcolors=colors, title="Example plate")
```

## A bare grid, decorated afterward

```julia
plt = plot_grid(trues(4,4))
place_shape!(plt, circle, 2, 2, 0.8; color="red")
```

## A heatmap over the grid

```julia
plt = plot_grid(trues(4,4))
values = rand(4,4)
plot_heatmap!(plt, values)
```

## Consistent role coloring

```julia
colors = role_palette([:positive, :negative, :duplicate])
colors[:positive]  # same color every time this role set is passed in, anywhere in CHESS
```

## Row naming

```julia
letter_code.(25:30)  # ["Y", "Z", "AA", "AB", "AC", "AD"]
wellnames(trues(2,3)) # ["A1" "A2" "A3"; "B1" "B2" "B3"]
```
