
function all_unique_labware_names(sources::Vector{<:Labware},targets::Vector{<:Labware})
    all_labware_names = vcat(CHESSCore.name.(sources),CHESSCore.name.(targets))
    return allunique(all_labware_names)
end

"""
    planning_concentration(stock::CHESSCore.Stock, ingredient::CHESSCore.Solid)
    planning_concentration(stock::CHESSCore.Stock, ingredient::CHESSCore.Liquid)

Concentration of `ingredient` in `stock`, in the fixed convention the pourfecto planning
algorithm (`normalize_inputs`) needs: always `g/µL` for solids, always a dimensionless `percent` for
liquids -- regardless of the stock's own total quantity dimension. This is a different (and
narrower) contract than `CHESSCore.concentration`, which is dimension-aware (returns `percent`
whenever the ingredient's dimension matches the stock total's, a mass/volume-style ratio
otherwise) for the dataframe "vc" format. `normalize_inputs` needs a single fixed unit per
ingredient kind so `S[:,c]./normfactor` is always convertible to `µL^-1`; using
`CHESSCore.concentration` directly here breaks that for stocks whose total shares a solid
ingredient's dimension (e.g. a `Mixture`), where it returns `percent` instead of `g/µL`.
"""
function planning_concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    ingredient in stock || return 0*u"g/µL"
    quant = solids(stock)[ingredient]/CHESSCore.quantity(stock)
    if !isa(quant,Unitful.Density)
        return convert(u"g/µL",quant,ingredient) # molar concentration issue
    else
        return uconvert(u"g/µL",quant)
    end
end

function planning_concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    ingredient in stock || return 0*u"percent"
    return uconvert(u"percent",liquids(stock)[ingredient]/CHESSCore.quantity(stock))
end

function normalize_inputs(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock})

    chems = union(all_reagents(sources),all_reagents(targets))
    ns = length(sources)
    nt=length(targets)
    nc = length(chems)
    S = [planning_concentration(s,c) for s in sources, c in chems]
    T = [quantity(t,c) for t in targets, c in chems]
    Sout = zeros(ns,nc)
    Tout = zeros(nt,nc)
    for c in 1:nc
        normfactor = maximum(T[:,c])
        if ustrip(normfactor) == 0 # if all targets are zero (the gram unit is irrellevant)
            normfactor = maximum(quantity.(sources,(chems[c],))) # the normalization factor should be based on the maximum quantity in the sources 
        end
        Sout[:,c] .= ustrip.(uconvert.((u"µL^-1",),S[:,c]./normfactor))
        Tout[:,c] .= T[:,c] ./normfactor

    end 
    return Sout,Tout
end 






function total_quantity(stocks::Vector{<:CHESSCore.Stock},chem::CHESSCore.Reagent)

    return sum(map(x->quantity(x,chem),stocks))
end 


function input_balance(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock})

    chems= union(all_reagents(sources),all_reagents(targets))
    balances= Dict{CHESSCore.Reagent,Unitful.Quantity}()
    for chem in chems 

        balances[chem] = total_quantity(sources,chem) - total_quantity(targets,chem) 
     end 
    return balances 
end 


function check_inputs(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock})

    balances = input_balance(sources,targets)
    shortages = filter(x-> ustrip(balances[x]) < 0,collect(keys(balances)))
    if length(shortages) > 0 
        bals = map(x-> balances[x],shortages)
        throw(ChemicalShortageError("there is a shortage of the following chemicals:",Dict(shortages .=> bals)))
    end 

    return nothing 
end

    
function update_priority(sources::Vector{<:CHESSCore.Stock},targets::Vector{<:CHESSCore.Stock},priority::PriorityDict)
    new_priority=PriorityDict()
    src_chems= all_reagents(sources)
    tgt_chems = all_reagents(targets) 
        # Update priorities: priority increases with decreasing level

    # Level 0: All level 0 ingredeients are blocked from the design. They may not appear in the stock. 
    # Level 1+: All other ingredients are scheduled sequentially by priority. we allow slack for all nonzero priorities, where we try to minimize the slack for each ingredient and then constrain the slack for future priority levels. 
    # Level 2^(64)-1: Maximum allowable priority level, typically a solvent like water that we would use to back fill will be assigned maximum priority level. 
    for chem in keys(priority) 
        new_priority[chem] = priority[chem]
    end 


    for chem in reagent_to_string.(tgt_chems)
        if !in(chem,keys(new_priority))
            new_priority[chem]=UInt64(1)
        end 
    end 
    for chem in reagent_to_string.(src_chems)
        if !in(chem,keys(new_priority)) # if the user hasn't specified a source ingredient priority or included it in the targets (see above), assume it is priority 0. (These ingredients will be blocked, regardless of a discrete or continuous robot)
            new_priority[chem]=UInt64(0) 
        end 
    end 
    return new_priority 
