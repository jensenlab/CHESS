
## Internal constants

const string_unit_substitution= Dict(
    "%" => "percent",
    "" => "NoUnits"
)

const unit_string_substitution = Dict(values(string_unit_substitution) .=> keys(string_unit_substitution))


## String Conversion

function string_to_unit(str::AbstractString)
    # unit_context has to include JensenLabUnits explicitly -- Unitful.uparse only searches
    # globally *registered* unit modules automatically via the `u"..."` macro, not via this
    # function form, so a custom unit like OD (used by Biomass) would otherwise fail to parse here.
    if str in keys(string_unit_substitution)
        return Unitful.uparse(string_unit_substitution[str];unit_context=[Unitful,JensenLabUnits])
    else
        return Unitful.uparse(str;unit_context=[Unitful,JensenLabUnits])
    end
end

function unit_to_string(unit::Unitful.Units)
    ustr = string(unit)
    if ustr in keys(unit_string_substitution)
        return unit_string_substitution[ustr]
    else
        return ustr
    end
end

function unit_to_string(::Missing)
    return ""
end



"""
    string_to_component(str::AbstractString, unit::Unitful.Units;
                        reagent_context=CHESSCore, org_context=CHESSCore, kwargs...) -> StockComponent

Infer a `StockComponent` from `str` and the dimension of `unit` -- used by the "vc"/"q" DataFrame
format, where a column's identity has to be guessed from its unit when it isn't otherwise
registered. Tries `reagentparse(str)` first; on failure, dispatches on `unit`'s dimension: a bare
`OD` dimension (vc's organism "concentration") or a `Biomass` dimension (`OD*Volume`, q's organism
quantity) both delegate to [`string_to_component(str,::Type{Organism})`](@ref); mass/molarity/
density/amount dimensions assume an unregistered `Solid`; dimensionless/volume dimensions assume an
unregistered `Liquid`.
"""
function string_to_component(str::AbstractString,unit::Unitful.Units;reagent_context=CHESSCore,org_context=CHESSCore,kwargs...)

    try
        return reagentparse(str;reagent_context=reagent_context)
    catch
    end
    if dimension(unit) == dimension(u"OD*mL") || dimension(unit) == dimension(u"OD")
        # an organism's OD-based "concentration" in vc format, or its Biomass in q format
        return string_to_component(str, Organism; org_context=org_context, kwargs...)
    elseif unit isa Unitful.DensityUnits || unit isa Unitful.MassUnits || unit isa Unitful.AmountUnits || unit isa Unitful.MolarityUnits
        # a solid mass concentration in vc format or a mass in q format
        @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
        return Solid(str,missing,missing,missing)
    elseif unit isa Unitful.DimensionlessUnits || unit isa Unitful.VolumeUnits # a %v/v concentration in vc format or a volume in q format
        @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
        return Liquid(str,missing,missing,missing)
    end

end

"""
    string_to_component(str::AbstractString, chem_type::Type{<:Reagent};
                        reagent_context=CHESSCore, kwargs...) -> Reagent
    string_to_component(str::AbstractString, ::Type{Organism};
                        org_context=CHESSCore, kwargs...) -> Organism

Convert a string into a `Reagent` or `Organism` instance.

The `Reagent` method first attempts to parse `str` using `CHESSCore.reagentparse`, which may
return a registered reagent object from `reagent_context`. If parsing fails, it
emits a warning and falls back to constructing a new reagent of type `chem_type`
using `str` as the identifier/name and `missing` for unknown properties.

The `Organism` method first attempts `CHESSCore.orgparse` (`org_context`); if that fails, it
emits a warning and falls back to splitting `str` into `"genus species strain"` form -- errors if
`str` doesn't have exactly three space-separated parts, since (unlike `Reagent`) `Organism` has no
`missing`-tolerant fields to build a permissive fallback from a single unstructured string.

# Arguments
- `str::AbstractString`: The reagent/organism identifier to parse (e.g., a registered name,
  alias, or other parseable representation).
- `chem_type::Type{<:Reagent}`: Concrete `Reagent` subtype to instantiate if
  `str` is not registered / cannot be parsed.

# Keyword Arguments
- `reagent_context=CHESSCore`: Module or list of modules to search for registered
  reagents during parsing (forwarded to `reagentparse`).
- `org_context=CHESSCore`: Module or list of modules to search for registered
  organisms during parsing (forwarded to `orgparse`).

# Returns
- A `Reagent` object. If `reagentparse` succeeds, the parsed/registered object is
  returned; otherwise, a new `chem_type(str, missing, missing, missing)` is returned.
- An `Organism` object. If `orgparse` succeeds, the parsed/registered object is returned;
  otherwise, `str` is split into `Organism(genus, species, strain)`.

# Notes
The `Reagent` method is intentionally permissive: unknown reagents do not error, but are
treated as reagents with unspecified properties (`missing`), which may affect
downstream calculations that require those properties. The `Organism` method is not --
an unregistered, malformed organism string errors rather than guessing.

See also: [`component_to_string`](@ref)

"""
function string_to_component(str::AbstractString,chem_type::Type{<:Reagent};reagent_context=CHESSCore,kwargs...)
    try
        return reagentparse(str;reagent_context=reagent_context)
    catch
    end
    @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
    return chem_type(str,missing,missing,missing)
