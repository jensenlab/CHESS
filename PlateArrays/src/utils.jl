


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
    assign_run_index(p::PlateArray; run_order::String="ordered", rng::AbstractRNG=Random.default_rng(),
                      indices::Union{Nothing,AbstractVector{<:Integer}}=nothing)

Return a new `PlateArray` with `run_index` populated over `p`'s run wells. Always recomputed from
scratch, so this can also be used to re-shuffle (or re-assign) an already-indexed `PlateArray`.

# Keyword Arguments
- `indices`: if given, assign these exact values (in order) to the run wells (column-major order) instead
  of computing `run_order`/`rng` -- must have exactly one value per run well. This is the primitive for
  assigning an arbitrary slice of a larger sequence (e.g. one plate's share of a multi-plate experiment's
  `1:total_runs`, as `arrayer` does) rather than a fresh, plate-local `1:N`.
- `run_order`: ignored when `indices` is given. `"ordered"` (default) assigns `1:N` in column-major well
  order (the same order `wellnames`/the DataFrame interface use); `"random"` assigns a uniformly random
  permutation of `1:N` using `rng`.
- `rng`: the random number generator used when `run_order="random"`. Pass an explicit RNG (e.g.
  `Random.Xoshiro(1234)`) for a reproducible ordering.
"""
function assign_run_index(p::PlateArray; run_order::String="ordered", rng::AbstractRNG=Random.default_rng(),
        indices::Union{Nothing,AbstractVector{<:Integer}}=nothing)
    idxs = findall(runs(p))
    if indices !== nothing
        length(indices) == length(idxs) || throw(ArgumentError(
            "indices must have one value per run well ($(length(idxs)) run wells, got $(length(indices)))"))
        order = collect(indices)
    else
        run_order in ("ordered","random") || throw(ArgumentError("run_order must be \"ordered\" or \"random\""))
        order = run_order == "random" ? shuffle(rng,1:length(idxs)) : collect(1:length(idxs))
    end
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

