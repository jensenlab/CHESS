using JuMP , Gurobi



function bound_plates(wells::BitMatrix,experiments::Vararg{Experiment})
    N=sum(wells)
    n_plates=0
    for expt in experiments
        max_runs_per_plate=N-expt.positive_controls-expt.negative_controls
        if max_runs_per_plate<=0 && expt.runs>0
            throw(ArgumentError("experiment's controls (positive_controls + negative_controls = $(expt.positive_controls+expt.negative_controls)) leave no room for runs on a plate with $N active wells"))
        end
        runs_fit=0
        while runs_fit < expt.runs
            runs_fit+=min(max_runs_per_plate,expt.runs)
            n_plates+=1
        end 
    end 

    return n_plates
end 







function assign_plates(wells::BitMatrix,experiments::Vararg{Experiment};bound_plates=bound_plates,plate_timelimit=100,quiet=true,kwargs...)
    ## Place experiments on plates by sequential minimization of the following criteria 
    # 1. minimize the number of plates used 
    # 2. minimize the number of splits between experiments on plates 
    # 3. minimize the total number of runs (minimize the number of controls needed because of splitting) 
    W=sum(wells)
    N=length(experiments) # number of experiments 

    P=bound_plates(wells,experiments...) # bound on number of plates

    model=Model(Gurobi.Optimizer)
    set_attribute(model,"TimeLimit",plate_timelimit)
    if quiet 
        set_silent(model)
    end 

    @variable(model, r[1:N,1:P] >= 0, Int ) # number of runs from experiment n on plate p
    @variable(model, c[1:N,1:P], Bin) # indicator for controls for experiment n on plate p 
    @variable(model, Ip[1:P],Bin) # indicator for if plate p is needed
    controls=map(x->x.positive_controls+x.negative_controls,experiments)
    runs=map(x->x.runs,experiments)

    for p in 1:P
        @constraint(model, sum(r[:,p]+controls.*c[:,p]) <= W * Ip[p]) # number of runs per plate in use must be less than or equal to the plate size across all experiments
        for n in 1:N
         @constraint(model, !c[n,p] => {r[n,p] == 0})  # having runs from experiment i on plate j requires the controls from experiment i on plate j 
        end 
    end 

    for n in 1:N 
        @constraint(model ,sum(r[n,:])== runs[n]) # each run from experiment i must be placed on a plate 
    end 

    @objective(model, Min, sum(Ip)) # first objective, minimize plates
    optimize!(model)
    active_plates=JuMP.value.(Ip)
    min_p=sum(active_plates) # constrain the number of plates to meet this minimum
    @constraint(model, sum(Ip)==min_p)

    @objective(model, Min, sum(c)) # second objective, minimize splits (the control indicator maps whether runs exist on a plate)
    optimize!(model)
    active_splits=JuMP.value.(c)
    min_splits=sum(active_splits)
    @constraint(model, sum(c)==min_splits) 

    @objective(model, Min,sum([controls[n]*c[n,p] for n in 1:N for p in 1:P]))

    optimize!(model)

    r_out=Int.(round.(JuMP.value.(r)))
    c_out=Bool.(round.(JuMP.value.(c)))
    Ip_out=Bool.(round.(JuMP.value.(Ip)))
    k=[controls[n]*c_out[n,p] for n in 1:N, p in 1:P]

    out=r_out .+ k 
    return out[:,Ip_out]

end 





#= testing 

runs=[400,250,87]
controls=[82,150,20]

platesize=384

s,c,I=PlateMILP(runs,controls,platesize)

=#

