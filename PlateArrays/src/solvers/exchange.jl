

"""
    exchange(wells::BitMatrix,P::Int,N::Int;objective::Function=hybrid,minimize=true,restarts::Int=10,iterations::Int=1000,rng::AbstractRNG=Random.default_rng(),kwargs...)

Exchange solver for control placment

# Arguments
- `plate`: A BitMatrix indicating the shape and active wells, use `trues(n,m)` for a full n x m plate.
- `P`: The integer number of positive controls
- `N`: The integer number of negative controls


# Keyword Arguments
- `objective` : The objective function criteria, choose from `minimax`, `LHS`, and `hybrid`. The hybrid objective is slower than the other objectives because it calculates bounds to balance two objectives.
- `minimize` : flip the objective sign
- `restarts` : Number of solver restarts. The solver returns the best solution among the restarts
- `iterations`: number of exchange iterations per run.
- `rng`: the random number generator used for the initial design and every exchange step. Pass an
  explicit RNG (e.g. `exchange(wells,P,N; rng=Random.Xoshiro(1234))`) for reproducible layouts.

"""
function exchange(wells::BitMatrix,P::Int,N::Int;objective::Function=hybrid,minimize=true,restarts::Int=10,iterations::Int=1000,rng::AbstractRNG=Random.default_rng(),kwargs...)
    global_best=PlateArray[]
    best_objective=Float64[]

    # set bounds for the hybrid objective if needed
    if objective==hybrid
        min_distance_plate=exchange(wells,P,N;objective=minimax,set_bounds=false,minimize=true,restarts=1,iterations=iterations,rng=rng,kwargs...)
        max_distance_plate=exchange(wells,P,N;objective=minimax,set_bounds=false,minimize=false,restarts=1,iterations=iterations,rng=rng,kwargs...)
        min_LHS_plate=exchange(wells,P,N;objective=LHS,set_bounds=false,minimize=true,restarts=1,iterations=iterations,rng=rng,kwargs...)
        max_LHS_plate=exchange(wells,P,N;objective=LHS,set_bounds=false,minimize=false,restarts=1,iterations=iterations,rng=rng,kwargs...)
        a=minimax(min_distance_plate)
        b=minimax(max_distance_plate)
        c=LHS(min_LHS_plate)
        d=LHS(max_LHS_plate)
        lambda=0.5
        if in(:lambda,keys(kwargs))
            lambda=kwargs[:lambda]
        end 
        objective=x-> hybrid(x;lambda=lambda,lb_dist=a,ub_dist=b,lb_LHS=c,ub_LHS=d,kwargs...)
    end 




    
    for i in 1:restarts 

        
        best_design=random_platearray(wells,P,N;rng=rng)
        best_score=objective(best_design)
        for _ in 1:iterations
            pos=rand(rng,Bernoulli(0.5))
            cand_positives=deepcopy(best_design.positives)
            cand_negatives=deepcopy(best_design.negatives)
            if pos
                current_controls= cand_positives .|| cand_negatives
                available= wells .&& .!current_controls
                pos_idxs=findall(x->x==true,cand_positives)
                if length(pos_idxs) ==0
                    continue
                end
                current_idx=rand(rng,pos_idxs)
                new_idx=rand(rng,findall(x->x==true,available))

                cand_positives[current_idx]=false # swap the location of the active bits
                cand_positives[new_idx]=true
            else
                current_controls= cand_positives .|| cand_negatives
                available= wells .&& .!current_controls
                neg_idxs=findall(x->x==true,cand_negatives)
                if length(neg_idxs) ==0
                    continue
                end
                current_idx=rand(rng,neg_idxs)
                new_idx=rand(rng,findall(x->x==true,available))

                cand_negatives[current_idx]=false # swap the location of the active bits 
                cand_negatives[new_idx]=true 
            end 
            design=PlateArray(wells,cand_positives,cand_negatives)
            score=objective(design)

            fun = > 
            if minimize
                fun = < 
            end 

            if fun(score ,best_score)
                best_score=score 
                best_design=deepcopy(design)
            end 
        end 
        push!(global_best,best_design)
        push!(best_objective,best_score)
    end 


    best_idx=findmax(best_objective)[2]
    return global_best[best_idx]
end 
