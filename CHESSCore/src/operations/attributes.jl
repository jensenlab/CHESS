
"""
    set_attribute!(x::Location,attribute::Attribute; instrument=nothing)

Set the value for a location's environmental attributes to `attribute`.

We use this method to ensure a proper pairing between the attribute type and the attribute in the dict.
To preview this without mutating `x`, see [`build_location`](@ref) (or CHESSDatabase's `reconstruct_location`).
See [`_check_capability`](@ref) for `instrument`.
"""
function set_attribute!(loc::Location,attribute::Attribute;instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,set_attribute!)
    set_attribute!(attributes(loc),attribute)
    invalidate_environment!(loc)
    nothing
end
