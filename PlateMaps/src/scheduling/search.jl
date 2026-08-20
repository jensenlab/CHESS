function _random_node_placement(nodes::Vector,free_wells::Vector{CartesianIndex{2}},rng::AbstractRNG)
    chosen = free_wells[shuffle(rng,1:length(free_wells))[1:length(nodes)]]
    return Dict{Any,CartesianIndex{2}}(n => w for (n,w) in zip(nodes,chosen))
end

"""
    _local_search(wells, nodes, free_wells, fixed_pos, score, minimize, restarts, iterations, rng)
        -> (Dict{Any,CartesianIndex{2}}, Real)

Generic restart/local-move search: place `nodes` onto `free_wells`, minimizing (or maximizing) `score`
(called on `merge(fixed_pos, candidate)`). Each restart starts from a random placement and repeatedly
either relocates one node into a currently-empty free well or swaps two nodes' positions, keeping a move
only if it improves the score. Used both for control placement (relative to already-fixed runs) and for
run placement itself (relative to nothing, i.e. `fixed_pos=Dict()`, minimizing [`run_compactness`](@ref)).
"""
function _local_search(wells::BitMatrix,nodes::Vector,free_wells::Vector{CartesianIndex{2}},
        fixed_pos::AbstractDict,score::Function,minimize::Bool,restarts::Int,iterations::Int,rng::AbstractRNG)
    if isempty(nodes)
        return Dict{Any,CartesianIndex{2}}(),score(fixed_pos)
    end
    better = minimize ? (<) : (>)
    empties_exist = length(nodes) < length(free_wells)
    best_pos_overall,best_score_overall = nothing,nothing
    for _ in 1:restarts
        cpos = _random_node_placement(nodes,free_wells,rng)
        s = score(merge(fixed_pos,cpos))
        for _ in 1:iterations
            cand = copy(cpos)
            if empties_exist && rand(rng,Bool)
                # relocate one node into a currently-empty free well
                n = nodes[rand(rng,1:length(nodes))]
                empty_wells = setdiff(free_wells,values(cand))
                isempty(empty_wells) && continue
                cand[n] = empty_wells[rand(rng,1:length(empty_wells))]
            else
                # swap two nodes' positions -- always valid, even with zero slack
                length(nodes) < 2 && continue
                a,b = nodes[rand(rng,1:length(nodes))],nodes[rand(rng,1:length(nodes))]
                a == b && continue
                cand[a],cand[b] = cand[b],cand[a]
            end
            cs = score(merge(fixed_pos,cand))
            if better(cs,s)
                cpos,s = cand,cs
            end
        end
        if best_score_overall === nothing || better(s,best_score_overall)
            best_pos_overall,best_score_overall = cpos,s
        end
    end
    return best_pos_overall,best_score_overall
end
