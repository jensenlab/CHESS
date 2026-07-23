
# internal constants and methods 
const roundtolerance=4
prefquantunits(::Solid)=u"g"
prefquantunits(::Liquid)=u"mL"

SolidDict=Dict{Solid,Unitful.Mass}
LiquidDict=Dict{Liquid,Unitful.Volume}


"""
    abstract type Stock end 

`Stock` objects represent combinations of organisms and chemicals quantities. 

"""
abstract type Stock end 

"""
    struct Empty <:Stock end 

Singleton type that represents an empty Stock object.
"""    
struct Empty <:Stock end 
  



"""
    struct Mixture <:Stock 

`Mixture` objects are stocks that only contain [`Solid`](@ref) components. Mixtures must contain at least one solid. (Otherwise, they would be [`Empty`](@ref) stocks.)

"""
struct Mixture <:Stock  
    solids::SolidDict
    function Mixture(solids)
        for solid in reagents(solids)
            x=ustrip(solids[solid])
            x >= 0 || throw(DomainError(x,"$solid must have a non-negative mass")) 
        end 
        length(solids) >= 1 || throw(DomainError(length(solids),"mixtures must contain at least one solid"))
        new(solids)
    end 
end 


"""
    struct Solution <:Stock 

`Solution` objects are stocks that only contain at least one [`Liquid`](@ref) component but no organisms. Solutions may contain any number of [`Solid`](@ref) components

"""
struct Solution <: Stock 
    solids::SolidDict
    liquids::LiquidDict
    function Solution(solids,liquids)  
        # test for issues 
        for solid in reagents(solids)
            x=ustrip(solids[solid])
            x >= 0 || throw(DomainError(x,"$solid must have a non-negative mass")) 
        end
        for liquid in reagents(liquids)
            x=ustrip(liquids[liquid])
            x >= 0 || throw(DomainError(x,"$liquid must have a non-negative volume")) 
        end
        length(liquids) >= 1 || throw(DomainError(length(liquids),"solutions must contain at least one liquid"))
        return new(solids,liquids)
    end
end 

"""
    struct Culture <: Stock 

`Culture` objects are stocks that contain at least one [`Organism`](@ref). Cultures may contain any number of [`Solid`](@ref) or [`Liquid`](@ref) components.
"""
struct Culture <: Stock 
    organisms::Set{Organism}
    solids::SolidDict
    liquids::LiquidDict
    function Culture(organisms,solids,liquids)  
        # test for issues 
        for solid in reagents(solids)
            x=ustrip(solids[solid])
            x >= 0 || throw(DomainError(x,"$solid must have a non-negative mass")) 
        end
        for liquid in reagents(liquids)
            x=ustrip(liquids[liquid])
            x >= 0 || throw(DomainError(x,"$liquid must have a non-negative volume")) 
        end
        length(organisms) >= 1 || throw(DomainError(length(organisms),"solutions must contain at least one liquid"))
        return new(organisms, solids,liquids)
    end
end 

"""
    solids(::Stock)

access the solids Dict for a Stock. If no solids are present, return SolidDict()
"""
solids(c::Stock)=c.solids
solids(::Empty)=SolidDict() # Empty doesn't have a solids property


"""
    liquids(::Stock)

access the liquids Dict for a Stock. If no liquids are present, return LiquidDict()
"""
liquids(c::Stock)=c.liquids
liquids(::Empty)=LiquidDict() # Empty doesn't have a liquids property
liquids(c::Mixture)=LiquidDict() # Mixture doesn't have a liquids property


"""
    quantity(::Empty)

returns `missing` for the quantity of an Empty Stock
"""
quantity(c::Empty)=missing 

"""
    quantity(::Mixture)

returns the sum of each solid's mass in a Mixture
"""
function quantity(c::Mixture)
    s= values(solids(c))
    if length(s) == 0 
        return 0u"g"
    else
        return sum(s)
    end 
end 

"""
    quantity(::Stock)

returns the sum of each liquid's volume in a Stock
"""
function quantity(c::Stock)
    s=values(liquids(c))
    if length(s)==0
        return 0u"mL"
    else
        return sum(s)
    end 
end 


"""
    organisms(::Stock) 
return the `organisms` property of a Stock. If no organisms, are present, return Set{Organism}(). 
"""
organisms(c::Stock)=Set{Organism}()
organisms(c::Culture)=c.organisms