end

function string_to_component(str::AbstractString, ::Type{Organism}; org_context=CHESSCore, kwargs...)
    try
        return orgparse(str; org_context=org_context)
    catch
    end
    @warn("organism $str not registered. parsing $str assuming \"genus species strain\" form.")
    parts = split(str)
    length(parts) == 3 || error("cannot parse organism \"$str\" -- not registered and not in \"genus species strain\" form")
    return Organism(parts[1], parts[2], parts[3])
end



"""
    component_to_string(r::CHESSCore.Reagent; reagent_context=CHESSCore, kwargs...) -> String
    component_to_string(o::CHESSCore.Organism; org_context=CHESSCore, kwargs...) -> String

Convert a `CHESSCore.Reagent` or `CHESSCore.Organism` into a stable string identifier.

Returns the *registered symbol* for the argument (via [`symbol`](@ref)) when it can be found in
`reagent_context`/`org_context` — this is useful because a registered component's display name
(`CHESSCore.name(x)`) is not necessarily the same string that [`reagentparse`](@ref)/[`orgparse`](@ref)
expect to resolve it. If not found (e.g. an ad hoc reagent/organism built on the fly), falls back
to `CHESSCore.name(x)`, which is sufficient to reconstruct such components.

See also: [`string_to_component`](@ref)
"""
function component_to_string(r::CHESSCore.Reagent; reagent_context=CHESSCore,kwargs...)
    try
        return string(symbol(r; context=reagent_context))
    catch e
        e isa ArgumentError || rethrow()
        return name(r)
    end
end

function component_to_string(o::CHESSCore.Organism; org_context=CHESSCore, kwargs...)
    try
        return string(symbol(o; context=org_context))
    catch e
        e isa ArgumentError || rethrow()
        return name(o)
    end
end


## Stock queries
"""
    concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Organism)

Return the concentration of an ingredient relative to the stock's own total (`CHESSCore.quantity(stock)`)
via [`_relative_amount`](@ref) — a mass for `Mixture`, a volume for `Solution`/`Culture`. This is what
the "vc" dataframe format needs: percent when the ingredient shares the total's physical dimension
(e.g. a liquid within a Solution's volume total, or a solid within a *Mixture's* mass total), an
amount-per-unit-of-total ratio otherwise (e.g. a solid's mass within a Solution's volume total, in
g/mL). Not `volume_estimate` -- that's a different, only-partially-defined physical-volume estimate
used elsewhere (`Well.jl` capacity checks, `pH`), not the right denominator for a relative
concentration.

For an `Organism`, [`Biomass`](@ref)'s dimension (`OD*Volume`) never matches the volume total's, so
this always takes the cross-dimension branch and returns a plain `Biomass/total` ratio in `OD` --
i.e. the culture's current, on-demand-derived optical density, never a stored value.
"""
function concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    total = CHESSCore.quantity(stock)
    # e.g. an Empty stock -- 0 g/mL (not 0 percent) to stay dimensionally consistent with the
    # Solution/Culture case (a solid's mass relative to a volume total, matching the common case
    # this "vc" dataframe format is used for), since a Mixture-total (percent) can't be assumed for
    # a stock with no total at all. Mixing 0-percent and 0-g/mL rows for the same reagent column
    # breaks component_dict's row-1-only unit classification in get_vc_components/vc_to_stock.
    ismissing(total) && return 0*u"g/mL"
    return _relative_amount(get(solids(stock),ingredient,0u"g"),total)
