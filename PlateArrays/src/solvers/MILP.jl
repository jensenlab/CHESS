



"""
    function MILP(P::Int,N::Int,wells::BitMatrix;objective::Function=hybrid,minimize=true,timelimit=100)

MILP solver for control placment. Requires Gurobi licence.

# Arguments 
- `wells`: A BitMatrix indicating the shape and active wells, use `trues(n,m)` for a full n x m plate.
- `P`: The integer number of positive controls
- `N`: The integer number of negative controls 

# Keyword Arguments 
- `objective`: the objective type for the MILP solver. Must be either 'minimax' or 'hybrid'.
- `timelimit`: time limit in seconds for the solver to return a suboptimal solution if it hasn't found an optimal one
- `minimize`: if true, the solver minimizes the distance from experiment wells to control wells. if false, it will maximize (this is not useful for practical purposes but is helpful for assessing performance) 

"""
function MILP(wells::BitMatrix,P::Int,N::Int;objective::Function=hybrid,minimize=true,timelimit=100)

    in(objective,[hybrid,minimax]) ? nothing : throw(ArgumentError("the objective for the MILP Solver must either be 'minimax' or 'hybrid'"))
    R,C=size(wells)
    model=Model(Gurobi.Optimizer)
    set_attribute(model,"TimeLimit",timelimit)
    @variable(model, x[1:R,1:C],Bin);
    @variable(model,y[1:R,1:C],Bin);
    @variable(model,dwx[1:R,1:C]>=0);
    @variable(model,dwy[1:R,1:C]>=0);




    @constraint(model, sum(x)==P);
    @constraint(model, sum(y)==N);
    for row in 1:R
        for col in 1:C
            @constraint(model,x[row,col]+y[row,col]<=1)
            @constraint(model, x[row,col] <= wells[row,col])
            @constraint(model,y[row,col] <= wells[row,col])

        end
    end
    M=max(R,C)

    if objective==hybrid
        epr,epc,enr,enc=expected_LHS(random_platearray(wells,P,N)) # given the plate shape, find the expected number of controls per row and column in a uniformly distributed array of controls. 

        #constrain the number of controls to be as close as possible to the expected LHS 
        for row in 1:R
            @constraint(model, sum(x[row,:])<= Int(ceil(epr[row]))) 
            @constraint(model,sum(x[row,:]) >= Int(floor(epr[row])))
            @constraint(model, sum(y[row,:])<= Int(ceil(enr[row])))
            @constraint(model,sum(y[row,:])>= Int(floor(enr[row])))
        end 

        for col in 1:C
            @constraint(model,sum(x[:,col])<= Int(ceil(epc[col])))
            @constraint(model,sum(x[:,col])>= Int(floor(epc[col])))
            @constraint(model,sum(y[:,col])<= Int(ceil(enc[col])))
            @constraint(model,sum(y[:,col])>= Int(floor(enc[col])))
        end
    end 



    if minimize
        for row in 1:R
            for col in 1:C
                for ring in 0:M
                    w=neighboring_ring(row,col,ring,R,C)
                    r=map(y->y[1],w)
                    c=map(y->y[2],w)
                    @constraint(model,dwx[row,col]>=ring+1-(ring+1)*sum([x[r[i],c[i]] for i =1:length(w)]));
                    @constraint(model,dwy[row,col]>=ring+1-(ring+1)*sum([y[r[i],c[i]] for i =1:length(w)]))
                end
            end
        end
        @objective(model,Min,sum(wells .* (dwx+dwy)));
    else 
        @variable(model, Idwx[1:R,1:C,1:M+1],Bin)
        @variable(model,Idwy[1:R,1:C,1:M+1],Bin)

        for row in 1:R
            for col in 1:C
                for ring in 0:M
                    w=neighboring_ring(row,col,ring,R,C)
                    r=map(y->y[1],w)
                    c=map(y->y[2],w)
                    @constraint(model ,Idwx[row,col,ring+1] => {sum([x[r[i],c[i]] for i =1:length(w)]) ==0})
                    @constraint(model ,Idwy[row,col,ring+1] => {sum([y[r[i],c[i]] for i =1:length(w)]) ==0})
                    
                    @constraint(model,dwx[row,col]<= ring +M*Idwx[row,col,ring+1])
                    @constraint(model,dwy[row,col]<= ring +M*Idwy[row,col,ring+1])
                    
                    
 

                end
            end
        end
        @objective(model,Min,-1*sum(wells.*(dwx+dwy)));
    end
    optimize!(model)
    return PlateArray(wells,BitMatrix(JuMP.value.(x)),BitMatrix(JuMP.value.(y)))
end

#= test 

R=16
C=24

N_pos=12

N_neg=12

wells=13:81
x,y,dwx,dwy,model=ControlDistanceMILP(N_pos,N_neg,R,C,wells,minimize=false)
=#