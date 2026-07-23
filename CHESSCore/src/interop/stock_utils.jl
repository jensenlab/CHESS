
## Internal constants

const string_unit_substitution= Dict(
    "%" => "percent",
    "" => "NoUnits"
)

const unit_string_substitution = Dict(values(string_unit_substitution) .=> keys(string_unit_substitution))


## String Conversion

function string_to_unit(str::AbstractString)

    if str in keys(string_unit_substitution)
        return Unitful.uparse(string_unit_substitution[str])
    else
        return Unitful.uparse(str)
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



function string_to_reagent(str::AbstractString,unit::Unitful.Units;reagent_context=CHESSCore,kwargs...)

    try
        return reagentparse(str;reagent_context=reagent_context)
    catch
    end
    @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
    if unit isa Unitful.DensityUnits || unit isa Unitful.MassUnits || unit isa Unitful.AmountUnits || unit isa Unitful.MolarityUnits
        # a solid mass concentration in vc format or a mass in q format
        return Solid(str,missing,missing,missing)
    elseif unit isa Unitful.DimensionlessUnits || unit isa Unitful.VolumeUnits # a %v/v concentration in vc format or a volume in q format
        return Liquid(str,missing,missing,missing)
    end

end

"""
    string_to_reagent(str::AbstractString, chem_type::Type{<:Reagent};
                      reagent_context=CHESSCore, kwargs...) -> Reagent

Convert a string into a `Reagent` instance.

The function first attempts to parse `str` using `CHESSCore.reagentparse`, which may
return a registered reagent object from `reagent_context`. If parsing fails, it
emits a warning and falls back to constructing a new reagent of type `chem_type`
using `str` as the identifier/name and `missing` for unknown properties.

# Arguments
- `str::AbstractString`: The reagent identifier to parse (e.g., a registered name,
  alias, or other parseable representation).
- `chem_type::Type{<:Reagent}`: Concrete `Reagent` subtype to instantiate if
  `str` is not registered / cannot be parsed.

# Keyword Arguments
- `reagent_context=CHESSCore`: Module or list of modules to search for registered
  reagents during parsing (forwarded to `reagentparse`).

# Returns
- A `Reagent` object. If `reagentparse` succeeds, the parsed/registered object is
  returned; otherwise, a new `chem_type(str, missing, missing, missing)` is returned.

# Notes
This function is intentionally permissive: unknown reagents do not error, but are
treated as reagents with unspecified properties (`missing`), which may affect
downstream calculations that require those properties.

See also: [`reagent_to_string`](@ref)

"""
function string_to_reagent(str::AbstractString,chem_type::Type{<:Reagent};reagent_context=CHESSCore,kwargs...)
    try
        return reagentparse(str;reagent_context=reagent_context)
    catch
    end
    @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
    return chem_type(str,missing,missing,missing)
end



"""
    reagent_to_string(r::CHESSCore.Reagent; reagent_context=CHESSCore, kwargs...) -> String

Convert a `CHESSCore.Reagent` into a stable string identifier.

Returns the *registered symbol* for `r` (via [`symbol`](@ref)) when it can be found in
`reagent_context` — this is useful because a registered reagent's display name
(`CHESSCore.name(r)`) is not necessarily the same string that [`reagentparse`](@ref) expects
to resolve it. If `r` isn't found (e.g. an ad hoc reagent built on the fly), falls back
to `CHESSCore.name(r)`, which is sufficient to reconstruct such reagents.

See also: [`string_to_reagent`](@ref)
"""
function reagent_to_string(r::CHESSCore.Reagent; reagent_context=CHESSCore,kwargs...)
    try
        return string(symbol(r; context=reagent_context))
    catch e
        e isa ArgumentError || rethrow()
        return name(r)
    end
end


## Stock queries
"""
    concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)

Return the concentration of an ingredient relative to the stock's own total (`CHESSCore.quantity(stock)`)
via [`_relative_amount`](@ref) — a mass for `Mixture`, a volume for `Solution`/`Culture`. This is what
the "vc" dataframe format needs: percent when the ingredient shares the total's physical dimension
(e.g. a liquid within a Solution's volume total, or a solid within a *Mixture's* mass total), an
amount-per-unit-of-total ratio otherwise (e.g. a solid's mass within a Solution's volume total, in
g/mL). Not `volume_estimate` -- that's a different, only-partially-defined physical-volume estimate
used elsewhere (`Well.jl` capacity checks, `pH`), not the right denominator for a relative
concentration.
"""
function concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    total = CHESSCore.quantity(stock)
    ismissing(total) && return 0*u"percent" # e.g. an Empty stock
    return _relative_amount(get(solids(stock),ingredient,0u"g"),total)
end

function concentration(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)
    total = CHESSCore.quantity(stock)
    ismissing(total) && return 0*u"percent"
    return _relative_amount(get(liquids(stock),ingredient,0u"mL"),total)
end



"""
    quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Solid)
    quantity(stock::CHESSCore.Stock,ingredient::CHESSCore.Liquid)

Return the quantity of an ingredient in a stock using the preferred units for that ingredient

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



function all_reagents(stock::CHESSCore.Stock)
         # Gather all ingredients contained in the sources, destinations, and priority list
         solids = reagents(CHESSCore.solids(stock))
         liqs = reagents(CHESSCore.liquids(stock))
         return collect(union(solids,liqs))
end

function all_reagents(stocks::Vector{<:CHESSCore.Stock})
    return collect(union(all_reagents.(stocks)...))
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
            out[:,reagent_to_string(i;kwargs...)]=vals
        end

    return out
end
