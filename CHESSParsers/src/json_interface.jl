# Shared by every result type's JSON interface (LabwareRead, EnvironmentLog): lowers metadata to
# plain JSON-safe values (an InstrumentFormat subtype -> its type name; any DataFrame-valued entry,
# e.g. EnvironmentLog's "plates" table, -> a JSONTables object-table, remembering which keys need
# restoring on the way back) and serializes/deserializes the {metadata, data} shape all result types
# share.

function _metadata_to_json(metadata::Dict{String,Any})
    meta = copy(metadata)
    fmt = get(meta, "format", nothing)
    fmt isa DataType && (meta["format"] = string(nameof(fmt)))
    dataframe_keys = String[]
    for (k, v) in meta
        if v isa DataFrame
            meta[k] = JSONTables.objecttable(v)
            push!(dataframe_keys, k)
        end
    end
    isempty(dataframe_keys) || (meta["__dataframe_keys__"] = dataframe_keys)
    return meta
end

function _metadata_from_json(meta::AbstractDict)
    meta = copy(meta)
    for k in get(meta, "__dataframe_keys__", String[])
        meta[k] = DataFrame(JSONTables.jsontable(meta[k]))
    end
    delete!(meta, "__dataframe_keys__")
    return meta
end

_to_json(metadata::Dict{String,Any}, data::DataFrame) =
    JSON.json(Dict("metadata" => _metadata_to_json(metadata), "data" => JSONTables.objecttable(data)))

function _from_json(::Type{T}, j::AbstractString) where {T}
    json_dict = JSON.parse(j)
    data = DataFrame(JSONTables.jsontable(json_dict["data"]))
    return T(_metadata_from_json(json_dict["metadata"]), data)
end

"""
    labwareread_to_json(lr::LabwareRead) -> String

Serialize `lr` to a JSON string. `metadata["format"]`, if it holds an [`InstrumentFormat`](@ref)
subtype, is lowered to its type name (a `String`) so the result is plain JSON.
"""
labwareread_to_json(lr::LabwareRead) = _to_json(lr.metadata, lr.data)

"""
    json_to_labwareread(j::AbstractString) -> LabwareRead

Deserialize a JSON string produced by [`labwareread_to_json`](@ref) back into a [`LabwareRead`](@ref).
"""
json_to_labwareread(j::AbstractString) = _from_json(LabwareRead, j)

"""
    environmentlog_to_json(el::EnvironmentLog) -> String

Serialize `el` to a JSON string, the [`EnvironmentLog`](@ref) counterpart of
[`labwareread_to_json`](@ref) (including its `metadata["plates"]` table).
"""
environmentlog_to_json(el::EnvironmentLog) = _to_json(el.metadata, el.data)

"""
    json_to_environmentlog(j::AbstractString) -> EnvironmentLog

Deserialize a JSON string produced by [`environmentlog_to_json`](@ref) back into an
[`EnvironmentLog`](@ref).
"""
json_to_environmentlog(j::AbstractString) = _from_json(EnvironmentLog, j)
