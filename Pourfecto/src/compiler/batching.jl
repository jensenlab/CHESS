# batching functions group multiple dispenses under a single aspirate, bounded by channel
# capacity, for instruments whose piston supports MultiRepeater dispensing. Instrument-agnostic:
# operates on CartesianIndex grid positions and scalar volumes/capacities only.

"""
    DispenseItem(col, position, volume)

One destination dispense, prior to being grouped into an aspirate batch.

- `col`: index back into the caller's source transfer-list row space (traceability only, unused
  by the batching/ordering algorithms themselves).
- `position`: grid position (`CartesianIndex(row,col)`) of the destination well.
- `volume`: transfer volume, in the same units as the capacity passed to `split_oversized`/`cluster_batches`.
"""
struct DispenseItem
    col::Int
    position::CartesianIndex
    volume::Real
end

"""
    grid_distance(a::CartesianIndex, b::CartesianIndex) -> Float64

Euclidean distance between two wells in `(row,col)` grid-index space. There is no physical
well-pitch/spacing data in the labware type system, so this is plain grid distance, not a
physical mm distance.
"""
grid_distance(a::CartesianIndex, b::CartesianIndex) = sqrt(sum(abs2, (a - b).I))

"""
    split_oversized(items::Vector{DispenseItem}, capacity::Real) -> Vector{DispenseItem}

Split any item whose `volume` exceeds `capacity` into `ceil(volume/capacity)` chunks, each
`≤ capacity` (the final chunk carries the remainder). Items already `≤ capacity` pass through
unchanged. Chunks keep the same `col`/`position` as their source item, so a later batching step
is free to either re-merge them into the same batch or spread them across different batches.
Preserves total volume exactly.
"""
function split_oversized(items::Vector{DispenseItem}, capacity::Real)
    out = DispenseItem[]
    for item in items
        remaining = item.volume
        if remaining <= capacity
            push!(out, item)
            continue
        end
        while remaining > 0
            chunk = min(remaining, capacity)
            push!(out, DispenseItem(item.col, item.position, chunk))
            remaining -= chunk
        end
    end
    return out
end

"""
    cluster_batches(items::Vector{DispenseItem}, capacity::Real; max_items::Union{Nothing,Int}=nothing) -> Vector{Vector{DispenseItem}}

Greedily partition `items` (already `split_oversized`) into capacity-bounded batches: each
batch's summed `volume` stays `≤ capacity`. Batch membership favors spatial locality -- each
batch opens from an unassigned seed item (largest remaining volume first, a reasonable
first-fit-decreasing tiebreak) and then repeatedly pulls in whichever still-unassigned,
capacity-fitting item is nearest (by `grid_distance`) to any item already in the batch, until
nothing more fits (or `max_items` is reached). Every input item ends up in exactly one output
batch.
"""
function cluster_batches(items::Vector{DispenseItem}, capacity::Real; max_items::Union{Nothing,Int}=nothing)
    unassigned = collect(1:length(items))
    batches = Vector{DispenseItem}[]
    while !isempty(unassigned)
        # seed the batch with the largest remaining volume, to pack tightly first
        seed = argmax(i -> items[i].volume, unassigned) # argmax(f,itr) returns the maximizing element of itr, i.e. the item index itself
        deleteat!(unassigned, findfirst(==(seed), unassigned))

        batch = DispenseItem[items[seed]]
        used = items[seed].volume

        while !isempty(unassigned)
            if !isnothing(max_items) && length(batch) >= max_items
                break
            end
            # nearest unassigned, capacity-fitting item to any item currently in the batch
            best_pos = nothing
            best_dist = Inf
            for (k, i) in enumerate(unassigned)
                items[i].volume + used > capacity && continue
                d = minimum(grid_distance(items[i].position, b.position) for b in batch)
                if d < best_dist
                    best_dist = d
                    best_pos = k
                end
            end
            isnothing(best_pos) && break
            chosen = unassigned[best_pos]
            deleteat!(unassigned, best_pos)
            push!(batch, items[chosen])
            used += items[chosen].volume
        end

        push!(batches, batch)
    end
    return batches
end

