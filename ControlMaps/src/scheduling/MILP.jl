"""
    assign_groups_MILP(n::Int, capacity::Int; optimizer=_default_optimizer[], timelimit=100) -> Vector{Int}

MILP formulation of the same group-assignment problem as
[`assign_groups_greedy`](@ref): partition `1:n` into the minimum number of
groups of at most `capacity` items each. Provided as an extensible scaffold
(e.g. for a future weighted-runs variant where greedy is no longer provably
optimal) -- for the current homogeneous-item case it is exact but not
"better" than the greedy solver; both achieve the optimal group count
`cld(n, capacity)`.

# Keyword Arguments
- `optimizer`: the JuMP-compatible optimizer used to solve the model,
  defaulting to `Gurobi.Optimizer` (requires a Gurobi license). A
  license-free alternative such as `HiGHS.Optimizer` can be passed instead.
- `timelimit`: time limit in seconds for the solver.
"""
function assign_groups_MILP(n::Int, capacity::Int; optimizer=_default_optimizer[], timelimit=100)
    n >= 0 || throw(DomainError(n, "n must be >= 0"))
    capacity >= 1 || throw(DomainError(capacity, "capacity must be >= 1"))
    n == 0 && return Int[]

    G = cld(n, capacity) # provably sufficient upper bound on groups needed

    model = Model(optimizer)
    set_time_limit_sec(model, Float64(timelimit))

    @variable(model, assign[1:n, 1:G], Bin)
    @variable(model, used[1:G], Bin)

    for i in 1:n
        @constraint(model, sum(assign[i, g] for g in 1:G) == 1)
    end
    for g in 1:G
        @constraint(model, sum(assign[i, g] for i in 1:n) <= capacity * used[g])
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
