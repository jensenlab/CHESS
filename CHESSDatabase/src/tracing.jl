# Tracing: which lots the material in a well came from, found by replaying the ledger. A trace is
# computed on demand and never stored. It follows the same transfers and component observations as
# `reconstruct_contents`, and carries alongside each well's stock the quantity of each component that
# came from each lot.

# Replay state of one well: its stock, and the quantity of each component traced to a lot. Material in
# the stock that no share accounts for is untraced.
mutable struct _TracedWell
    stock::Stock
    shares::Dict{Tuple{StockComponent,Lot},Unitful.Quantity}
end
_TracedWell() = _TracedWell(Empty(),Dict{Tuple{StockComponent,Lot},Unitful.Quantity}())

function _component_quantity(st::Stock,component::StockComponent)
    dict = component isa Solid ? solids(st) : component isa Liquid ? liquids(st) : organisms(st)
    return get(dict,component,nothing)
end

# move the fraction `factor` of a well's stock and traced shares out, returning what left
function _withdraw_traced!(w::_TracedWell,quant)
    factor = Unitful.uconvert(Unitful.NoUnits,quant/CHESSCore.quantity(w.stock))
    out_stock = factor*w.stock
    out_shares = Dict(k=>factor*q for (k,q) in w.shares)
    w.stock = w.stock - out_stock
    for (k,q) in out_shares
        w.shares[k] -= q
    end
    return out_stock,out_shares
end

function _deposit_traced!(w::_TracedWell,stock::Stock,shares)
    w.stock = w.stock + stock
    mergewith!(+,w.shares,shares)
    return nothing
end

# State that `component` is present in the well at exactly `quant`. Material already there keeps its
# proportions among lots and untraced material. A component appearing in an empty well is traced to the
# lot of the well's labware, when it has one.
function _observe_traced!(w::_TracedWell,component::StockComponent,quant,bottle_lot::Union{Lot,Nothing})
    old = _component_quantity(w.stock,component)
    w.stock = set_component(w.stock,component,quant)
    if isnothing(old) || iszero(old)
        for k in filter(k->k[1]==component,collect(keys(w.shares)))
            delete!(w.shares,k)
        end
        isnothing(bottle_lot) || iszero(quant) || (w.shares[(component,bottle_lot)] = quant)
    else
        factor = Unitful.uconvert(Unitful.NoUnits,quant/old)
        for k in keys(w.shares)
            k[1]==component && (w.shares[k] *= factor)
        end
    end
    return nothing
end

