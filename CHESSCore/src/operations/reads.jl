
"""
    record_read!(loc::Location, read::Read; instrument=nothing)

Append `read` to `loc`'s `reads` collection. Does *not* call [`invalidate_environment!`](@ref) --
reads never participate in [`environment`](@ref). See [`_check_capability`](@ref) for `instrument`.
"""
function record_read!(loc::Location,read::Read;instrument::Union{Instrument,Nothing}=nothing)
    _check_capability(instrument,record_read!)
    push!(reads(loc),read)
    return nothing
end
