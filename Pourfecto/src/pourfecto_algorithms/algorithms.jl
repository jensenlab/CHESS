function build_planning_model(sources::Vector{<:CHESSCore.Stock},
        targets::Vector{<:CHESSCore.Stock},
        params::ParameterDict;
        priority::PriorityDict=_kw_pourfecto_default_.priority,
        quiet::Bool=_kw_pourfecto_default_.quiet,
        solver_timelimit::Real = _kw_pourfecto_default_.solver_timelimit,
        grb_feasibility_tol::Real=_kw_pourfecto_default_.grb_feasibility_tol,
        min_vol_threshold=_kw_pourfecto_default_.min_vol_threshold,
        require_nonzero=_kw_pourfecto_default_.require_nonzero,
        solution_tolerance = _kw_pourfecto_default_.solution_tolerance,
        optimizer=_default_optimizer[],
        kwargs...)

    params[:priority] = priority
    params[:quiet] = quiet 
    params[:solver_timelimit] =solver_timelimit
    params[:grb_feasibility_tol] = grb_feasibility_tol 
    params[:require_nonzero] = require_nonzero
    params[:min_vol_threshold]= min_vol_threshold
    params[:n_sources] = length(sources)
    params[:n_targets] = length(targets) 
    params[:solution_tolerance] = solution_tolerance


    ## Initialization 
    check_inputs(sources,targets) # returns nothing if input checks pass. throws error otherwise 
    full_priority= update_priority(sources,targets,priority)
    params[:priority] = full_priority 

    model=Model(optimizer)
    if quiet
        set_silent(model)
    end
    set_time_limit_sec(model, solver_timelimit)
    if optimizer === Gurobi.Optimizer
        JuMP.set_attribute(model,"FeasibilityTol",grb_feasibility_tol)
    elseif JuMP.solver_name(model) == "HiGHS"
        # HiGHS's active-set QP solver can report a spurious "Solve error" on the larger,
        # tightly-bounded re-solves solve_planning_model performs (bound residuals ~1e-7 trip its
        # default tolerance on big models); loosening these tolerances avoids it. This has no
        # effect on Gurobi/SCIP, which don't hit this failure mode.
        JuMP.set_attribute(model,"primal_feasibility_tolerance",1e-4)
        JuMP.set_attribute(model,"dual_feasibility_tolerance",1e-4)
    end

    S,T = normalize_inputs(sources,targets) 
    chems = union(all_reagents(sources),all_reagents(targets))

    N_s , N_c = size(S)
    N_t , N_c = size(T)




    # Define Model variables 
    @variable(model, V[1:N_s,1:N_t]>=0) # v(s,t) = volume of material transferred from source s to target t. units of v(s,t) are in µL, as determined by normalization
    @variable(model,slacks[1:N_t,1:N_c]) # slack makes up the difference between targets and planned stocks 


    # constrain slacks to measure target stock error
    @constraint(model, V'*S .- slacks .== T ) # create the targets with the sources, allowing for some slack. This is a mass/volume balance. 


    #constraints to ensure that we don't overdraft sources
    for st in eachindex(sources)
        @constraint(model, sum(V[st,:]) <= stock_quantity(sources[st]))
    end 

    # constraints to ensure we don't overproduce targets 
    for st in eachindex(targets)
        @constraint(model,sum(V[:,st]) <= stock_quantity(targets[st]))
    end 

    if require_nonzero  # requiring nonzero transfers for each needed destination well and chemical 
        for c in 1:N_c
                srcs_with_chem=S[:,c] .> 0 
                for t in 1:N_t
                        if T[t,c] > 0 
                                @constraint(model,sum( V[:,t] .* srcs_with_chem) >=  min_vol_threshold ) # check that at least one transfer happens if an ingredient is needed in a destination, even if the optimial solution is to not dispense anything.  
                        end 
                end 
        end 
    end
    for c in 1:N_c
        if full_priority[reagent_to_string(chems[c])] == UInt(0)
                @constraint(model, slacks[:,c] .== 0) # priority 0 ingredients must hit the target exactly for each destination. The slack must be zero (because the delivered quantity must be zero)  
        end
     end 

    return model ,params 

end 





function add_node_trackers(model::JuMP.Model , source_labware,target_labware, configs, asp_nodes, disp_nodes) 

        asp_node_labware_idx = map(x->findfirst(y-> labware(x.mask) ==y,source_labware),asp_nodes)
        anli = length(asp_node_labware_idx)
        @variable(model, asp_labware[1:anli])
        @constraint(model, asp_labware .== asp_node_labware_idx)


        disp_node_labware_idx = map(x->findfirst(y-> labware(x.mask) ==y,target_labware),disp_nodes)
        dnli =length(disp_node_labware_idx)
        @variable(model,disp_labware[1:dnli])
        @constraint(model,disp_labware .== disp_node_labware_idx)


        asp_node_config_idx = map(x->findfirst(y-> x.configuration ==y,configs),asp_nodes)
        anci = length(asp_node_config_idx)
        @variable(model, asp_config[1:anci])
        @constraint(model,asp_config .== asp_node_config_idx)

        disp_node_config_idx = map(x->findfirst(y-> x.configuration ==y,configs),disp_nodes)
        dnci = length(disp_node_config_idx)
        @variable(model, disp_config[1:dnci])
        @constraint(model,disp_config .== disp_node_config_idx)


        isa_multi_repeater_piston = map(x-> repeater_style(pistons(head(x.mask))[x.piston]) == MultiRepeater,asp_nodes)
        imrp = length(isa_multi_repeater_piston)
        @variable(model,multi_repeater_piston[1:imrp])
        @constraint(model, multi_repeater_piston .== Int.(isa_multi_repeater_piston))
        

        return model 

        
end 




function build_scheduling_model(
        source_labware::Vector{<:Labware},
        target_labware::Vector{<:Labware},
        configs::Vector{<:Configuration},
        params::ParameterDict;
        enforce_minimum_shot::Bool=_kw_pourfecto_default_.enforce_minimum_shot,
        kwargs...)

        params[:enforce_minimum_shot]=enforce_minimum_shot
        params[:n_source_labware]=length(source_labware)
        params[:n_target_labware]=length(target_labware)
        params[:n_configs]=length(configs)

        sources = stocks(source_labware)
        targets = stocks(target_labware)

        M = ustrip(uconvert(u"µL",sum((q for q in CHESSCore.quantity.(sources) if !ismissing(q));init=0u"µL"))) # Empty sources contribute 0 to the big-M bound, matching stock_quantity's ismissing convention

        model, params = build_planning_model(sources,targets,params;kwargs...)


        src_wellnames = vcat(well_names.(source_labware)...)
        tgt_wellnames = vcat(well_names.(target_labware)...)
        asp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.AspNode,configs,source_labware)
        disp_nodes = Pourfecto.compute_flow_nodes(Pourfecto.DispNode,configs,target_labware)


        flow_connections = Pourfecto.compute_flow_connections(src_wellnames,tgt_wellnames,asp_nodes,disp_nodes) # compute all flow pairs that connect each pair of wells (regardless of if they are physically possible or not) 

        padding_factors = [padding_factor(a,d) for a in asp_nodes, d in disp_nodes] 


        A= length(asp_nodes)
        D = length(disp_nodes)
        S = length(sources)
        T = length(targets)

        @variable(model, Q[1:A,1:D] >= 0 )
        model = add_node_trackers(model,source_labware,target_labware,configs,asp_nodes,disp_nodes)


        if enforce_minimum_shot # This is an option because it turns the problem into an MILP
                @variable(model,QI[1:A,1:D],Bin)
                for d in 1:D
                        min_disp = minimum_shot(disp_nodes[d]) # minimum single shot volume
                        for a in 1:A
                                @constraint(model,Q[a,d] >= min_disp * QI[a,d])
                                @constraint(model, Q[a,d] <= M * QI[a,d]) # big-M constraint to force it into a range  in { 0 , [min_disp,M]}
                        end
                end
        end


        V = model[:V]


        for s in 1:S 
                for t in 1:T 
                        @constraint(model, V[s,t] == sum(Q[flow_connections[s,t]])) # main scheduling constraints mapping flows to wells 
                end 
        end 




        for a in 1:A 
                for d in 1:D 
                        if !is_valid_flow(asp_nodes[a],disp_nodes[d])
                                @constraint(model,Q[a,d] == 0)  # if the flows aren't valid constrain them to zero  
                        end 
                end 
        end 

        for s in 1:S
                flow_idxs=vcat(flow_connections[s,:]...)
                @constraint(model, sum(padding_factors[flow_idxs] .* Q[flow_idxs]) <= stock_quantity(sources[s]))  # ensure that the sum of all flows drawing from source s does not exceed the stock quantity, while accounting for the padding factor supplied by the configuration. This is the scheduling version of the "don't overdraft sources" constraint in planning
        end




        return model,params,sources,targets


