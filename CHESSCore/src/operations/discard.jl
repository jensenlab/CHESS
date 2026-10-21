"""
    discard!(donor::Well, quantity::Union{Unitful.Volume,Unitful.Mass}; instrument=nothing)

Remove `quantity` from `donor` and let it leave the system: it is used up, poured to waste, or thrown
away, and goes into no other well.

`discard!` takes a proportional slice of the well's contents, as [`withdraw!`](@ref) does, so
discarding a quarter of the total takes a quarter of every reagent and organism. It throws if the well
holds less than `quantity`. Where [`transfer!`](@ref) moves material from one well to another,
`discard!` ends it, and a database records it as a withdrawal rather than as a lower observed amount.
See [`_check_capability`](@ref) for `instrument`.
"""
function discard!(donor::Well,quantity::Union{Unitful.Volume,Unitful.Mass};instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,discard!)
    withdraw!(donor,quantity)
    nothing
end
