"""
    set_component(st::Stock, component::StockComponent, quant)

Return a copy of `st` in which `component` is present at exactly `quant`, leaving every other
component unchanged. A zero `quant` removes the component. `quant` must have the dimension the
component is tracked in: mass for a [`Solid`](@ref), volume for a [`Liquid`](@ref), and
[`Biomass`](@ref) for an [`Organism`](@ref).

See also: [`observe!`](@ref)
"""
function set_component(st::Stock,component::Solid,quant::Unitful.Quantity)
    return Stock(copy(organisms(st)),_set_quantity(solids(st),component,quant,Unitful.Mass),copy(liquids(st)))
end

function set_component(st::Stock,component::Liquid,quant::Unitful.Quantity)
    return Stock(copy(organisms(st)),copy(solids(st)),_set_quantity(liquids(st),component,quant,Unitful.Volume))
end

function set_component(st::Stock,component::Organism,quant::Unitful.Quantity)
    return Stock(_set_quantity(organisms(st),component,quant,Biomass),copy(solids(st)),copy(liquids(st)))
end

function _set_quantity(dict::AbstractDict,component,quant,Q)
    quant isa Q || throw(ArgumentError("$component cannot be given a quantity of $quant"))
    ustrip(quant) >= 0 || throw(DomainError(quant,"$component must have a non-negative quantity"))
    out=copy(dict)
    if ustrip(quant) == 0
        delete!(out,component)
    else
        out[component]=quant
    end
    return out
end


"""
    observe!(well::Well, component::StockComponent, quant; instrument=nothing)
    observe!(loc::Location, attribute::Attribute; instrument=nothing)
    observe!(child::Location, parent::Union{Location,Nothing}; instrument=nothing)
    observe!(loc::Location, facet::Symbol, value; instrument=nothing)

Declare one fact about `loc` as ground truth, whatever history predicted. Unlike the other
operations, an observation makes no claim about how the state came about. It only states what the
state is.

- **Component:** `component` is present in `well` at exactly `quant`, and every other component is
  unchanged. `observe!(well, rgt"glucose", 2u"g")`. A zero `quant` asserts absence. Cost is unchanged.
- **Attribute:** `loc`'s own attribute is `attribute`, as with [`set_attribute!`](@ref). A `missing`
  value means `loc` has no local value and defers to its parent.
- **Parent:** `child` is located in `parent` (or nowhere, for `nothing`). This moves `child` like
  [`move_into!`](@ref) but ignores `child`'s lock. Occupancy rules still apply.
- **Scalar facets:** `facet` is one of `:cost` (a `Well`'s cost), `:locked` or `:active`.

See [`_check_capability`](@ref) for `instrument`.
"""
function observe!(well::Well,component::StockComponent,quant::Unitful.Quantity;instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,observe!)
    new_stock=set_component(stock(well),component,quant)
    check_capacity(new_stock,well)
    well.stock=new_stock
    return nothing
end

function observe!(loc::Location,attribute::Attribute;instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,observe!)
    set_attribute!(attributes(loc),attribute)
    invalidate_environment!(loc)
    return nothing
end

function observe!(child::Location,newparent::Union{Location,Nothing};instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,observe!)
    oldparent=parent(child)
    oldparent === newparent && return nothing
    was_locked=hasproperty(child,:is_locked) && is_locked(child)
    was_locked && unlock!(child)
    try
        add_to!(newparent,child)
    finally
        was_locked && lock!(child)
    end
    isnothing(oldparent) || remove!(oldparent,child)
    return nothing
end

function observe!(loc::Location,facet::Symbol,value;instrument::Union{Location,Nothing}=nothing)
    _check_capability(instrument,observe!)
    if facet === :cost
        loc isa Well || throw(ArgumentError("only a Well has a cost to observe"))
        loc.cost=value
    elseif facet === :locked
        loc.is_locked=value
    elseif facet === :active
        loc.is_active=value
    else
        throw(ArgumentError("unknown observable facet :$facet; expected :cost, :locked or :active"))
    end
    return nothing
end