end 










function solve_planning_model(
        model::JuMP.Model,
        sources::Vector{<:CHESSCore.Stock},
        targets::Vector{<:CHESSCore.Stock},
        params::ParameterDict;
        slack_tol::Real = _kw_pourfecto_default_.slack_tol,
        kwargs...)


    params[:slack_tol]=slack_tol 

    chems = union(all_reagents(sources),all_reagents(targets))


    priority = params[:priority]
    priority_levels= sort(unique(collect(values(priority))))
    slacks = model[:slacks]
    S,T=normalize_inputs(sources,targets)

    N_s= length(sources) 
    N_t = length(targets)
    N_c = length(chems) 

    # add a dummy binary variable prior to any solves if the problem will become and MILP later --
    # this workaround is Gurobi-specific ("Gurobi errors out if you add integer or binary variables
    # after solving with only continuous variables"). HiGHS/SCIP have no such restriction (confirmed
    # directly), and adding this placeholder unconditionally would turn the still-continuous planning
    # QP into a nominal MIQP for them -- which HiGHS cannot solve at all, even trivially.
    if requires_MILP(model,params;kwargs...) && JuMP.solver_name(model) == "Gurobi"
        @variable(model,MILP_placeholder, Bin)
    end


    for level in priority_levels  # pass through all priority levels from lowest to higest level


            chem_weights= falses(N_c)
            for c in 1:N_c
                    if priority[reagent_to_string(chems[c])] <= level 
                            chem_weights[c]=true # activate the weight term for this ingredient on this pass
                    end 
            end 
            set_objective_sense(model, MOI.FEASIBILITY_SENSE)
            @objective(model, Min,sum(chem_weights' .*(slacks.^2))) # penalize large slacks, search for V that minimize slacks.
            optimize!(model)

            # Check for optimality and feasibility
            term = termination_status(model)
            if term == MOI.OPTIMAL || term == MOI.OBJECTIVE_LIMIT
            if primal_status(model)==MOI.FEASIBLE_POINT
                    println("Optimal Solution Found For Level $level")
            elseif primal_status(model)==MOI.NO_SOLUTION
                    throw(error("No solution exists For Level $level"))
            end 
            elseif term == MOI.TIME_LIMIT
            if primal_status(model) == MOI.FEASIBLE_POINT
                    @warn "a solution was found for level $level, but it may be sub-optimal because the solver stopped due to reaching its $(timelimit)s  time limit."
            else 
                    throw(error("the solver was unable to find a feasible solution for level $level in the $(params[:solver_timelimit])s time limit."))
            end 
            elseif term == MOI.INFEASIBLE || term == MOI.INFEASIBLE_OR_UNBOUNDED
            println("infeasible solution")
            println(term)

            end 
            current_slacks=abs.(JuMP.value.(slacks))
            
            for c in 1:N_c
                    if chem_weights[c]
                            delta=slack_tol * T[:,c] # delta is the tolerance we give to updating the slack in higher priority levels, it is some fraction of the dispense target quantity for every destination. Wiggle room for the slack in future iterations 
                            current_slack=current_slacks[:,c]
                            @constraint(model, slacks[:,c] .>= -current_slack .- delta)
                            @constraint(model, slacks[:,c] .<= current_slack .+ delta)
                    end 
            end 
    
            
    end
    optimize!(model) # resolve one last time with the final slack constraints -> we need to optimize before querying results for the secondary objectives
        current_slacks=abs.(JuMP.value.(slacks))
        @constraint(model,slacks .>= - current_slacks) # fix the slacks for the scheduling phase once the plan has been found
        @constraint(model,slacks .<= current_slacks )
    optimize!(model)
    return model ,params
end 





# Wraps the private helpers _solve_scheduling_model in order to dispatch on the objective keyword argument
function solve_scheduling_model(model::JuMP.Model,
        params::ParameterDict;
        objective::Union{AbstractString,Vector{<:AbstractString}}=_kw_pourfecto_default_.objective,
        kwargs...)

        params[:objective] = objective 
        return _solve_scheduling_model(model,params,objective;kwargs...)
end 




function _solve_scheduling_model(
        model::JuMP.Model,
        params::ParameterDict,
        objective::AbstractString;
        kwargs...)

        objectives[objective](model,params;kwargs...)
        optimize!(model)

        return model, params 

end 
function _solve_scheduling_model(
        model::JuMP.Model,
        params::ParameterDict,
        objective::Vector{<:AbstractString};
        kwargs...)

        for obj in objective 
                objectives[obj](model,params;kwargs...)
                optimize!(model)
        end 

        return model, params 

end 


function check_objective_dict(obj::AbstractString)
        return _objective_MILP_[obj]
end 

function check_objective_dict(obj::Vector{<:AbstractString})
        for o in obj 
                if _objective_MILP_[o]
                        return true 
                end 
        end 
        return false 
end 


function requires_MILP(model::JuMP.Model,params::ParameterDict;kwargs...)
        if :objective in keys(params)
                obj = params[:objective]
                return check_objective_dict(obj)
        elseif :objective in keys(kwargs) 
                obj = kwargs[:objective]
                return check_objective_dict(obj)
        end
        return false 
end 





function planner(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock};kwargs...)
        start_time = Dates.now()
        params = ParameterDict()
        pourfecto_version_metadata!(params)
        model, params  = build_planning_model(sources,targets,params;kwargs...)
        model, params = solve_planning_model(model,sources,targets,params;kwargs...)
        mdl_solution = pourfecto_model_solution(model)
        obj_val = objective_value(model)
        finish_time = Dates.now()
        params[:solver_elapsed]=string(finish_time-start_time)
    return Pourcast(sources,targets,Labware[],Labware[],Configuration[],params,mdl_solution,obj_val)
end


function scheduler(source_labware::Vector{<:CHESSCore.Labware},target_labware::Vector{<:CHESSCore.Labware},configs::Vector{<:Configuration};kwargs...)
        start_time = Dates.now()
        parameters = ParameterDict()
        pourfecto_version_metadata!(parameters)
        if !(all_unique_labware_names(source_labware,target_labware))
                error("all labware must have unique names")
        end 
    mdl, parameters,sources,targets = build_scheduling_model(source_labware,target_labware,configs,parameters;kwargs...) 
    mdl, parameters = solve_planning_model(mdl,sources,targets,parameters; kwargs...)
    mdl,parameters = solve_scheduling_model(mdl,parameters;kwargs...)
    mdl_solution= pourfecto_model_solution(mdl)
    obj_val = objective_value(mdl)
    finish_time = Dates.now()
    parameters[:solver_elapsed] = string(finish_time-start_time)
    return Pourcast(sources,targets,source_labware,target_labware,configs,parameters,mdl_solution,obj_val)

end









"""
        pourfecto(sources::Vector{<:CHESSCore.Stock},
                targets::Vector{<:CHESSCore.Stock};
                kwargs...)

Run the Pourfecto algorithm in **planning** mode using just the source and target stocks
## Arguments 
* `sources`: The CHESSCore.Stock objects that pourfecto can use to create the targets 
* `targets`: The CHESSCore.Stock objects that pourfecto is trying to create using the sources

## Keyword Arguments 
$(_pourfecto_kw_doc_())
"""
function pourfecto(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock};kwargs...)
        return planner(sources,targets;kwargs...)
