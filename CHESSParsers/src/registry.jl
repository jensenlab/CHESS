"""
    format_registry

Global registry of known [`InstrumentFormat`](@ref) subtypes, keyed by name. Use
[`register_format!`](@ref) to add to it and `keys(format_registry)` to see what's available.
"""
const format_registry = Dict{String,DataType}()

"""
    register_format!(T::Type{<:InstrumentFormat}; name::AbstractString, override::Bool=false)

Register `T` in the global [`format_registry`](@ref) under `name`, making it discoverable via
`format_registry["name"]` and usable by name in [`parse_instrument_file`](@ref).

Errors if `name` is already registered unless `override=true` (in which case the previous entry is
replaced and a warning is emitted) -- this guards against two independently-authored instrument
packages accidentally colliding on the same name.

Third-party instrument packages should call this once per [`InstrumentFormat`](@ref) they define,
typically at module top-level, right after `using CHESSParsers`.

# Examples
```jldoctest
julia> struct ExFormat <: InstrumentFormat end

julia> CHESSParsers.detect(::Type{ExFormat}, path) = endswith(path, ".ex");

julia> register_format!(ExFormat; name="ex_format");

julia> haskey(format_registry, "ex_format")
true
```
"""
function register_format!(T::Type{<:InstrumentFormat}; name::AbstractString, override::Bool=false)
    if haskey(format_registry, name)
        if !override
            error("an instrument format named \"$name\" is already registered; pass override=true to replace it")
        end
        @warn "overwriting existing instrument format \"$name\""
    end
    format_registry[name] = T
    return T
end

"""
    detect_format(path::AbstractString) -> Union{DataType,Nothing}

Try every registered [`InstrumentFormat`](@ref) subtype's [`detect`](@ref) method against `path`,
returning the first match, or `nothing` if none match.
"""
function detect_format(path::AbstractString)
    for T in values(format_registry)
        detect(T, path) && return T
    end
    return nothing
end

"""
    parse_instrument_file(path::AbstractString; format=nothing, kwargs...) -> Vector{LabwareRead}

Parse the instrument export file at `path` into one [`LabwareRead`](@ref) per (plate, channel) found
in it.

`format` selects which [`InstrumentFormat`](@ref) to use:
- `nothing` (default): auto-detect via [`detect_format`](@ref), erroring if no registered format
  matches.
- a `String`: looked up by name in [`format_registry`](@ref).
- an `InstrumentFormat` subtype: used directly, skipping detection.

Any `kwargs` are forwarded to the concrete format's [`parse_raw`](@ref) method.
"""
function parse_instrument_file(path::AbstractString; format::Union{DataType,AbstractString,Nothing}=nothing, kwargs...)
    T = if format isa AbstractString
        haskey(format_registry, format) || error("no instrument format named \"$format\" is registered; known formats: $(collect(keys(format_registry)))")
        format_registry[format]
    elseif format isa DataType
        format
    else
        detected = detect_format(path)
        isnothing(detected) && error("could not auto-detect an instrument format for \"$path\"; pass `format=` explicitly")
        detected
    end
    return parse_raw(T, path; kwargs...)
end
