function JSON.lower(map::RunMap)
    return Dict(
        "runs" => collect(map.runs),
        "edges" => [
            Dict("run" => x.run, "linked_run" => x.linked_run, "relation_type" => String(x.relation_type), "metadata" => x.metadata)
            for x in edges(map)
        ],
    )
end

"""
    RunMap(d::AbstractDict) -> RunMap

Reconstruct a `RunMap` from a dict of the shape produced by
`JSON.lower(::RunMap)`/[`json_to_runmap`](@ref): a top-level `"runs"` node
list (so orphan nodes round-trip) plus an `"edges"` list of
`{"run","linked_run","relation_type","metadata"}` objects.

Since JSON has no native type system beyond string/number/bool/array/object,
a node that was e.g. a `Symbol` or `UUID` before serialization comes back as
a `String` -- `N` is inferred from the parsed values' actual types, same as
the `DataFrame` reverse constructor.
"""
function RunMap(d::AbstractDict)
    map = RunMap()
    for r in d["runs"]
        add_run!(map, r)
    end
    for e in d["edges"]
        raw_meta = get(e, "metadata", Dict())
        md = isempty(raw_meta) ? nothing : Dict(Symbol(k) => v for (k, v) in raw_meta)
        link!(map, e["run"], e["linked_run"], e["relation_type"]; metadata=md)
    end
    return map
end

"""
    runmap_to_json(map::RunMap) -> String

Serialize a `RunMap` to a JSON string.

See also: [`json_to_runmap`](@ref).
"""
runmap_to_json(map::RunMap) = JSON.json(map)

"""
    json_to_runmap(s::AbstractString) -> RunMap

Parse a JSON string (produced by [`runmap_to_json`](@ref)) back into a
`RunMap`.
"""
json_to_runmap(s::AbstractString) = RunMap(JSON.parse(s))

"""
    write_json(path::AbstractString, map::RunMap)

Write `map` to `path` as JSON.

See also: [`read_runmap_json`](@ref).
"""
write_json(path::AbstractString, map::RunMap) = write(path, runmap_to_json(map))

"""
    read_runmap_json(path::AbstractString) -> RunMap

Read a `RunMap` previously written with [`write_json`](@ref).
"""
read_runmap_json(path::AbstractString) = json_to_runmap(read(path, String))
