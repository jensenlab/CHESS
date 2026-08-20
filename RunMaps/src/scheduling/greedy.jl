"""
    assign_groups_greedy(weights::Vector{Int}, capacity::Int; kwargs...) -> Vector{Int}

Partition items (given by `weights`, e.g. cluster sizes) into groups whose
total weight never exceeds `capacity`, using first-fit-decreasing (FFD):
sort items by weight descending, place each into the first group with
enough remaining capacity, opening a new group otherwise.

For uniform weights (e.g. every item weight `1`) FFD still fills each group
to capacity before opening the next, so it achieves the exact optimal group
count `cld(n, capacity)` -- a strict generalization of the previous
unweighted behavior, not a change to it. For general/mixed weights FFD is a
well-known good heuristic, **not** guaranteed exact -- see
[`assign_groups_MILP`](@ref) for an exact (given enough time) alternative.

Throws `ArgumentError` if any weight exceeds `capacity` (an item that can
never fit in any group). Accepts and ignores extra `kwargs` so it is
interchangeable with [`assign_groups_MILP`](@ref) behind
[`group_solvers`](@ref).
"""
function assign_groups_greedy(weights::Vector{Int}, capacity::Int; kwargs...)
    capacity >= 1 || throw(DomainError(capacity, "capacity must be >= 1"))
    isempty(weights) && return Int[]
    all(>=(1), weights) || throw(DomainError(weights, "weights must be >= 1"))
    maximum(weights) <= capacity || throw(ArgumentError(
        "an item's weight ($(maximum(weights))) exceeds capacity ($capacity): cannot fit in any group"))

    n = length(weights)
    order = sortperm(weights; rev=true)
    bin_remaining = Int[]
    groups = Vector{Int}(undef, n)

    for i in order
        w = weights[i]
        placed = false
        for (b, rem) in enumerate(bin_remaining)
            if rem >= w
                bin_remaining[b] -= w
                groups[i] = b
                placed = true
                break
            end
        end
        if !placed
            push!(bin_remaining, capacity - w)
            groups[i] = length(bin_remaining)
        end
    end

    return groups
end

"""
    assign_groups_greedy(n::Int, capacity::Int; kwargs...) -> Vector{Int}

Convenience overload for the unweighted/homogeneous case (every item has
weight `1`) -- equivalent to `assign_groups_greedy(fill(1, n), capacity;
kwargs...)`.
"""
assign_groups_greedy(n::Int, capacity::Int; kwargs...) = assign_groups_greedy(fill(1, n), capacity; kwargs...)
