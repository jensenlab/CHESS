function JSON.lower(map::ControlMap)
    return Dict(
        "runs" => collect(map.runs),
        "controls" => collect(map.controls),
        "edges" => [
            Dict("run" => x.run, "control" => x.control, "control_type" => String(x.control_type), "metadata" => x.metadata)
            for x in edges(map)
        ],
    )
end

"""
    ControlMap(d::AbstractDict) -> ControlMap

Reconstruct a `ControlMap` from a dict of the shape produced by
`JSON.lower(::ControlMap)`/[`json_to_controlmap`](@ref): top-level `"runs"`
and `"controls"` node lists (so orphan nodes round-trip) plus an `"edges"`
list of `{"run","control","control_type","metadata"}` objects.

Since JSON has no native type system beyond string/number/bool/array/object,
a node that was e.g. a `Symbol` or `UUID` before serialization comes back as
a `String` -- `R`/`C` are inferred from the parsed values' actual types, same
as the `DataFrame` reverse constructor.
"""
function ControlMap(d::AbstractDict)
    map = ControlMap()
    for r in d["runs"]
        add_run!(map, r)
    end
    for c in d["controls"]
        add_control!(map, c)
    end
    for e in d["edges"]
        raw_meta = get(e, "metadata", Dict())
        md = isempty(raw_meta) ? nothing : Dict(Symbol(k) => v for (k, v) in raw_meta)
        link!(map, e["run"], e["control"], e["control_type"]; metadata=md)
    end
    return map
end

"""
    controlmap_to_json(map::ControlMap) -> String

Serialize a `ControlMap` to a JSON string.

See also: [`json_to_controlmap`](@ref).
"""
controlmap_to_json(map::ControlMap) = JSON.json(map)

"""
    json_to_controlmap(s::AbstractString) -> ControlMap

Parse a JSON string (produced by [`controlmap_to_json`](@ref)) back into a
`ControlMap`.
"""
json_to_controlmap(s::AbstractString) = ControlMap(JSON.parse(s))

"""
    write_json(path::AbstractString, map::ControlMap)

Write `map` to `path` as JSON.

See also: [`read_controlmap_json`](@ref).
"""
write_json(path::AbstractString, map::ControlMap) = write(path, controlmap_to_json(map))

"""
    read_controlmap_json(path::AbstractString) -> ControlMap

Read a `ControlMap` previously written with [`write_json`](@ref).
"""
read_controlmap_json(path::AbstractString) = json_to_controlmap(read(path, String))
