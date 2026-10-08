
"""
    transfer!(donor::Well,recipient::Well,quantity::Union{Unitful.Volume,Unitful.Mass},configuration::String="";instrument=nothing)

Remove `quantity` from `donor` and move it to `recipient`

`transfer!` mutates the donor and recipient in place. To preview this without mutating either well,
see [`build_location`](@ref) (or CHESSDatabase's `reconstruct_location`). See [`_check_capability`](@ref) for
`instrument`.
"""
function transfer!(donor::Well,recipient::Well,quantity::Union{Unitful.Volume,Unitful.Mass},configuration::String="";instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,transfer!)
    trf_stock,trf_cost=withdraw!(donor,quantity)
    deposit!(recipient,trf_stock,trf_cost)
    nothing
end
