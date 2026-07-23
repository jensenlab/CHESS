
"""
    mutable struct Instrument <: Location

The concrete [`Location`](@ref) subtype for a device that can perform operations on *other* locations
(`move_into!`/`transfer!`/`set_attribute!`/`record_read!`, gated by [`performable_operations`](@ref) --
see [`_check_capability`](@ref)) and/or produce [`Read`](@ref)s -- as opposed to a plain
[`GenericLocation`](@ref), whose state only ever changes via direct calls, never its own action.

There is a single concrete `Instrument` type for every instrument model — capability (which
operations it can perform via [`performable_operations`](@ref), which attribute kinds it's associated
with via [`actuatable_attributes`](@ref), which [`ReadKind`](@ref)s it's associated with via
[`readable_types`](@ref) -- these last two are descriptive data only, not enforced by any runtime
check, reserved for a possible future planning/scheduling feature) is carried as data on its
[`LocationKind`](@ref), not as a distinct type per model or category, mirroring how
[`LocationKind`](@ref) itself avoids a Julia type per kind.
"""
mutable struct Instrument <: Location
    const location_id::Union{Integer,Nothing}
    const name::String
    const kind::LocationKind
    parent::Union{Location,Nothing}
    children::Vector{Location}
    attributes::AttributeDict
    reads::Vector{Read}
    is_locked::Bool
    is_active::Bool
end

function Instrument(location_id::Union{Integer,Nothing},name::String,kind::LocationKind;
        parent::Union{Location,Nothing}=nothing,children::Vector{<:Location}=Location[],
        attributes::AttributeDict=AttributeDict(),reads::Vector{Read}=Read[],is_locked::Bool=false,is_active::Bool=true)
    return Instrument(location_id,name,kind,parent,Location[children...],attributes,reads,is_locked,is_active)
end

"""
    actuatable_attributes(x::Instrument)

Return the `Set{Symbol}` of [`AttributeKind`](@ref) names `x` is associated with — descriptive data
carried on `x`'s [`LocationKind`](@ref), not enforced anywhere (reserved for a possible future
planning/scheduling feature).
"""
actuatable_attributes(x::Instrument) = kind(x).actuatable_attributes

"""
    performable_operations(x::Instrument)

Return the `Set{Function}` of operation functions (e.g. `move_into!`, `transfer!`, `set_attribute!`)
that `x` can perform on *other* locations — data carried on `x`'s [`LocationKind`](@ref).
"""
performable_operations(x::Instrument) = kind(x).performable_operations

"""
    readable_types(x::Instrument)

Return the `Set{Symbol}` of [`ReadKind`](@ref) names that `x` can produce — data carried on `x`'s
[`LocationKind`](@ref).
"""
readable_types(x::Instrument) = kind(x).readable_types
