const _kw_pourfecto_default_= (;
    objective= "min_cost_flow",
    priority= PriorityDict(),
    quiet=true,
    grb_timelimit = 30,
    grb_feasibility_tol=1e-6,
    min_vol_threshold=0.1,
    require_nonzero=true,
    enforce_minimum_shot=false,
    slack_tol = 1e-2,
    config_costs = "ones(length(configs))",
    solution_tolerance = 1e-2 
)


const _kw_pourfecto_default_doc_ = (;
    objective = "Set the scheduling objective for Pourfecto. See `keys(objectives)` for options.",
    priority = "a [`PriorityDict`](@ref) that specifies which reagents take precedence over others in a plan.",
    quiet = "Supress the printout of the solver.",
    grb_timelimit = "Set the Gurobi solver's [`TimeLimit`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#timelimit) paramter.",
    grb_feasibility_tol= "Set the Gurobi solver's [`FeasibilityTol`](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#feasibilitytol) parameter.",
    min_vol_threshold = "Set the minimum volume threshold in µL. Any transfer must be at least this large.",
    require_nonzero = "If a target contains a reagent, require that some amount of that reagent is delivered, even if the optimal solution is none.", 
    enforce_minimum_shot = "Enforce the minimum shot volume constraints for each instrument. **Caution** turns the problem into an MILP.",
    slack_tol = "Set the tolerance of the slacks in the solution to stay with in a percentage of the optimal value. A value of 0.01 equates to a 1% tolerance.",
    config_costs = "Set the relative cost of using each configuration.",
    solution_tolerance = "Set the limit for the magnitude of any single slack. A value of 1 indicates that the slack can be as large as the largest target in the model. "

)


function _pourfecto_kw_doc_()
    names = collect(keys(pairs(_kw_pourfecto_default_)))

    doc_strs = map(x-> """* `$x = $(_kw_pourfecto_default_[x])`: $(_kw_pourfecto_default_doc_[x])""", names)

    return join(doc_strs,"\n")


end 