end





function compute_flow_nodes(nodetype::Type{<:FlowNode},configs::Vector{<:Configuration},labware::Vector{<:Labware})
    combinations = vec(collect(Iterators.product(configs,labware)))
    node_info = map(x-> (Mask(head(x[1]),x[2]),x[1]),combinations)
    nodes = nodetype[]
    position_dict = Dict(
        AspNode => asp_positions,
        DispNode => disp_positions
    )

    for info in node_info
        mask = info[1]
        config = info[2]
        n_pistons = length(pistons(head(mask)))
        n_positions = prod(position_dict[nodetype](mask))
        for piston in 1:n_pistons 
            for position in 1:n_positions 
                node = nodetype(mask,config, piston,position)
                push!(nodes,node)
            end
        end
    end
    return nodes 
end 



function well_connections(node::FlowNode) 
    mask = node.mask 
    piston = node.piston 
    position = node.position 
    lw = labware(mask) 
    wellnames = vec(CHESSCore.name.(children(lw)))
    n_wells = length(wellnames)
    connections = Tuple{<:String,<:Integer}[]
    piston_channel_mask = node isa DispNode ? dispense_mask(head(mask)) : aspirate_mask(head(mask)) # aspirate/dispense may have different piston-channel connectivity (e.g. Tempest)
    channels_to_test = findall(x->x==true,piston_channel_mask[piston,:]) # which channels connect to the selected piston
    mask_type = asp
    if node isa DispNode
        mask_type = disp
    end
    for w in 1:n_wells 
        connecting_channels = map(x-> mask_type(mask)(w, position,x),channels_to_test)

        for c in eachindex(connecting_channels)
            if connecting_channels[c] # channels_to_test[c] connects to well w 
                push!(connections,(wellnames[w],channels_to_test[c]))
            end
        end 
    end 
    return map(x->(CHESSCore.name(lw),x...),connections) # a triple of the labware name, well name, and the channel index 
end 

function well_names(l::Labware)

    return map(x-> (CHESSCore.name(l),CHESSCore.name(x)),vec(CHESSCore.children(l)))
end 

function compute_flow_connections(src_wells::Vector{Tuple{String,String}},tgt_wells::Vector{Tuple{String,String}},asp_nodes::Vector{AspNode},disp_nodes::Vector{DispNode})

    asp_connections = well_connections.(asp_nodes)

    asp_well_labware = map(y -> map(x-> x[[1,2]],y),asp_connections)
    disp_connections = well_connections.(disp_nodes) 
    disp_well_labware = map(y -> map(x-> x[[1,2]],y),disp_connections)

    src_well_connections = map(w-> findall(x-> in(w,x),asp_well_labware),src_wells)
    tgt_well_connections = map(w-> findall(x-> in(w,x),disp_well_labware),tgt_wells)

    S = length(src_well_connections)
    T = length(tgt_well_connections)

    flow_connections =[CartesianIndex{2}[] for s in 1:S , t in 1:T]

    for s in 1:S
        for t in 1:T
            for na in src_well_connections[s]
                for nd in tgt_well_connections[t]
                    asp_nodes[na].configuration === disp_nodes[nd].configuration || continue # routing is only meaningful within the same physical instrument -- a config mismatch is invalid regardless (see is_valid_flow) and their channel index spaces aren't comparable anyway

                    sw = asp_connections[na][findall(x-> x == src_wells[s],asp_well_labware[na])] # grab only connections that interact with our well of interest
                    s_chs = map(x->x[3],sw) # find the aspirate channel indices that facilitate that connection

                    tw = disp_connections[nd][findall(x-> x == tgt_wells[t],disp_well_labware[nd])]
                    t_chs = map(x->x[3],tw) # find the dispense channel indices that facilitate that connection

                    routing = channel_routing(head(asp_nodes[na].mask)) # channel_routing[i,j]: does aspirate channel i physically reach dispense channel j (identity for most instruments; a real fan-out for e.g. Tempest)
                    if any(routing[ac,dc] for ac in s_chs, dc in t_chs) # the channels must be physically connected for the wells to truly connect
                        push!(flow_connections[s,t],CartesianIndex(na,nd))

                    end
                end
            end
        end
    end

     return flow_connections

end