"""
    function Stock(organisms,solids,liquids)

a generic stock constructor that returns the appropriate stock subtype. 
"""
function Stock(organisms,solids,liquids) 
    o=length(organisms)
    s=length(solids)
    l=length(liquids)
    if o > 0 
        return Culture(organisms,solids,liquids)
    elseif o==0 && l > 0 
        return Solution(solids,liquids)
    elseif o==0 && l ==0 && s>0
        return Mixture(solids)
    else
        return Empty()
    end 
end 




"""
    reagents(x::Union{SolidDict,LiquidDict})

a wrapper for `collect(keys(x))` that returns an array of the chemical keys.
"""
function reagents(x::Union{SolidDict,LiquidDict})

    return collect(keys(x))
end 


# trivial constructors for mixtures and solutions 




"""
    *(quantity::Unitful.Amount,chemical::Solid)

Overload the `*` operator to construct a Mixture from a molar quantity of a solid. 
"""
function *(quantity::Unitful.Amount,chemical::Solid) 
    return Mixture(SolidDict(chemical => convert(prefquantunits(chemical),quantity,chemical)))
end 

"""
    *(quantity::Unitful.Mass,chemical::Solid)

Overload the `*` operator to construct a Mixture from a mass of a solid. 
"""
function *(quantity::Unitful.Mass,chemical::Solid) 
    return Mixture(SolidDict(chemical => uconvert(prefquantunits(chemical),quantity)))
end
"""
    *(quantity::Unitful.Mass,chemical::Solid)

Overload the `*` operator to construct a Solution from a volume of a liquid. 
"""
function *(quantity::Unitful.Volume,chemical::Liquid) 
    return Solution(SolidDict(),LiquidDict(chemical=>uconvert(prefquantunits(chemical),quantity)))
end 



"""
    *(num::Real,stock::Stock)

Overload the `*` operator to multiply the chemicals of a Stock by a scalar. Returns a new Stock with all chemical quantities scaled by a factor of `num`. 
"""
function *(num::Real,stock::Stock)
    new_solids=Dict{Solid,Unitful.Mass}()
    new_liquids=Dict{Liquid,Unitful.Volume}()
    for solid in reagents(solids(stock))
        new_solids[solid]=solids(stock)[solid] * num 
    end 
    for liquid in reagents(liquids(stock))
        new_liquids[liquid]=liquids(stock)[liquid]*num
    end 
    return Stock(organisms(stock),new_solids,new_liquids)
end 

*(stock::Stock,num::Real) = *(num,stock)

"""
    /(stock::Stock,num::Real)

Overload the `/` operator to divide a Stock by a scalar. Returns a new Stock with all chemical quantities scaled by a factor of `num` 
"""
/(stock::Stock,num::Real) = *(1/num,stock)




"""
    *(q::Unitful.Quantity,stock::Stock) 

Overload the `*` operator to divide a stock by a quantity. Returns a new stock scaled to have a total quantity q 
"""
function *(q::Unitful.Quantity,stock::Stock)
    num = convert(Float64,q/quantity(stock)) # ensures that num is a scalar, and throws a dimensional compatibility error if not
    return num * stock # scalar multiplation defined above
end 

*(stock::Stock,q::Unitful.Quantity) = *(q,stock) # enable commutative property 



function quantity_split(x::Unitful.Quantity)
    return (ustrip(x),string(Unitful.unit(x)))
end




"""
    volume_estimate(s::Stock)

Return the estimated volume of a Stock `s`

- *Empty* returns a value of `0u"mL"`
- *Mixture* approximates the volume based on the density of each reagent. Reagents with a missing
  density are excluded from the sum (rather than propagating `missing` and zeroing out the whole
  estimate) -- the result is therefore a lower bound, and a warning is emitted when this happens.
- *Solution* returns `quantity(s)`
"""
volume_estimate(s::Stock) = quantity(s)
volume_estimate(s::Empty)=0u"mL"

function volume_estimate(m::Mixture)
    vol=0u"mL"
    sols=solids(m)
    unknown=Solid[]
    for sol in reagents(sols)
        d=density(sol)
        if ismissing(d)
            push!(unknown,sol)
        else
            vol+=sols[sol]/d
        end
    end
    isempty(unknown) || @warn "volume_estimate: density unknown for $(join(name.(unknown),", ")); excluded from the estimate (result is a lower bound)"
    return vol
