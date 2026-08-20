const TYPEKEY = "__type__"

"""
    NODE_TYPE_REGISTRY

Maps a serialized type-tag string to the concrete Julia type it should reconstruct as when parsing a
`PlateMap`'s JSON `occupant` field back in -- JSON has no native way to represent arbitrary Julia types
(a `Symbol`-typed occupant, for instance, would otherwise silently come back as a `String`). Mirrors
`Pourfecto`'s `INSTRUMENT_TYPES` tag-to-type registry pattern for the same "which concrete type do I
rebuild" problem. Extend it (`NODE_TYPE_REGISTRY["MyType"] = MyType`) for custom node-identity types.
"""
const NODE_TYPE_REGISTRY = Dict{String,Type}(
    "String" => String,
    "Symbol" => Symbol,
    "Int64" => Int64,
    "Int32" => Int32,
)

function lower_bitmatrix(M::BitMatrix)
    return Dict(TYPEKEY => "BitMatrix", "size" => [size(M,1), size(M,2)], "data" => vec(Bool.(M)))
end

function raise_bitmatrix(d::JSON.Object{String,Any})
    d[TYPEKEY] == "BitMatrix" || error("Not a BitMatrix dict")
    m, n = d["size"]
    return BitMatrix(reshape(Bool.(d["data"]), m, n))
end

_json_scalar(v::Symbol) = String(v)
_json_scalar(v) = v

_from_json(::Type{Symbol},v) = Symbol(v)
_from_json(::Type{T},v) where T = convert(T,v)

function lower_occupant(M::Matrix{Union{Missing,T}}) where T
    return Dict(TYPEKEY => "Occupant", "size" => [size(M,1),size(M,2)], "node_type" => string(T),
                "data" => [ismissing(v) ? nothing : _json_scalar(v) for v in vec(M)])
end

function raise_occupant(d::JSON.Object{String,Any})
    d[TYPEKEY] == "Occupant" || error("Not an Occupant dict")
    m, n = d["size"]
    tname = d["node_type"]
    T = get(NODE_TYPE_REGISTRY,tname,nothing)
    T === nothing && error("Unknown node_type \"$tname\" -- register it in NODE_TYPE_REGISTRY to deserialize")
    data = Union{Missing,T}[v === nothing ? missing : _from_json(T,v) for v in d["data"]]
    return reshape(data,m,n)
end

function JSON.lower(pm::PlateMap)
    return Dict(TYPEKEY => "PlateMap", "wells" => lower_bitmatrix(pm.wells), "occupant" => lower_occupant(pm.occupant))
end

function raise_platemap(d::JSON.Object{String,Any})
    d[TYPEKEY] == "PlateMap" || error("Not a PlateMap dict")
    wells = raise_bitmatrix(d["wells"])
    occupant = raise_occupant(d["occupant"])
    return PlateMap(wells,occupant)
end

"""
    platemap_to_json(pm::PlateMap) -> String

Serialize a `PlateMap` to a JSON string.

See also: [`json_to_platemap`](@ref)
"""
platemap_to_json(pm::PlateMap) = JSON.json(pm)

"""
    json_to_platemap(s::AbstractString) -> PlateMap

Parse a JSON string (produced by [`platemap_to_json`](@ref)) back into a `PlateMap`. The node-identity
type is reconstructed via [`NODE_TYPE_REGISTRY`](@ref).
"""
json_to_platemap(s::AbstractString) = raise_platemap(JSON.parse(s))

function raise_platemaps(d::JSON.Object{String,Any})
    d[TYPEKEY] == "PlateMapBatch" || error("Not a PlateMapBatch dict")
    return PlateMap[raise_platemap(p) for p in d["plates"]]
end

"""
    platemaps_to_json(pms::Vector{PlateMap}) -> String

Serialize a multi-plate schedule to a single JSON string: a `__type__`-tagged `"PlateMapBatch"` wrapper
around each plate's own `JSON.lower` form, matching the tagged-`Dict` convention every other JSON
shape in this package uses. Deliberately not a `JSON.lower(::Vector{PlateMap})` method, so an unrelated
`Vector{PlateMap}` nested inside some other JSON structure isn't silently reshaped by it.

See also: [`json_to_platemaps`](@ref)
"""
platemaps_to_json(pms::Vector{PlateMap}) = JSON.json(Dict(TYPEKEY=>"PlateMapBatch","plates"=>[JSON.lower(pm) for pm in pms]))

"""
    json_to_platemaps(s::AbstractString) -> Vector{PlateMap}

Parse a JSON string (produced by [`platemaps_to_json`](@ref)) back into a `Vector{PlateMap}`.
"""
json_to_platemaps(s::AbstractString) = raise_platemaps(JSON.parse(s))