function can_slot_labware_pair(a::Labware,b::Labware,config::Configuration) 

    open_slots = Set{Tuple{DeckPosition,Int}}()

    for position in deck(config) 
        n_slots = prod(slots(position))
        for i in 1:min(n_slots,2) 
            push!(open_slots,(position,i))
        end 
    end 
    placed_a = false 
    placed_b = false 

    for s in open_slots
        if can_place(a,s[1],config)
            placed_a=true
            delete!(open_slots,s)
            break
        end

    end

    for s in open_slots
        if can_place(b,s[1],config)
            placed_b=true
            delete!(open_slots,s)
            break
        end
    end

    return placed_a && placed_b

end 




function is_valid_flow(a::AspNode, d::DispNode) 

   if  a.configuration != d.configuration # flows must use the same configuration 
        return false 
   end 
   con = a.configuration # we know at this point the configs are the same 

   if !can_slot_labware_pair(labware(a.mask),labware(d.mask),con) # we must be able to slot the labware simultaneously 
        return false 
   end 

   if a.piston != d.piston # the flow must use the same piston 
        return false 
   end 
   return true 

end  


function minimum_shot(a::AspNode) 
    piston_idx = a.piston 
    h = head(a.mask)
    p = pistons(h)[piston_idx] 

    asp_limits = p.asp 

    min_asp = asp_limits[1]

    return ustrip(uconvert(u"µl",min_asp))
end 
function maximum_shot(a::AspNode) 
    piston_idx = a.piston 
    h = head(a.mask)
    p = pistons(h)[piston_idx] 

    asp_limits = p.asp 

    max_asp = asp_limits[2]

    return ustrip(uconvert(u"µl",max_asp))
end 


function minimum_shot(a::DispNode) 
    piston_idx = a.piston 
    h = head(a.mask)
    p = pistons(h)[piston_idx] 

    disp_limits = p.disp

    min_disp= disp_limits[1]

    return ustrip(uconvert(u"µl",min_disp))
end 

function maximum_shot(a::DispNode) 
    piston_idx = a.piston 
    h = head(a.mask)
    p = pistons(h)[piston_idx] 

    disp_limits = p.disp

    max_disp = disp_limits[2]

    return ustrip(uconvert(u"µl",max_disp))
end 



function padding_factor(a::AspNode,d::DispNode)
    if is_valid_flow(a,d)
        piston_idx = a.piston 
        h= head(a.mask)
        p = pistons(h)[piston_idx]

        return p.deadPad 
    else
        return 0 
    end 
end 

function node_costs(asp_nodes::Vector{AspNode},disp_nodes::Vector{DispNode},c::Vector{<:Configuration},config_costs::Vector{<:Real})

    

    costs = [ config_costs[findfirst(x->x == a.configuration,c)] for a in asp_nodes , d in disp_nodes]

    return costs 
end 


function stock_quantity(s::CHESSCore.Stock;unit = u"µL")
        sq = CHESSCore.quantity(s)
        stock_quantity = 0
        if !ismissing(sq)
                stock_quantity= ustrip(uconvert(unit,sq))
        end 
        return stock_quantity
end 


function pourfecto_model_solution(m::JuMP.Model) 
  mdl_objs = JuMP.object_dictionary(m)
  mdl_solution = Dict{Symbol,Any}()
  for obj_key in keys(mdl_objs)
    obj = JuMP.value.(m[obj_key])
    mdl_solution[obj_key] = obj
  end 
  return mdl_solution 
end 


function pourfecto_version_metadata!(params::ParameterDict)
    params[:pourfecto_vesion]= pkgversion(Pourfecto)
    params[:gurobi_version] = Gurobi._GUROBI_VERSION
    params[:solve_time] = string(Dates.now())
    return params 
end 


function solution_quality(p::Pourcast)
    s = slacks(p) 
    tol = params(p)[:solution_tolerance]
    quality_flag = abs.(s) .> tol 
    return quality_flag
end


function solution_quality_report(p::Pourcast) 

    sources = source_stocks(p)
    targets = target_stocks(p) 

    chems= union(all_reagents(sources),all_reagents(targets))
    s = slacks(p)

    quality_flag = solution_quality(p)
    stocks = Integer[]
    chem_idx = Integer[]
    chem_name = String[]
    slack_values = Real[]
    tolerances = Real[]
    for idx in findall(x->x==true,quality_flag) 
      i,j = Tuple(idx) 
      push!(stocks,i)
      push!(chem_idx,j)
      push!(chem_name,CHESSCore.name(chems[j]))
      push!(slack_values,s[i,j])
      push!(tolerances,params(p)[:solution_tolerance])
    end 

    return DataFrame(stock = stocks, chemical_index = chem_idx, chemical = chem_name, slack_value = slack_values , tolerance = tolerances )
  end 