"""
    trace_contents(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

Trace what a well holds back to the lots it came from, as of `sequence_id` and `time`. The result has one
row for each component and lot, with columns `Component`, `Lot`, and `Quantity`. Material that cannot be
tied to a lot, such as water drawn from a tap, appears as a row with a `missing` `Lot`.

The trace follows the transfers into the well and the observations of its ancestors, with each transfer
taking the same fraction of every lot's share of a component as of the component itself. A component
observed in a well that held none of it comes from the [`Lot`](@ref) of the well's labware as of
`sequence_id`, which is how a bottle's contents are attributed to the bottle's lot. A component observed
in a well that already held some keeps its proportions among lots.

The trace is computed from the ledger each time and is not stored. See also [`trace_cost`](@ref).
"""
function trace_contents(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    name,build = get_location_info(location_id)
    build(location_id,name) isa CHESSCore.Well || error("only a well holds contents to trace, and location $location_id is not one")
    transfers = get_transfer_ancestors([location_id],0,sequence_id,time)
    core = Set{Int}([location_id])
    for row in eachrow(transfers)
        row.Core == 1 && union!(core,(row.Source,row.Destination))
    end
    observations = get_content_observations(collect(core),0,sequence_id,time)
    filter!(row->!ismissing(row.ComponentID),observations)

    wells = Dict{Int,_TracedWell}()
    well(id) = get!(()->_TracedWell(),wells,id)
    lots = Dict{Int,Union{Lot,Nothing}}()
    function bottle_lot(well_id)
        get!(lots,well_id) do
            parent = CHESSCore.parent(reconstruct_parent(well_id,sequence_id,time))
            isnothing(parent) ? nothing : reconstruct_lot(CHESSCore.location_id(parent),sequence_id,time)
        end
    end
    components = Dict{Int,StockComponent}()
    component(id) = get!(()->get_component(id),components,id)

    events = vcat([(row.SequenceID,:transfer,row) for row in eachrow(transfers)],
                  [(row.SequenceID,:observation,row) for row in eachrow(observations)])
    sort!(events;by=first)
    for (_,kind,row) in events
        quant = row.Quantity*_parse_unit(row.Unit)
        if kind === :observation
            _observe_traced!(well(row.LocationID),component(row.ComponentID),quant,bottle_lot(row.LocationID))
        elseif row.Core == 1
            out_stock,out_shares = _withdraw_traced!(well(row.Source),quant)
            _deposit_traced!(well(row.Destination),out_stock,out_shares)
        else # a core well's outgoing transfer to a well that never feeds back into it
            _withdraw_traced!(well(row.Source),quant)
        end
    end

    result = DataFrame(Component=StockComponent[],Lot=Union{Lot,Missing}[],Quantity=Unitful.Quantity[])
    w = well(location_id)
    for (component,total) in _components(w.stock)
        traced = [(k[2],q) for (k,q) in w.shares if k[1]==component]
        sort!(traced;by=t->(t[1].supplier,t[1].catalog_number,t[1].lot))
        for (lot,q) in traced
            push!(result,(component,lot,q))
        end
        remainder = total - sum(last.(traced);init=zero(total))
        abs(Unitful.ustrip(remainder)) > 1e-9*abs(Unitful.ustrip(total)) && push!(result,(component,missing,remainder))
    end
    return result
end

# What `quantity` of `component` costs, given the lot's price for its whole quantity. `missing` when the
# lot has no cost or quantity or its quantity cannot be expressed in the component's terms.
function _lot_cost(component::StockComponent,lot::Union{Lot,Missing},quantity)
    (ismissing(lot) || ismissing(lot.cost) || ismissing(lot.quantity)) && return missing
    total = try
        _in_quantity_of(component,lot.quantity,quantity)
    catch err
        err isa Union{ArgumentError,Unitful.DimensionError} || rethrow()
        return missing
    end
    return lot.cost*Unitful.uconvert(Unitful.NoUnits,quantity/total)
end

# a lot's purchased quantity in the dimension of `like`, converting through the component's density or
# molar mass when the lot is bought in a different dimension than the component is tracked in
function _in_quantity_of(component::StockComponent,purchased,like)
    Unitful.dimension(purchased) == Unitful.dimension(like) && return purchased
    component isa Reagent || throw(ArgumentError("$(component) cannot be converted between dimensions"))
    mass = Unitful.dimension(purchased) == Unitful.dimension(u"g") ? purchased :
           Unitful.dimension(purchased) == Unitful.dimension(u"mol") ? purchased*molecular_weight(component) :
           purchased*density(component)
    Unitful.dimension(like) == Unitful.dimension(u"g") && return Unitful.uconvert(Unitful.unit(like),mass)
    return Unitful.uconvert(Unitful.unit(like),mass/density(component))
end

"""
    trace_cost(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

The cost of what a well holds, share by share. It is [`trace_contents`](@ref) with a `Cost` column: the
cost of each share is the lot's `cost` times the share's fraction of the lot's `quantity`. The cost is
`missing` for a share with no lot, and for one whose lot has no cost or quantity.

See also: [`reconstruct_cost`](@ref).
"""
function trace_cost(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    traced = trace_contents(location_id,sequence_id,time)
    traced.Cost = Union{Float64,Missing}[_lot_cost(r.Component,r.Lot,r.Quantity) for r in eachrow(traced)]
    return traced
end

"""
    reconstruct_cost(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(); strict=false)

The cost of what a well holds: the sum of [`trace_cost`](@ref) over the shares whose cost is known. Material
with no known cost does not add to the sum, so the result is a lower bound unless every share is costed.
With `strict=true` the result is `missing` unless every share is costed.
"""
function reconstruct_cost(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();strict::Bool=false)
    costs = trace_cost(location_id,sequence_id,time).Cost
    strict && any(ismissing,costs) && return missing
    return sum(skipmissing(costs);init=0.0)
end
