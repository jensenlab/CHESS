
## Internal constants 

const string_unit_substitution= Dict(
    "%" => "percent",
    "" => "NoUnits"
)

const unit_string_substitution = Dict(values(string_unit_substitution) .=> keys(string_unit_substitution))

const chemical_access_dict=Dict(
    JLIMS.Solid => JLIMS.solids ,
    JLIMS.Liquid => JLIMS.liquids
)


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
    


function string_to_reagent(str::AbstractString,unit::Unitful.Units;chem_context::Vector{Module}=[JLIMS],kwargs...) 
    
    try 
        return chemparse(str;chem_context=chem_context)
    catch 
    end 
    #=
    try 
        return orgparse(str;chem_context=chem_context)
    catch 
    end 
    =#
    @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
    if unit isa Unitful.DensityUnits || unit isa Unitful.MassUnits || unit isa Unitful.AmountUnits || unit isa Unitful.MolarityUnits 
        # a solid mass concentration in vc format or a mass in q format 
        return Solid(str,missing,missing,missing)
    elseif unit isa Unitful.DimensionlessUnits || unit isa Unitful.VolumeUnits # a %v/v concentration in vc format or a volume in q format 
        return Liquid(str,missing,missing,missing) 
    end 

end 

"""
    string_to_reagent(str::AbstractString, chem_type::Type{<:Chemical};
                      chem_context::Vector{Module} = [JLIMS], kwargs...) -> Chemical

Convert a string into a reagent (`Chemical`) instance.

The function first attempts to parse `str` using `JLIMS.chemparse`, which may
return a registered reagent/chemical object from the provided `chem_context`.
If parsing fails, it emits a warning and falls back to constructing a new
chemical of type `chem_type` using `str` as the identifier/name and `missing`
for unknown properties.

# Arguments
- `str::AbstractString`: The reagent identifier to parse (e.g., a registered name,
  alias, or other parseable representation).
- `chem_type::Type{<:Chemical}`: Concrete `Chemical` subtype to instantiate if
  `str` is not registered / cannot be parsed.

# Keyword Arguments
- `chem_context::Vector{Module} = [JLIMS]`: Modules to search for registered
  chemicals during parsing (forwarded to `chemparse`).

# Returns
- A `Chemical` object. If `chemparse` succeeds, the parsed/registered object is
  returned; otherwise, a new `chem_type(str, missing, missing, missing)` is returned.

# Notes
This function is intentionally permissive: unknown reagents do not error, but are
treated as chemicals with unspecified properties (`missing`), which may affect
downstream calculations that require those properties.

See also: [`reagent_to_string`](@ref)

"""
function string_to_reagent(str::AbstractString,chem_type::Type{<:Chemical};chem_context::Vector{Module}=[JLIMS],kwargs...)
        try 
        return chemparse(str;chem_context=chem_context)
    catch 
    end 
    @warn("reagent $str not registered. parsing $str assuming it is a chemical. No chemical properties known.")
    return chem_type(str,missing,missing,missing)
end 



"""
    reagent_to_string(chem::JLIMS.Chemical; chem_context::Vector{Module} = [JLIMS], kwargs...) -> String

Convert a `JLIMS.Chemical` into a stable string identifier.

This function attempts to return the *registry key* for `chem` when the chemical is
registered in one of the modules listed in `chem_context`. This is useful because a
registered chemical’s display name (`JLIMS.name(chem)`) is not necessarily the same
string that `chemparse` expects to resolve it.

If `chem` is not found among the registered chemicals in `chem_context`, the function
falls back to returning `JLIMS.name(chem)`, which is sufficient to reconstruct
“ad hoc” (unregistered) chemicals created on the fly.

See also: [`string_to_reagent`](@ref)
"""
function reagent_to_string(chem::JLIMS.Chemical; chem_context::Vector{Module}=[JLIMS],kwargs...)
        all_chem_symbols = vcat(map(x->filter(y-> JLIMS.chemstr_check_bool(getfield(x,y)),names(x;all=true)),chem_context)...) # all chemical symbols 
        chem_strs = String.(all_chem_symbols)
        chem_dict = Dict(chemparse.(chem_strs;chem_context=chem_context)  .=> String.(chem_strs))
        if chem in keys(chem_dict) 
            return chem_dict[chem] # JLIMS registered chemicals appear in the chem dict. Their name is a display name and not necessarily the key used to find the chemical
        else
            return JLIMS.name(chem) # Chemicals that are not registered (generated on the fly) can be re-generated with just the name 
        end 
end 


## Stock queries 
""" 
    concentration(stock::JLIMS.Stock,ingredient::JLIMS.Ingredient)

Return the concentration of an ingredient in a stock using the preferred units for that ingredient and stock 
    

"""
function concentration(stock::JLIMS.Stock,ingredient::JLIMS.Solid) 
    if ingredient in stock 
        quant = solids(stock)[ingredient]/JLIMS.quantity(stock)
        if !isa(quant,Unitful.Density)
            return convert(u"g/µL",quant,ingredient) # molar concentration issue 
        else 
            return uconvert(u"g/µL",quant)
        end 
    else
        return 0*u"g/µL"
    end 
end 

function concentration(stock::JLIMS.Stock,ingredient::JLIMS.Liquid) 
    if ingredient in stock 
        return uconvert(u"percent",liquids(stock)[ingredient]/JLIMS.quantity(stock))
    else
        return 0*u"percent"
    end 
end 



""" 
    quantity(stock::JLIMS.Stock,ingredient::JLIMS.Ingredient)

Return the quantity of an ingredient in a stock using the preferred units for that ingredient
    

"""
function quantity(stock::JLIMS.Stock,ingredient::JLIMS.Solid)
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


function quantity(stock::JLIMS.Stock,ingredient::JLIMS.Liquid)
    if ingredient in stock
        return uconvert(u"µl",liquids(stock)[ingredient])
    else
        return 0*u"µL"
    end 
end 



function all_chemicals(stock::JLIMS.Stock)
         # Gather all ingredients contained in the sources, destinations, and priority list 
         solids = chemicals(JLIMS.solids(stock))
         liqs = chemicals(JLIMS.liquids(stock))
         return collect(union(solids,liqs))
end

function all_chemicals(stocks::Vector{<:JLIMS.Stock})
    return collect(union(all_chemicals.(stocks)...))
end





## Stock array conversion 

function chemical_df(stocks::Vector{<:JLIMS.Stock};measure::Function=concentration,kwargs...) # can return concentration or quantity 
    ingredients = all_chemicals(stocks)
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



