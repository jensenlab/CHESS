


"""
    random_platearray(wells::BitMatrix,P::Int,N::Int;rng::AbstractRNG=Random.default_rng())

Generate a `PlateArray` with `P` positive and `N` negative controls placed at uniformly random
active wells.

# Keyword Arguments
- `rng`: the random number generator used to draw well positions. Pass an explicit RNG (e.g.
  `Random.Xoshiro(1234)`) for reproducible output.

"""
function random_platearray(wells::BitMatrix,P::Int,N::Int;rng::AbstractRNG=Random.default_rng())
    availables=findall(x->x==true,wells)
    R,C=size(wells)
    pos=falses(R,C)
    neg=falses(R,C)
    pos_idx=sample(rng,availables,P;replace=false)
    pos[pos_idx] .=true
    neg_available=findall(x->x==true, wells .&& .!pos)
    neg_idx=sample(rng,neg_available,N;replace=false)
    neg[neg_idx].=true
    return PlateArray(wells,pos,neg)
end





"""
    runs(platearray::PlateArray)

Compute the non-control active wells of a PlateArray.

"""
function runs(platearray::PlateArray)
    return platearray.wells .&& .!platearray.positives .&& .!platearray.negatives
end


"""
    assign_run_index(p::PlateArray; run_order::String="ordered", rng::AbstractRNG=Random.default_rng())

Return a new `PlateArray` with `run_index` populated over `p`'s run wells (`1:N`, `N` = number of runs).
Always recomputed from scratch, so this can also be used to re-shuffle an already-indexed `PlateArray`.

# Keyword Arguments
- `run_order`: `"ordered"` (default) assigns `1:N` in column-major well order (the same order
  `wellnames`/the DataFrame interface use); `"random"` assigns a uniformly random permutation of `1:N`
  using `rng`.
- `rng`: the random number generator used when `run_order="random"`. Pass an explicit RNG (e.g.
  `Random.Xoshiro(1234)`) for a reproducible ordering.
"""
function assign_run_index(p::PlateArray; run_order::String="ordered", rng::AbstractRNG=Random.default_rng())
    run_order in ("ordered","random") || throw(ArgumentError("run_order must be \"ordered\" or \"random\""))
    idxs = findall(runs(p))
    order = run_order == "random" ? shuffle(rng,1:length(idxs)) : collect(1:length(idxs))
    run_index = Matrix{Union{Missing,Int}}(missing,size(p.wells))
    run_index[idxs] .= order
    return PlateArray(p.wells,p.positives,p.negatives,run_index)
end


"""
    active_indices(plate::BitMatrix)

Compute the integer indices of active wells. 
"""
function active_indices(plate::BitMatrix)
    r,c=size(plate)
    x=vec(reshape(plate,r*c,1))
    return findall(y->y==true,x)
end 


function letter_code(n::Integer) 
    
    alphabet=collect('A':'Z')
    k=length(alphabet)
    return repeat(alphabet[mod(n-1,k)+1],cld(n,k))
end 


function wellnames(platearray::PlateArray) 
    R,C = size(platearray.wells)
    return ["$(letter_code(i))$j" for i in 1:R, j in 1:C]
end 

