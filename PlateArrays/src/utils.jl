


function random_platearray(wells::BitMatrix,P::Int,N::Int)
    availables=findall(x->x==true,wells)
    R,C=size(wells)
    pos=falses(R,C)
    neg=falses(R,C)
    pos_idx=sample(availables,P;replace=false)
    pos[pos_idx] .=true 
    neg_available=findall(x->x==true, wells .&& .!pos)
    neg_idx=sample(neg_available,N;replace=false)
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

