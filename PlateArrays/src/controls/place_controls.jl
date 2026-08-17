

"""
    solvers 

Predefined solvers for the [`place_controls`](@ref) algorithm 

"""
const solvers = Dict(
    "exchange" => exchange,
    "MILP" => MILP
)

""" objectives 

Predefined objectives for the [`place_controls`](@ref) algorithm 
"""
const objectives = Dict(
    "hybrid" => hybrid,
    "minimax" => minimax,
    "LHS" => LHS 
)







"""
    place_controls(wells::BitMatrix,P::Int,N::Int;solver::String="exchange",objective::String="hybrid",run_order::String="ordered",rng::AbstractRNG=Random.default_rng(),kwargs...)

Place optimal controls for detecting errors in microplate experiments

# Arguments
- `wells`: A BitMatrix mask indicating the shape and active wells, use `trues(n,m)` for a full n x m plate.
- `P`: The integer number of positive controls
- `N`: The integer number of negative controls

# Keyword Arguments
- `solver`: The algorithm used to place the controls. There are currently two solvers available:
    1. exchange (default):
    2. MILP :
- `objective`: The objective the solver uses to score plate array candidates.
    1. minimax -> Minimize the maximum distance in wells from an active well to its nearest control.
    2. LHS -> Find an approximate latin hypercube sample of the available wells in the plate.
    3. hybrid (default) -> a weighted combination of both criteria
- `run_order`: how run wells are scheduled with `run_index` -- `"ordered"` (default) or `"random"`. See
  [`assign_run_index`](@ref).
- `rng`: the random number generator used by the solver and by `run_order="random"`. Pass an explicit RNG
  (e.g. `Random.Xoshiro(1234)`) for reproducible output.
"""
function place_controls(wells::BitMatrix,P::Int,N::Int;solver::String="exchange",objective::String="hybrid",run_order::String="ordered",rng::AbstractRNG=Random.default_rng(),kwargs...)
    solver_fun = solvers[solver]
    objective_fun = objectives[objective]
    P >=0 ? nothing : throw(DomainError(P,"P must be >= 0"))
    N >=0 ? nothing : throw(DomainError(N,"N must be >=  0"))
    P+N <= sum(wells) ? nothing : throw(OccupancyError("The number of controls must be less than or equal to the number of available spaces."))
    result = solver_fun(wells,P,N;objective=objective_fun,rng=rng,kwargs...)
    return assign_run_index(result;run_order=run_order,rng=rng)
end

function place_controls(platearray::PlateArray;kwargs...)
    P=sum(platearray.positives)
    N=sum(platearray.negatives)
    return place_controls(platearray.wells,P,N;kwargs...)
end

"""
    function place_controls(wells::BitMatrix,expt::Experiment;kwargs...)

Place optimal controls for detecting errors in microplate experiments

# Arguments 
- `wells`: A BitMatrix mask indicating the shape and active wells, use `trues(n,m)` for a full n x m plate.
- `expt` : An [`Experiment`](@ref) type indicating the number of runs as well as positive and negative controls 

# Keyword Arguments 
- `solver`: The algorithm used to place the controls. There are currently two solvers available: 
    1. exchange (default): 
    2. MILP : 
- `objective`: The objective the solver uses to score plate array candidates. 
    1. minimax -> Minimize the maximum distance in wells from an active well to its nearest control. 
    2. LHS -> Find an approximate latin hypercube sample of the available wells in the plate. 
    3. hybrid (default) -> a weighted combination of both criteria
"""
function place_controls(wells::BitMatrix,expt::Experiment;kwargs...)
    P = expt.positive_controls
    N = expt.negative_controls
    return place_controls(wells,P,N;kwargs...)
end