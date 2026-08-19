"""
    assign_groups_greedy(n::Int, capacity::Int; kwargs...) -> Vector{Int}

Partition `1:n` into the minimum number of groups of at most `capacity` items
each, using simple sequential fill (items `1:capacity` -> group 1, the next
`capacity` -> group 2, ...). For this unweighted/homogeneous-item case this
achieves the provably optimal group count `cld(n, capacity)` exactly -- see
[`assign_groups_MILP`](@ref) for a formulation that generalizes to future
weighted variants, not a "better" answer today. Accepts and ignores extra
`kwargs` so it is interchangeable with [`assign_groups_MILP`](@ref) behind
[`group_solvers`](@ref).
"""
function assign_groups_greedy(n::Int, capacity::Int; kwargs...)
    n >= 0 || throw(DomainError(n, "n must be >= 0"))
    capacity >= 1 || throw(DomainError(capacity, "capacity must be >= 1"))
    return [cld(i, capacity) for i in 1:n]
end