end

function concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    total = CHESSCore.quantity(stock)
    ismissing(total) && return 0*u"percent"
    return _relative_amount(get(liquids(stock),ingredient,0u"mL"),total)
end

function concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Organism)
    total = CHESSCore.quantity(stock)
    ismissing(total) && return 0*u"OD"
    return _relative_amount(get(organisms(stock),ingredient,0u"OD*mL"),total)
end



"""
    quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Organism)

Return the quantity of an ingredient in a stock using the preferred units for that ingredient (an
organism's [`Biomass`](@ref) in `OD*mL`).

"""
function quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    if ingredient in stock
        quant = solids(stock)[ingredient]
        if !isa(quant,Unitful.Mass)
            return convert(u"g",quant,ingredient)
        else
            return uconvert(u"g",quant)
        end
    else
        return 0*u"g"
    end
end


function quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    if ingredient in stock
        return uconvert(u"µl",liquids(stock)[ingredient])
    else
        return 0*u"µL"
    end
end

function quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Organism)
    if ingredient in stock
        return uconvert(u"OD*mL",organisms(stock)[ingredient])
    else
        return 0*u"OD*mL"
    end
end



function all_reagents(stock::CHESSCore.Stock)
         # Gather all ingredients contained in the sources, destinations, and priority list
         solids = reagents(CHESSCore.solids(stock))
         liqs = reagents(CHESSCore.liquids(stock))
         return collect(union(solids,liqs))
end

function all_reagents(stocks::Vector{<:CHESSCore.Stock})
    return collect(union(all_reagents.(stocks)...))
end

"""
    all_components(stock::Stock) -> Vector{<:StockComponent}
    all_components(stocks::Vector{<:Stock}) -> Vector{<:StockComponent}

Like [`all_reagents`](@ref), but also includes any [`Organism`](@ref)s present -- gathers every
[`StockComponent`](@ref) (reagent or organism) a `Stock` (or collection of `Stock`s) contains.
`all_reagents` itself is unchanged and remains organism-blind; use `all_components` wherever
organisms should participate in the enumeration.
"""
function all_components(stock::CHESSCore.Stock)
    solids = reagents(CHESSCore.solids(stock))
    liqs = reagents(CHESSCore.liquids(stock))
    orgs = reagents(CHESSCore.organisms(stock))
    return collect(union(solids,liqs,orgs))
end

function all_components(stocks::Vector{<:CHESSCore.Stock})
    return collect(union(all_components.(stocks)...))
end




## Stock array conversion

function reagent_df(stocks::Vector{<:CHESSCore.Stock};measure::Function=concentration,kwargs...) # can return concentration or quantity
    ingredients = all_reagents(stocks)
    out=DataFrame()
        for i in ingredients
            vals=Any[]
            for s in stocks
                push!(vals,measure(s,i))
            end
            out[:,component_to_string(i;kwargs...)]=vals
        end

    return out
end

"""
    component_df(stocks::Vector{<:Stock}; measure::Function=concentration, kwargs...) -> DataFrame

Like [`reagent_df`](@ref), but gathers via [`all_components`](@ref) instead of [`all_reagents`](@ref),
so organisms are included as columns alongside reagents (`measure` -- `concentration` or `quantity`
-- already has `Organism` methods).
"""
function component_df(stocks::Vector{<:CHESSCore.Stock};measure::Function=concentration,kwargs...)
    ingredients = all_components(stocks)
    out=DataFrame()
        for i in ingredients
            vals=Any[]
            for s in stocks
                push!(vals,measure(s,i))
            end
            out[:,component_to_string(i;kwargs...)]=vals
        end

    return out
end
