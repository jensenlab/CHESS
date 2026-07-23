
"""
    transfer!(donor::Well,recipient::Well,quantity::Union{Unitful.Volume,Unitful.Mass};instrument=nothing)

Remove `quantity` from `donor` and move it to `recipient`

`transfer!` mutates the donor and recipient in place. To preview this without mutating either well,
see [`reconstruct_location`](@ref)/[`build_location`](@ref). See [`_check_capability`](@ref) for
`instrument`.
"""
function transfer!(donor::Well,recipient::Well,quantity::Union{Unitful.Volume,Unitful.Mass},configuration::String="";instrument::Union{Instrument,Nothing}=nothing)
    _check_capability(instrument,transfer!)
    trf_stock,trf_cost=withdraw!(donor,quantity)
    deposit!(recipient,trf_stock,trf_cost)
    nothing
end
