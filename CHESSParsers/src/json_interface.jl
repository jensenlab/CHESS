"""
    labwareread_to_json(lr::LabwareRead) -> String

Serialize `lr` to a JSON string. `metadata["format"]`, if it holds an [`InstrumentFormat`](@ref)
subtype, is lowered to its type name (a `String`) so the result is plain JSON.
"""
function labwareread_to_json(lr::LabwareRead)
    meta = copy(lr.metadata)
    fmt = get(meta, "format", nothing)
    fmt isa DataType && (meta["format"] = string(nameof(fmt)))
    json_dict = Dict("metadata" => meta, "data" => JSONTables.objecttable(lr.data))
    return JSON.json(json_dict)
end

"""
    json_to_labwareread(j::AbstractString) -> LabwareRead

Deserialize a JSON string produced by [`labwareread_to_json`](@ref) back into a [`LabwareRead`](@ref).
"""
function json_to_labwareread(j::AbstractString)
    json_dict = JSON.parse(j)
    data = DataFrame(JSONTables.jsontable(json_dict["data"]))
    return LabwareRead(json_dict["metadata"], data)
end