end


function ==(a::Stock,b::Stock) 
    all([organisms(a)==organisms(b),solids(a)==solids(b),liquids(a)==liquids(b)])
end 


function Base.hash(s::Stock, h::UInt)
    hash(organisms(s),hash(solids(s),hash(liquids(s),h)))
end 


function Base.in(str::Organism,stock::Stock)
    return str in organisms(stock)
end 

function Base.in(sol::Solid,stock::Stock)
    return sol in reagents(solids(stock))
end 

function Base.in(liq::Liquid,stock::Stock)
    return liq in reagents(liquids(stock))
end 



function isapprox(a::Stock,b::Stock;kwargs...)
    if keys(solids(a)) != keys(solids(b))
        return false 
    end 
    if keys(liquids(a)) != keys(liquids(b))
        return false 
    end 
    if organisms(a) != organisms(b)
        return false 
    end 
    for solid in reagents(solids(a)) 
        if !isapprox(solids(a)[solid],solids(b)[solid];kwargs...)
            return false 
        end 
    end 
    for liquid in reagents(liquids(a))
        if !isapprox(liquids(a)[liquid],liquids(b)[liquid];kwargs...)
            return false
        end
    end
    return true
end

function _stockrecipes(m::Module)
    sn = Symbol("#JLIMS_stockrecipes")
    if isdefined(m,sn)
        getproperty(m,sn)
    else
        Core.eval(m,:(const $sn = Dict{Symbol,Stock}()))
    end
end

"""
    const stock_recipes

Registry mapping a name to a [`Stock`](@ref) recipe registered via [`@stock`](@ref). Unlike a bare
`const` binding of a `Stock` value, only recipes registered this way are reachable via
[`@stock_str`](@ref) -- an intermediate `Stock` (e.g. a concentrated stock solution used only as an
ingredient in a larger recipe) never accidentally becomes discoverable.
"""
const stock_recipes = _stockrecipes(CHESSCore)

function stockrecipe_expr(m::Module,n,st)
    if m === CHESSCore
        :($(_stockrecipes(CHESSCore))[$n] = $st)
    else
        quote
            $(_stockrecipes(m))[$n] = $st
            $(_stockrecipes(CHESSCore))[$n] = $st
        end
    end
end

"""
    @stock name expr

Register `expr` (a [`Stock`](@ref)-producing expression) under `name`, both as a `const` binding
and in the [`stock_recipes`](@ref) registry -- mirrors [`@location_kind`](@ref). This is what makes
a recipe reachable via [`@stock_str`](@ref); a plain `const` binding of a `Stock` is not.

Example:
```julia-repl
julia> @stock saline_recipe 1u"mL" * water + 5u"g" * NaCl
saline_recipe

julia> stock"saline_recipe"
```
"""
macro stock(name,expr)
    n = Symbol(name)
    ln = Meta.quot(n)
    esc(quote
        haskey(CHESSCore.stock_recipes,$ln) && throw(ArgumentError("Stock recipe $($ln) already exists"))
        const $n = $expr
        $(stockrecipe_expr(__module__,ln,n))
        $n
    end)
end

"""
    @stock_str(kind)

String macro to recall a `Stock` recipe registered with [`@stock`](@ref), by name -- mirrors
[`@loc_str`](@ref)/[`@attr_str`](@ref)/[`@rgt_str`](@ref)/[`@chem_str`](@ref)/[`@org_str`](@ref), but
looks up [`stock_recipes`](@ref) directly rather than scanning for any correctly-typed `const`
binding: only recipes registered via [`@stock`](@ref) are reachable this way.

Example:
```julia-repl
julia> stock"thy_350mL"
```
"""
macro stock_str(kind)
    sym = Symbol(kind)
    ln = Meta.quot(sym)
    esc(quote
        haskey(CHESSCore.stock_recipes,$ln) || throw(ArgumentError(
            "Stock recipe `$($ln)` not found. Registered recipes: $(join(sort(string.(keys(CHESSCore.stock_recipes))), ", "))"))
        CHESSCore.stock_recipes[$ln]
    end)
end



