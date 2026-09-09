# Build Pourfecto `Stock` vectors from the canonical benchmark instance JSON (see
# generate_instances.py), for **planning-only** comparison (`Pourfecto.planner`, no scheduling /
# instrument geometry at all).
#
# This replaces the earlier to_pourfecto_labware.jl, which built full `Labware` grid objects and ran
# scheduling with a `single_channel` instrument config. That modeled physical pipette-head/deck
# geometry -- a capability rlforlqh's greedy/beam-search have no equivalent of (they only ever decide
# which cell to move liquid between next, never reason about an instrument). Planning-only puts both
# sides on the same footing: does an exact-match sequence of source-to-target transfers exist, and
# can you find it.
#
# Since planning mode has no notion of physical wells/position at all (`Stock` objects carry no
# location), the (row, col) each stock corresponds to is tracked ourselves, in a parallel array,
# purely so the distance metric (used identically on the other two solvers) can be computed
# afterwards from `transfers(pc)`'s source/target indices.
#
# One reagent per rlforlqh "type" ("R0", "R1", ...), created once and shared between source and
# target stocks so Pourfecto matches them by identity. Each occupied cell becomes exactly one Stock
# (`amount * u"µL" * reagent`) -- generate_instances.py already guarantees one reagent type per cell,
# so no stock here is ever a multi-reagent mixture. Cells that are empty in a given grid (no content
# to source, or nothing requested there) simply have no corresponding Stock -- unlike the old
# Labware-based version, planning mode doesn't need an explicit "deliver nothing here" placeholder:
# conservation of total mass per type between init and goal (enforced by the generator) means the
# solver must still route every source unit somewhere to hit the targets exactly.

using CHESSCore, Pourfecto, Unitful, JSON

function load_instance(path::AbstractString)
    instance = JSON.parsefile(path)
    n = instance["grid"][1]
    k = instance["n_types"]
    return instance, n, k
end

function build_reagents(k::Integer)
    return [string_to_component("R$(t)", Liquid) for t in 0:(k-1)]
end

function cells_to_stocks(cells, reagents)
    stocks = CHESSCore.Stock[]
    positions = Tuple{Int,Int}[]
    for cell in cells
        r, c, t, amt = cell["row"] + 1, cell["col"] + 1, cell["type"] + 1, cell["amount"]
        push!(stocks, amt * u"µL" * reagents[t])
        push!(positions, (r, c))
    end
    return stocks, positions
end

"""
    instance_to_stocks(path)

Returns a named tuple `(sources, targets, source_positions, target_positions, priority, n, k)`:
- `sources`, `targets`: `Vector{CHESSCore.Stock}`, one entry per occupied init/goal cell, ready to
  pass to `Pourfecto.planner`.
- `source_positions`, `target_positions`: `Vector{Tuple{Int,Int}}` giving the (row, col) each entry
  in `sources`/`targets` corresponds to, in the same order -- needed to turn `transfers(pc)`'s
  source/target indices back into grid coordinates for the distance metric.
- `priority`: exact-match `PriorityDict` covering every reagent type in this instance.
"""
function instance_to_stocks(path::AbstractString)
    instance, n, k = load_instance(path)
    reagents = build_reagents(k)

    sources, source_positions = cells_to_stocks(instance["init"], reagents)
    targets, target_positions = cells_to_stocks(instance["goal"], reagents)
    priority = Dict{String,UInt64}("R$(t)" => UInt64(0) for t in 0:(k-1))

    return (sources=sources, targets=targets, source_positions=source_positions,
            target_positions=target_positions, priority=priority, n=n, k=k)
end
