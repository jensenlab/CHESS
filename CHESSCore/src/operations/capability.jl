
"""
    _check_capability(instrument::Union{Instrument,Nothing}, fun::Function)

Shared gate for the four operations whose CHESS Database tables carry an `InstrumentID`
(`move_into!`/`transfer!`/`set_attribute!`/`record_read!`): if `instrument` is given, it must have
`fun` in its [`performable_operations`](@ref), or this throws `ArgumentError`. A no-op if `instrument`
is `nothing` (the default everywhere it's used) -- this never mutates `instrument` and never changes
the mutation logic of the operation itself, it only validates.

Checks only the coarse "can this instrument perform this operation at all" axis --
`actuatable_attributes`/`readable_types` (the finer, per-argument axes) are deliberately not consulted
here; they remain descriptive `LocationKind` data for a possible future planning/scheduling feature.
"""
function _check_capability(instrument::Union{Instrument,Nothing},fun::Function)
    isnothing(instrument) && return nothing
    fun in performable_operations(instrument) || throw(ArgumentError("$(instrument) cannot perform $(fun)"))
    return nothing
end
