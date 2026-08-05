struct InfeasibleSolveError <: Exception
    msg::String
    level::Any
    causes::Vector{NamedTuple}
end

function Base.showerror(io::IO, e::InfeasibleSolveError)
    print(io, e.msg)
end

# Groups conflicting constraints by category and returns a short, pattern-matched interpretation of
# what the combination usually means -- these are the co-occurrences we've actually seen cause
# infeasibility (see Pourfecto/test/test_problems/in_place.jl); returns nothing for unrecognized
# combinations rather than guessing.
function infeasibility_hint(grouped::Dict{Symbol,Vector{NamedTuple}})
    if haskey(grouped, :pinning) && haskey(grouped, :priority0)
        return "This usually means an in-place well's existing content includes a chemical the target never declares (so it defaults to priority-0 / must-be-zero) while being pinned to carry that chemical forward."
    elseif haskey(grouped, :pinning) && haskey(grouped, :capacity)
        return "This usually means a pinned in-place well's existing content already exceeds, or leaves no room within, its declared or physical capacity."
    elseif haskey(grouped, :overdraft) && haskey(grouped, :mass_balance)
        return "This usually means the available source material can't cover the required target composition, independent of priorities."
    else
        return nothing
    end
end

"""
    diagnose_infeasibility(model::JuMP.Model, level) -> InfeasibleSolveError

Build an `InfeasibleSolveError` explaining why `model` (already solved to an infeasible
termination status) could not be satisfied. When the active optimizer supports conflict/IIS
analysis (e.g. Gurobi), this runs `JuMP.compute_conflict!` and translates the resulting
irreducible inconsistent constraint set back into Pourfecto-level terms (source/target/chemical
names) using the registry `build_planning_model` attaches at `model.ext[:pourfecto_constraints]`.
Falls back to a generic message when conflict analysis isn't supported or the registry has no
entry for the conflicting constraints (e.g. the scheduling-stage model).
"""
function diagnose_infeasibility(model::JuMP.Model, level)
    registry = get(model.ext, :pourfecto_constraints, Dict{JuMP.ConstraintRef,NamedTuple}())
    causes = NamedTuple[]
    conflict_available = true

    try
        JuMP.compute_conflict!(model)
    catch
        conflict_available = false
    end

    if conflict_available && MOI.get(model, MOI.ConflictStatus()) == MOI.CONFLICT_FOUND
        for (con, info) in registry
            if MOI.get(model, MOI.ConstraintConflictStatus(), con) == MOI.IN_CONFLICT
                push!(causes, info)
            end
        end
    end

    if isempty(causes)
        msg = "the problem is infeasible at priority level $level. Check that the targets are consistent with the sources and any pinned in-place wells."
        if !conflict_available
            msg *= " (the active solver backend doesn't support conflict/IIS analysis, so a detailed breakdown isn't available here -- Gurobi supports it and will give a more specific diagnosis.)"
        end
        return InfeasibleSolveError(msg, level, causes)
    end

    causes = unique(causes)
    grouped = Dict{Symbol,Vector{NamedTuple}}()
    for c in causes
        push!(get!(grouped, c.category, NamedTuple[]), c)
    end

    lines = ["  - " * c.description for c in causes]
    hint = infeasibility_hint(grouped)

    msg = "the problem is infeasible at priority level $level. The following constraints cannot be satisfied together:\n" *
          join(lines, "\n") *
          (isnothing(hint) ? "" : "\n$hint")

    return InfeasibleSolveError(msg, level, causes)
end

"""
    check_solve_status!(model::JuMP.Model, level)

Inspect `model`'s termination/primal status after `optimize!` and raise a clear error if the
solve didn't produce a usable solution. `level` is used only to label the error message (a
priority level for the planning solve, or a stage name like `"scheduling"`).
"""
function check_solve_status!(model::JuMP.Model, level)
    term = termination_status(model)
    if term == MOI.OPTIMAL || term == MOI.OBJECTIVE_LIMIT
        if primal_status(model) == MOI.FEASIBLE_POINT
            println("Optimal Solution Found For Level $level")
        elseif primal_status(model) == MOI.NO_SOLUTION
            throw(error("No solution exists For Level $level"))
        end
    elseif term == MOI.TIME_LIMIT
        tl = JuMP.time_limit_sec(model)
        if primal_status(model) == MOI.FEASIBLE_POINT
            @warn "a solution was found for level $level, but it may be sub-optimal because the solver stopped due to reaching its $(tl)s time limit."
        else
            throw(error("the solver was unable to find a feasible solution for level $level in the $(tl)s time limit."))
        end
    elseif term == MOI.INFEASIBLE || term == MOI.INFEASIBLE_OR_UNBOUNDED
        throw(diagnose_infeasibility(model, level))
    else
        throw(error("the solver returned an unexpected status ($term) for level $level. This may indicate a numerical issue with the model; consult the solver's own log output for details."))
    end
    return nothing
end
