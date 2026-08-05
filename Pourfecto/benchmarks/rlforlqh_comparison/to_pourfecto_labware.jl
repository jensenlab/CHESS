# Build Pourfecto `Labware` objects from the canonical benchmark instance JSON (see
# generate_instances.py). Each instance is a closed-system grid-rearrangement problem, so the
# mapping is direct:
#
#   - one custom NxN-shaped LocationKind per instance side (source/target), built ad hoc via
#     CHESSCore.LocationKind + build_location rather than a registered plate kind, since no built-in
#     plate kind is big enough for a 20x20 (400-well) grid (the largest registered, WP384, is
#     16x24 = 384 wells).
#   - one reagent per rlforlqh "type" ("R0", "R1", ...), created once and shared between the source
#     and target grids so Pourfecto matches them by identity.
#   - each grid cell's stock is the sum of amount(uL) * reagent over the types present at that cell;
#     cells absent from the instance's cell list are left as CHESSCore's default empty well, which
#     `stocks(::Labware)` still enumerates (see CHESSCore/src/interop/dataframe_interface.jl:335) --
#     so a well that must end up empty is represented as an explicit "deliver nothing here" target,
#     the same full-grid-equality semantics greedy.py and beam search (after the fix in
#     beam_search_lib.py) use.
#   - priority 0 (exact match, no slack) on every reagent type, so success/failure is comparable to
#     the other two solvers' pass/fail semantics.

using CHESSCore, Pourfecto, Unitful, JSON

function load_instance(path::AbstractString)
    instance = JSON.parsefile(path)
    n = instance["grid"][1]
    k = instance["n_types"]
    return instance, n, k
end

function build_reagents(k::Integer)
    return [string_to_reagent("R$(t)", Liquid) for t in 0:(k-1)]
end

function grid_kind(n::Integer, tag::AbstractString)
    return CHESSCore.LocationKind(Symbol("BenchGrid_$(n)x$(n)_$(tag)"); shape=(n, n), socket=:Well150000)
end

function fill_grid!(lw, cells, reagents)
    acc = Dict{Tuple{Int,Int},Any}()
    for cell in cells
        r, c, t, amt = cell["row"] + 1, cell["col"] + 1, cell["type"] + 1, cell["amount"]
        term = amt * u"µL" * reagents[t]
        acc[(r, c)] = haskey(acc, (r, c)) ? acc[(r, c)] + term : term
    end
    for ((r, c), stk) in acc
        children(lw)[r, c].stock = stk
    end
    return lw
end

"""
    instance_to_labware(path; instance_id="inst")

Returns a named tuple `(source, target, positions, priority, n, k)`:
- `source`, `target`: `Labware` grids ready to pass to `pourfecto`.
- `positions`: `Vector{Tuple{Int,Int}}` giving the (row, col) of well index `i`, in the same order
  `stocks(::Labware)` enumerates wells (`vec(children(lw))`, Julia's column-major order) -- needed to
  turn `transfers(pc)`'s source/target indices back into grid coordinates for the distance metric.
- `priority`: exact-match `PriorityDict` covering every reagent type in this instance.
"""
function instance_to_labware(path::AbstractString; instance_id::AbstractString="inst")
    instance, n, k = load_instance(path)
    reagents = build_reagents(k)

    source = build_location(grid_kind(n, "src_$(instance_id)"), "source_grid_$(instance_id)")
    target = build_location(grid_kind(n, "tgt_$(instance_id)"), "target_grid_$(instance_id)")
    fill_grid!(source, instance["init"], reagents)
    fill_grid!(target, instance["goal"], reagents)

    positions = [(idx[1], idx[2]) for idx in CartesianIndices((n, n))]
    priority = Dict{String,UInt64}("R$(t)" => UInt64(0) for t in 0:(k-1))

    return (source=source, target=target, positions=positions, priority=priority, n=n, k=k)
end
