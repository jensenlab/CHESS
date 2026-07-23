
"""
    mutable struct Well <: Location

Wells are special [`Location`](@ref) subtypes that contain a single [`Stock`](@ref) object.

A well's [`LocationKind`](@ref) (`kind`) determines its volume capacity in `kind.capacity`. `kind` is
a required, explicit constructor argument (not derived from the parent), so a well's capacity is
known immediately at construction, whether or not it has a parent yet.

Wells are only allowed to be located in [`Labware`](@ref) objects and cannot be moved from the
labware — they are physically fused to it.
"""
mutable struct Well <: Location
    const location_id::Union{Integer,Nothing}
    const name::String
    const kind::LocationKind
    parent::Union{Labware,Nothing}
    stock::Stock
    attributes::AttributeDict
    reads::Vector{Read}
    cost::Real
    is_active::Bool
    function Well(location_id::Union{Integer,Nothing},name::String,kind::LocationKind;
            parent::Union{Labware,Nothing}=nothing,stock::Stock=Empty(),
            attributes::AttributeDict=AttributeDict(),reads::Vector{Read}=Read[],cost::Real=0,is_active::Bool=true)
        cap=wellcapacity(kind)
        if !isnothing(cap)
            (CHESSCore.volume_estimate(stock) <= cap) || throw(WellCapacityError(CHESSCore.volume_estimate(stock),cap))
        end
        new(location_id,name,kind,parent,stock,attributes,reads,cost,is_active)
    end
end


AbstractTrees.ParentLinks(::Type{<:Well})=StoredParents()
# No parent_cost/child_cost overrides here -- Well uses the generic, kind-data-driven definitions
# (Occupancy.jl) like any other Location. The two real structural rules ("a Well never accepts
# children" and "a Well can't be independently relocated") are enforced directly, not by hijacking
# the occupancy-cost fallback: see add_to!(parent::Well,...) (movement.jl) for the former and
# can_move_into(::Location,child::Well) (movement.jl) for the latter.


"""
    wellcapacity(k::LocationKind)

Return the capacity of a well [`LocationKind`](@ref) as a `Unitful.Volume` quantity, or `nothing` if
`k` is not a well-shaped kind.
"""
function wellcapacity(k::LocationKind)
    return k.capacity
end

"""
    wellcapacity(w::Well)

Return the capacity of a well as a Unitful.Volume quantity

"""
function wellcapacity(w::Well)
    return wellcapacity(kind(w))
end


AbstractTrees.children(::Well) = ()



"""
    stock(::Well)

Access the [`Stock`](@ref) property of a well
"""
stock(x::Well)=x.stock

# all wells are always locked
is_locked(::Well)=true


"""
    cost(::Well)

Access the cost property of a well

"""
cost(x::Well) = x.cost


occupancy(::Well) = 1//1


function check_capacity(s::Stock,w::Well)
    a=volume_estimate(s)
    b=wellcapacity(w)
    if !isnothing(b)
        a <= b || throw(WellCapacityError(a,b))
    end
    nothing
end

function Base.show(io::IO,w::Well)
    print(io,name(w))
end

function lock!(::Well;instrument::Union{Location,Nothing}=nothing)
end

function unlock!(::Well;instrument::Union{Location,Nothing}=nothing)
end

function toggle_lock!(::Well;instrument::Union{Location,Nothing}=nothing)
end




"""
    empty!(x::Well)

Remove the stock contained in a well by setting it to `Empty()`

See also: [`Empty`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function empty!(x::Well)
    s=Empty()
    check_capacity(s,x)
    x.stock=s
    nothing
end

"""
    sterilize!(x::Well)

Remove any organisms from the [`Stock`](@ref) object contained in well `x`. To preview this without
mutating `x`, see [`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function sterilize!(x::Well)
    st=stock(x);
    st_new=Stock(Set{Organism}(),solids(st),liquids(st));
    check_capacity(st_new,x)
    x.stock=st_new;
    nothing
end

"""
    drain!(x::Well)

Remove all [`Chemical`](@ref) components from the [`Stock`](@ref) object contained in the well.

* `drain!` leaves behind any [`Organism`](@ref)s *

See also: [`sterilize!`](@ref),[`empty!`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function drain!(x::Well)
    st=stock(x);
    st_new=Stock(organisms(st),SolidDict(),LiquidDict())
    check_capacity(st_new,x)
    x.stock=st_new;
    nothing
end



function withdraw!(donor::Well,quant::Union{Unitful.Volume,Unitful.Mass})
    st=stock(donor)
    q_tot=quantity(st)
    Unitful.dimension(q_tot) == Unitful.dimension(quant) || error("the withdrawl quantity dimension must be the same as the well's stock dimension")
    factor=Unitful.uconvert(NoUnits,quant/q_tot)
    st_out= factor*st
    donor.stock=st-st_out
    transfer_cost=factor*cost(donor)
    donor.cost -= transfer_cost
    return st_out, transfer_cost
end

"""
    deposit!(recipient::Well, stock::Stock, cost::Real=0)

Add `stock` into `recipient`'s current [`Stock`](@ref), guarded by [`wellcapacity`](@ref) (throws
[`WellCapacityError`](@ref) if the combined stock would exceed it). `cost` is a plain tracked number
(e.g. a reagent cost) added to the well's running cost, apportioned proportionally whenever
[`withdraw!`](@ref) pulls material back out. Defaults to `0` for deposits that don't track a cost.

See also: [`withdraw!`](@ref), [`transfer!`](@ref).
"""
function deposit!(recipient::Well,stock::Stock,cost::Real=0)
    st=CHESSCore.stock(recipient)
    new_stock=st+stock
    check_capacity(new_stock,recipient)
    recipient.stock=new_stock
    recipient.cost += cost
    nothing
end
