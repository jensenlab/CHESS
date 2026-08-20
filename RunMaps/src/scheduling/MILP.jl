"""
    assign_groups_MILP(weights::Vector{Int}, capacity::Int; optimizer=_default_optimizer[], timelimit=100) -> Vector{Int}

MILP formulation of the same weighted group-assignment problem as
[`assign_groups_greedy`](@ref): partition items (given by `weights`) into
the minimum number of groups whose total weight never exceeds `capacity`.
Unlike the greedy first-fit-decreasing heuristic, this is exact (given
enough time) for general/mixed weights.

The candidate group count `G` is sized from **running greedy first** as a
valid upper bound (`G = length(unique(assign_groups_greedy(weights,
capacity)))`), since `cld(n, capacity)` is only a valid bound for uniform
weights.

Throws `ArgumentError` if any weight exceeds `capacity`.

# Keyword Arguments
- `optimizer`: the JuMP-compatible optimizer used to solve the model,
  defaulting to `Gurobi.Optimizer` (requires a Gurobi license). A
  license-free alternative such as `HiGHS.Optimizer` can be passed instead.
- `timelimit`: time limit in seconds for the solver.
"""
function assign_groups_MILP(weights::Vector{Int}, capacity::Int; optimizer=_default_optimizer[], timelimit=100)
    capacity >= 1 || throw(DomainError(capacity, "capacity must be >= 1"))
    isempty(weights) && return Int[]
    all(>=(1), weights) || throw(DomainError(weights, "weights must be >= 1"))
    maximum(weights) <= capacity || throw(ArgumentError(
        "an item's weight ($(maximum(weights))) exceeds capacity ($capacity): cannot fit in any group"))

    n = length(weights)
    G = length(unique(assign_groups_greedy(weights, capacity))) # warm upper bound

    model = Model(optimizer)
    set_time_limit_sec(model, Float64(timelimit))

    @variable(model, assign[1:n, 1:G], Bin)
    @variable(model, used[1:G], Bin)

    for i in 1:n
        @constraint(model, sum(assign[i, g] for g in 1:G) == 1)
    end
    for g in 1:G
        @constraint(model, sum(weights[i] * assign[i, g] for i in 1:n) <= capacity * used[g])
    end
    for g in 1:(G - 1)
        @constraint(model, used[g] >= used[g + 1])
    end

    @objective(model, Min, sum(used))
    optimize!(model)

    groups = Vector{Int}(undef, n)
    for i in 1:n
        for g in 1:G
            if round(Int, JuMP.value(assign[i, g])) == 1
                groups[i] = g
                break
            end
        end
    end
    return groups
end

"""
    assign_groups_MILP(n::Int, capacity::Int; kwargs...) -> Vector{Int}

Convenience overload for the unweighted/homogeneous case (every item has
weight `1`) -- equivalent to `assign_groups_MILP(fill(1, n), capacity;
kwargs...)`.
"""
assign_groups_MILP(n::Int, capacity::Int; kwargs...) = assign_groups_MILP(fill(1, n), capacity; kwargs...)
