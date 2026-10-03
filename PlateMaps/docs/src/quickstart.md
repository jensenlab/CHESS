```@meta
CurrentModule = PlateMaps
```

# Quick Start

## Standalone scheduling

[`mkedge`](@ref) builds an edge from `(node1, node2, role, metadata)`. [`schedule_platemap`](@ref)
takes the edges, the nodes to place first (typically runs), and a mask of the active wells:

```julia
using PlateMaps

wells = trues(4, 4)
run_nodes = [Symbol("run$i") for i in 1:4]
edges = [mkedge(Symbol("run$i"), :pos1, :positive) for i in 1:4]
append!(edges, [mkedge(Symbol("run$i"), :neg1, :negative) for i in 1:4])

pms = schedule_platemap(wells, edges, run_nodes)
```

`schedule_platemap` returns a `Vector{PlateMap}` with one entry for each plate used. A set of
nodes connected by edges is never split across plates. If everything fits on one plate, the vector
has one element.

```julia
pm = only(pms)
well_position(pm, :run1)   # CartesianIndex of run1's well
nodes(pm)                  # every placed node
```

The `solver` keyword selects the control-placement algorithm: `"exchange"` is the default heuristic,
and `"MILP"` is exact and supports only `objective=:distance`. The `plate_solver` keyword selects how
connected sets are assigned to plates when more than one plate is needed: `"greedy"` is the default,
and `"MILP"` is the alternative.

## With RunMaps

`RunMaps.RunMap` models run and control relationships as a graph whose edges have a `relation_type`.
It does not distinguish runs from controls. The relation types passed to `schedule_platemap` mark
which nodes are placeable, meaning optimized, instead of fixed:

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

A node that is an endpoint of an edge whose `relation_type` is in `placeable_roles` is placed by the
control-placement stage. Every other node is placed first by `place_runs`.

## With CHESSCore

A registered plate `LocationKind` replaces a hand-built `wells::BitMatrix`:

```julia
using PlateMaps, CHESSCore

kind = CHESSCore.LocationKind(:MyPlate; shape=(8, 12))
pms = schedule_platemap(kind, edges, run_nodes)
```

This combines with the `RunMaps` extension when both are loaded, so
`schedule_platemap(kind, rm, placeable_roles; kwargs...)` works without extra code.

## DataFrame and JSON interfaces

A single plate:

```julia
df = DataFrame(pm)
PlateMap(df) == pm

json_to_platemap(platemap_to_json(pm)) == pm
```

A batch of several plates converts to one table or one JSON document. The table has a leading
`plate` column, and the JSON is wrapped with a `"PlateMapBatch"` tag:

```julia
df = DataFrame(pms)                    # one "plate" column, stacked rows
platemaps_from_dataframe(df) == pms

json_to_platemaps(platemaps_to_json(pms)) == pms
```

`DataFrame(pms::Vector{PlateMap}, rm::RunMap)` returns the same table joined with the `RunMap`.
