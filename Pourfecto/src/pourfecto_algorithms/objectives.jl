



function min_cost_flow!(model::JuMP.Model,params::ParameterDict;config_costs::Vector{<:Real} = ones(params[:n_configs]),kwargs...)
        params[:config_costs]= config_costs 
        Q = model[:Q]
        
        asp_configs = Int.(round.(JuMP.value.(model[:asp_config])))
        disp_configs = Int.(round.(JuMP.value(model[:disp_config])))

        costs = [sqrt(config_costs[a]*config_costs[d]) for a in asp_configs , d in disp_configs]

        set_objective_sense(model, MOI.FEASIBILITY_SENSE)
        @objective(model, Min,sum(costs .* Q)) # minimize total masked operations 
        optimize!(model)
        Qval= JuMP.value.(Q) 
        @constraint(model,sum(costs .* Q) <= sum( costs .* Qval))
        return model,params
end 

function regularize_flows!(model::JuMP.Model,params::ParameterDict;kwargs...)
        Q = model[:Q]
        


        set_objective_sense(model, MOI.FEASIBILITY_SENSE)
        @objective(model, Min,sum(Q.^2)) # minimize with l2 norm to regularize flows
        optimize!(model)
        Qval= JuMP.value.(Q) 
        @constraint(model,sum(Q.^2) <= sum(Qval.^2))
        return model,params
end 




function min_active_flow!(model::JuMP.Model,params::ParameterDict;kwargs...) 
    Q = model[:Q] 
    A,D =size(Q)
    if !params[:enforce_minimum_shot] # enforce minimum shot already creates an indicator 
        @variable(model, QI[1:A,1:D],Bin)
        for a in 1:A 
                for d in 1:D 
                        @constraint(model, !QI[a,d] --> {Q[a,d] <= params[:grb_feasibility_tol]})
                end 
        end 
        set_objective_sense(model, MOI.FEASIBILITY_SENSE)
        @objective(model, Min, sum(QI))
        optimize!(model)
        QIval = round(sum(JuMP.value.(QI)))
        @constraint(model,sum(QI) <= QIval)
    else 
        QI = model[:QI]
        set_objective_sense(model, MOI.FEASIBILITY_SENSE)
        @objective(model, Min, sum(QI))
        optimize!(model)
        QIval = round(sum(JuMP.value.(QI)))
        @constraint(model,sum(QI) <= QIval)
    end 

    return model , params 
end 



function min_sources!(model::JuMP.Model,params::ParameterDict;kwargs...)
    V=model[:V]
    S,T = size(V)
    @variable(model,sourceI[1:S],Bin)
    for s in 1:S 
            @constraint(model, !sourceI[s] --> {sum(V[s,:]) <= params[:grb_feasibility_tol]})
    end 
    set_objective_sense(model, MOI.FEASIBILITY_SENSE)
    @objective(model, Min, sum(sourceI))
    optimize!(model)
    sourceIval= round(sum(JuMP.value.(sourceI)))
    @constraint(model,sum(sourceI) <= sourceIval)
    return model ,params 
end 


function min_labware!(model::JuMP.Model,params::ParameterDict;kwargs...)
    Q=model[:Q]

    asp_labware = Int.(round.(JuMP.value.(model[:asp_labware])))
    disp_labware = Int.(round.(JuMP.value(model[:disp_labware])))

    n_source_labware = params[:n_source_labware]
    n_target_labware = params[:n_target_labware]

    @variable(model,lwI[1:n_source_labware,1:n_target_labware],Bin)

    for slw in 1:n_source_labware
        for tlw in 1:n_target_labware
            src_nodes = findall(x->x==slw,asp_labware)
            tgt_nodes = findall(x->x==tlw,disp_labware)
            coords = vec(collect(Iterators.product(src_nodes,tgt_nodes)))
            idxs = map(x-> CartesianIndex(x),coords)
            @constraint(model, !lwI[slw,tlw] --> {sum(Q[idxs]) <= params[:grb_feasibility_tol]})
        end 
    end 
    set_objective_sense(model, MOI.FEASIBILITY_SENSE)
    @objective(model,Min,sum(lwI))
    optimize!(model)
    lwIval = round(sum(JuMP.value.(lwI)))
    @constraint(model,sum(lwI) <= lwIval)
    return model, params 
end 


function min_config!(model::JuMP.Model, params::ParameterDict;kwargs...) 
    Q=model[:Q]

    asp_config = Int.(round.(JuMP.value.(model[:asp_config])))
    n_configs= params[:n_configs]

    @variable(model,configI[1:n_configs],Bin)

    for slw in 1:n_configs
            config_nodes = findall(x->x==slw,asp_config)

            @constraint(model, !configI[slw] --> {sum(Q[config_nodes,:]) <= params[:grb_feasibility_tol]})
    end 
    set_objective_sense(model, MOI.FEASIBILITY_SENSE)
    @objective(model,Min,sum(configI))
    optimize!(model)
    configIval = round(sum(JuMP.value.(configI)))
    @constraint(model,sum(configI) <= configIval)
    return model, params 
end 


function min_aspirations!(model::JuMP.Model,params::ParameterDict;kwargs...)
    Q=model[:Q] 

    multi_repeater = Bool.(Int.(round.(JuMP.value.(model[:multi_repeater_piston]))))

    A,D =size(Q)
    if !params[:enforce_minimum_shot] # enforce minimum shot already creates an indicator 
        @variable(model, QI[1:A,1:D],Bin)
        for a in 1:A 
                for d in 1:D 
                        @constraint(model, !QI[a,d] --> {Q[a,d] <= params[:grb_feasibility_tol]})
                end 
        end 
    else 
        QI = model[:QI]
    end 

    
    @variable(model, aspsI[1:A],Int)

    for a in 1:A 
        if multi_repeater[a]
            @constraint(model,aspsI[a] >= sum(QI[a,:])/D) # we only care if at least one of them is on. Multi repeaters only "pay" for a single aspiration
        else
            @constraint(model,aspsI[a] >= sum(QI[a,:])) # Every dispense counts with a single repeater 
        end 
    end 
    set_objective_sense(model, MOI.FEASIBILITY_SENSE)
    @objective(model,Min,sum(aspsI))
    optimize!(model)
    aspsIval = sum(JuMP.value.(aspsI))
    @constraint(model,sum(aspsI) <= aspsIval)
    
    return model, params 
end 


"""
    objectives 

Pourfecto provides an assortment of pre-defined objectives. Use `keys(objectives)` to see available options

Note that many non-defualt options turn the problem into an MILP in the scheudling phase, which can lead to long and unpredictable run times. 

"""
const objectives = Dict{String,Function}(
    "min_cost_flow" => min_cost_flow!,
    "min_active_flow" => min_active_flow!,
    "min_sources" => min_sources!,
    "min_labware" => min_labware!,
    "min_config" => min_config!,
    "min_aspirations" => min_aspirations!,
    "regularize_flows" => regularize_flows!
)


# Internal constant for the planning solver to check what type of problem (LP/MILP) will come up later in scheduling. If true, we need to add a dummy binary variable before optimizing. Gurobi errors out if you add integer or binary variables after solving with only continuous variables
const _objective_MILP_ = Dict{String,Bool}(
    "min_cost_flow" => false,
    "min_active_flow" => true,
    "min_sources" => true,
    "min_labware" => true,
    "min_config" => true,
    "min_aspirations" => true,
    "regularize_flows"=> false
)