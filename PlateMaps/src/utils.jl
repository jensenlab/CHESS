function letter_code(n::Integer)
    alphabet = collect('A':'Z')
    k = length(alphabet)
    return repeat(alphabet[mod(n-1,k)+1],cld(n,k))
end

function wellnames(wells::AbstractMatrix)
    R,C = size(wells)
    return ["$(letter_code(i))$j" for i in 1:R, j in 1:C]
end
