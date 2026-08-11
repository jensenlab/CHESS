function distance_to_edge(R,C)
    distance=zeros(Int64,R,C)
    for r in 1:R
        for c in 1:C
            distance[r,c]=min(abs(1-r),abs(R-r),abs(1-c),abs(C-c))
        end
    end 

    return vec(reshape(distance,R*C,1))
end 


"""
    function partition(wells::BitMatrix,expts::Vararg{Int})

Partition experiments onto a plate of active wells. Use center wells before using edge wells, and place the experiments into contiguous blocks.

# Arguments 
- `wells` a BitMatrix where each active well has a value of 'true'
- `expts` a Vararg Int indicating how many runs are present in each experiment

"""
function partition(wells::BitMatrix,expts::Vararg{Int})
    # place the experiments on the plate such that any empty wells are on the edge and that each experiment is contiguous
    nexpts=sum(expts)
    if nexpts>sum(wells)
        throw(ArgumentError("total number of experiments exceeds the number of active wells on the plate"))
    end
    R,C=size(wells)
    order=sortperm(distance_to_edge(R,C),rev=true)
    wellvec=vec(reshape(wells,R*C,1))
    idx=filter(x->wellvec[x]==true,order)

    idx=sort(idx[1:nexpts])

    # split wells to form contiguous blocks for each experiment
    cutoffs=vcat(0,cumsum(collect(expts)))
    plates=[falses(R,C) for _ in eachindex(expts)]
    for i in eachindex(expts)
        plates[i][idx[cutoffs[i]+1:cutoffs[i+1]]].=true
    end 


    return plates
end


