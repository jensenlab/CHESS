const TYPEKEY = "__type__"

function lower_bitmatrix(M::BitMatrix)
    return Dict(TYPEKEY => "BitMatrix", "size" => [size(M,1), size(M,2)], "data" => vec(Bool.(M)))
end

function raise_bitmatrix(d::JSON.Object{String,Any})
    d[TYPEKEY] == "BitMatrix" || error("Not a BitMatrix dict")
    m, n = d["size"]
    return BitMatrix(reshape(Bool.(d["data"]), m, n))
end

function JSON.lower(p::PlateArray)
    return Dict(TYPEKEY => "PlateArray",
                "wells" => lower_bitmatrix(p.wells),
                "positives" => lower_bitmatrix(p.positives),
                "negatives" => lower_bitmatrix(p.negatives))
end

function raise_platearray(d::JSON.Object{String,Any})
    d[TYPEKEY] == "PlateArray" || error("Not a PlateArray dict")
    return PlateArray(raise_bitmatrix(d["wells"]), raise_bitmatrix(d["positives"]), raise_bitmatrix(d["negatives"]))
end

"""
    platearray_to_json(p::PlateArray) -> String

Serialize a `PlateArray` to a JSON string.

See also: [`json_to_platearray`](@ref)
"""
platearray_to_json(p::PlateArray) = JSON.json(p)

"""
    json_to_platearray(s::AbstractString) -> PlateArray

Parse a JSON string (produced by [`platearray_to_json`](@ref)) back into a `PlateArray`.
"""
json_to_platearray(s::AbstractString) = raise_platearray(JSON.parse(s))