end 

"""
        pourfecto(source_labware::Vector{<:CHESSCore.Labware},
                target_labware::Vector{<:CHESSCore.Labware};
                kwargs...)

Run the Pourfecto algorithm in **planning** mode using just the source and target labware
## Arguments 
* `source_labware`: The CHESSCore.Labware objects containing source stocks that pourfecto can use to create the targets 
* `target_labware`: The CHESSCore.Labware objects containing target stocks pourfecto is trying to create using the sources

## Keyword Arguments 
$(_pourfecto_kw_doc_())
"""
function pourfecto(source_labware::Vector{<:CHESSCore.Labware},target_labware::Vector{<:CHESSCore.Labware};kwargs...)
        sources = stocks(source_labware)
        targets = stocks(target_labware) 
        return planner(sources,targets;kwargs...)
end 



"""
        pourfecto(source_labware::Vector{<:CHESSCore.Labware},
                target_labware::Vector{<:CHESSCore.Labware},
                configs::Vector{<:Configuration};
                kwargs...)

Run the Pourfecto algorithm in **planning and scheduling** mode 
## Arguments 
* `source_labware`: The CHESSCore.Labware objects containing source stocks that pourfecto can use to create the targets 
* `target_labware`: The CHESSCore.Labware objects containing target stocks pourfecto is trying to create using the sources
* `configs` : The instrument configurations pourfecto can use to schedule the planned liquid transfers. 

## Keyword Arguments 
$(_pourfecto_kw_doc_())
"""
function pourfecto(source_labware::Vector{<:CHESSCore.Labware},target_labware::Vector{<:CHESSCore.Labware},configs::Vector{<:Configuration};kwargs...)
        return scheduler(source_labware,target_labware,configs;kwargs...)
end 


"""
        pourfecto(source_labware::Vector{<:CHESSCore.Labware},
                target_labware::Vector{<:CHESSCore.Labware},
                configs_string::Vector{<:AbstractString};kwargs...)

Run the Pourfecto algorithm in **planning and scheduling** mode.
## Arguments 
* `source_labware`: The CHESSCore.Labware objects containing source stocks that pourfecto can use to create the targets 
* `target_labware`: The CHESSCore.Labware objects containing target stocks pourfecto is trying to create using the sources
* `configs_string` : The String identifiers for instrument configurations pourfecto can use to schedule the planned liquid transfers. 

## Keyword Arguments 
$(_pourfecto_kw_doc_())
"""
function pourfecto(source_labware::Vector{<:CHESSCore.Labware},target_labware::Vector{<:CHESSCore.Labware},configs_string::Vector{<:AbstractString};kwargs...)
        configs = map(x->configurations[x],configs_string)
        return scheduler(source_labware,target_labware,configs;kwargs...)
end 







