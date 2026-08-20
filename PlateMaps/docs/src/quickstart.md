```@meta
CurrentModule = PlateMaps
```

# Quick Start Guide

## Standalone scheduling

Build edges with [`mkedge`](@ref) -- `(node1, node2, role, metadata)` -- and hand them to
[`schedule_platemap`](@ref) along with the nodes you want fixed first (typically "runs") and an active-well
mask:

```julia
using PlateMaps

wells = trues(4, 4)
run_nodes = [Symbol("run$i") for i in 1:4]
edges = [mkedge(Symbol("run$i"), :pos1, :positive) for i in 1:4]
append!(edges, [mkedge(Symbol("run$i"), :neg1, :negative) for i in 1:4])

pms = schedule_platemap(wells, edges, run_nodes)
```

`schedule_platemap` always returns a `Vector{PlateMap}` -- one entry per plate actually used. Edge-connected
components are atomic (never split across plates): if everything fits on one plate, you get a 1-element
vector back.

```julia
pm = only(pms)
well_position(pm, :run1)   # CartesianIndex of run1's well
nodes(pm)                  # every placed node
```

`solver="exchange"` (default, heuristic) or `solver="MILP"` (exact, `objective=:distance` only) picks the
control-placement algorithm; `plate_solver="greedy"` (default) or `"MILP"` picks how components are binned
onto plates when more than one is needed.

## With RunMaps

`RunMaps.RunMap` models run/control relationships as a graph with open-ended `relation_type` edges -- it has
no structural "run" vs. "control" distinction, so you tell `schedule_platemap` which relation types mark a
node as *placeable* (optimized) rather than fixed:

```julia
using PlateMaps, RunMaps

rm = RunMap{Symbol}()
for i in 1:4
    link!(rm, Symbol("run$i"), :pos1, :positive)
    link!(rm, Symbol("run$i"), :neg1, :negative)
end

pms = schedule_platemap(wells, rm, (:positive, :negative))
pm = only(pms)

describe(pm, rm, :run1)   # (registered=true, outgoing_roles=[...], incoming_roles=[...], ...)
plot(pm, rm)              # role-colored layout
DataFrame(pm, rm)         # joined well + role/metadata view
```

Any node that participates, as either endpoint, in an edge whose `relation_type` is in `placeable_roles`
is placed by the control-placement stage; every other node is fixed first via `place_runs`.

## With CHESSCore

A registered plate `LocationKind` can stand in for a hand-built `wells::BitMatrix`:

```julia
using PlateMaps, CHESSCore

kind = CHESSCore.LocationKind(:MyPlate; shape=(8, 12))
pms = schedule_platemap(kind, edges, run_nodes)
```

This composes with the `RunMaps` extension automatically when both are loaded --
`schedule_platemap(kind, rm, placeable_roles; kwargs...)` works with no extra glue code.

## DataFrame and JSON interfaces

A single plate:

```julia
df = DataFrame(pm)
PlateMap(df) == pm

json_to_platemap(platemap_to_json(pm)) == pm
```

A multi-plate batch compiles into one file for each interface, disambiguated by a leading `plate` column
(DataFrame) or a `"PlateMapBatch"`-tagged wrapper (JSON):

```julia
df = DataFrame(pms)                    # one "plate" column, stacked rows
platemaps_from_dataframe(df) == pms

json_to_platemaps(platemaps_to_json(pms)) == pms
```

The `RunMaps`-joined form works the same way: `DataFrame(pms::Vector{PlateMap}, rm::RunMap)`.
