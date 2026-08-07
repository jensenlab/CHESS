# A benchmark-only baseline for comparing against Pourfecto.cluster_batches (src/compiler/batching.jl).
# Not part of the library -- it isolates what distance-awareness buys over plain capacity-bounded
# packing, by using the exact same capacity bound and one-to-many capability but no notion of
# grid_distance at all.

using Pourfecto: DispenseItem

"""
    naive_cluster_batches(items::Vector{DispenseItem}, capacity::Real) -> Vector{Vector{DispenseItem}}

First-fit-by-index batching: walk `items` in the order given, accumulating into the current batch
until the next item would push its total volume over `capacity`, then start a new batch. Same
capacity bound and one-to-many capability as `Pourfecto.cluster_batches`, but with no notion of
`grid_distance` -- batch membership depends only on input order, not spatial locality.
"""
function naive_cluster_batches(items::Vector{DispenseItem}, capacity::Real)
    batches = Vector{DispenseItem}[]
    batch = DispenseItem[]
    used = zero(capacity)
    for item in items
        if !isempty(batch) && used + item.volume > capacity
            push!(batches, batch)
            batch = DispenseItem[]
            used = zero(capacity)
        end
        push!(batch, item)
        used += item.volume
    end
    isempty(batch) || push!(batches, batch)
    return batches
end