"""
    order_greedy(batch::Vector{DispenseItem}) -> Vector{DispenseItem}

Nearest-neighbor tour: start from the batch's first item, repeatedly append the unvisited item
nearest (by `grid_distance`) to the last-appended item's position.
"""
function order_greedy(batch::Vector{DispenseItem})
    length(batch) <= 1 && return copy(batch)
    remaining = collect(2:length(batch))
    tour = DispenseItem[batch[1]]
    current = batch[1]
    while !isempty(remaining)
        best_pos = argmin(k -> grid_distance(current.position, batch[remaining[k]].position), eachindex(remaining))
        chosen = remaining[best_pos]
        deleteat!(remaining, best_pos)
        push!(tour, batch[chosen])
        current = batch[chosen]
    end
    return tour
end

const _order_exact_max_items = 8

# No Combinatorics.jl dependency in this project -- a small recursive permutation generator is
# all that's needed here, since order_exact only ever calls this on ≤ _order_exact_max_items
# elements (≤ 40320 permutations).
function _permutations(v::AbstractVector)
    length(v) <= 1 && return [v]
    perms = Vector{eltype(v)}[]
    for i in eachindex(v)
        rest = vcat(v[1:i-1], v[i+1:end])
        for p in _permutations(rest)
            push!(perms, vcat(v[i], p))
        end
    end
    return perms
end

"""
    order_exact(batch::Vector{DispenseItem}) -> Vector{DispenseItem}

Exact minimum-total-travel-distance ordering, found by brute-force permutation search over
`batch`, minimizing the sum of consecutive `grid_distance`s. Batches are small (bounded by
`capacity`/typical dispense volume), so this stays cheap; a batch larger than
`$(_order_exact_max_items)` items falls back to [`order_greedy`](@ref) with a warning rather
than paying the factorial cost. No solver is used here: at this scale, per-batch solver
startup overhead would dominate a plain permutation search.
"""
function order_exact(batch::Vector{DispenseItem})
    n = length(batch)
    n <= 1 && return copy(batch)
    if n > _order_exact_max_items
        @warn "order_exact: batch of $n items exceeds the exact-ordering cap of $_order_exact_max_items; falling back to order_greedy"
        return order_greedy(batch)
    end
    best_tour = batch
    best_len = Inf
    for perm in _permutations(collect(1:n))
        len = sum(grid_distance(batch[perm[i]].position, batch[perm[i+1]].position) for i in 1:n-1)
        if len < best_len
            best_len = len
            best_tour = batch[perm]
        end
    end
    return best_tour
end

"""
    order_batch(batch::Vector{DispenseItem}, method::Symbol) -> Vector{DispenseItem}

Dispatches to [`order_greedy`](@ref) or [`order_exact`](@ref) based on `method` (`:greedy` or
`:exact`).
"""
function order_batch(batch::Vector{DispenseItem}, method::Symbol)
    method === :greedy && return order_greedy(batch)
    method === :exact && return order_exact(batch)
    throw(ArgumentError("order_batch: unknown method $method, expected :greedy or :exact"))
end

"""
    tip_change_flags(batch_sources::Vector, windowsize::Int) -> Vector{Int}

Per-batch analogue of a shot-level sliding-window tip-change heuristic: given `batch_sources[i]`
(the source identity of the i-th aspirate batch, in emission order), returns a `0`/`1` flag per
batch. `flags[1]` is always `0` (no forced change on the very first aspirate -- there is no
prior tip to distinguish it from). For `i > 1`, `flags[i] == 1` if the source changed from batch
`i-1`, or if no source-change occurred anywhere in the trailing `windowsize`-batch window ending
at `i` (forcing a periodic refresh even when the same source is reused across many batches).
"""
function tip_change_flags(batch_sources::Vector, windowsize::Int)
    n = length(batch_sources)
    flags = zeros(Int, n)
    for i in 2:n
        if batch_sources[i] != batch_sources[i-1]
            flags[i] = 1
        end
    end
    for i in 1:n-windowsize+1
        window = @view flags[i:i+windowsize-1]
        if sum(window) == 0
            flags[i+windowsize-1] = 1
        end
    end
    return flags
end
