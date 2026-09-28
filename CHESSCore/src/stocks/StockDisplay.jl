function Base.show(io::IO,::MIME"text/plain",s::Empty;sigdigits::Integer=3)
    printstyled(io, "Empty Stock";bold=true)
end
function Base.show(io::IO,s::Empty;sigdigits::Integer=3)
    printstyled(io, "Empty Stock";bold=true)
end
"""
    _relative_amount(amt, total; digits=nothing)

Shared dimension-matching rule behind [`_reagent_table`](@ref) and `concentration`
(`src/interop/stock_utils.jl`): if `amt` shares `total`'s physical dimension, express it as a
percentage of `total`; otherwise express it as an amount-per-unit-of-`total` (e.g. g/mL). Optional
`digits` rounds the result.
"""
function _relative_amount(amt, total; digits=nothing)
    ratio = amt/total
    result = dimension(unit(amt))==dimension(unit(total)) ? uconvert(u"percent",ratio) : ratio
    return isnothing(digits) ? result : round(result;digits=digits)
end

"""
    _reagent_table(dict::Union{SolidDict,LiquidDict,OrganismDict}, total; digits=2)

Shared logic behind both `show(::MIME"text/plain",::Stock)` and [`reagent_display`](@ref): sort
`dict`'s reagents by name and compute each one's amount and concentration relative to `total` (the
stock's overall `quantity`/`volume_estimate`), via [`_relative_amount`](@ref). Returns
`(sorted_reagents, amounts, concentrations)`, all empty if `dict` is empty. For an `OrganismDict`,
"concentration" comes out as `Biomass/total` -- i.e. the current, on-demand-derived OD -- since
`Biomass`'s dimension differs from `total`'s (see [`_relative_amount`](@ref)). `digits=nothing`
leaves the values unrounded, for display formatting by [`_pretty_quantity`](@ref).
"""
function _reagent_table(dict::Union{SolidDict,LiquidDict,OrganismDict}, total; digits=2)
    arr = sort(reagents(dict), by=name)
    isempty(arr) && return arr, Unitful.Quantity[], Unitful.Quantity[]
    raw = [dict[x] for x in arr]
    amounts = isnothing(digits) ? raw : round.(raw; digits=digits)
    concs = [_relative_amount(dict[x],total;digits=digits) for x in arr]
    return arr, amounts, concs
end

# Units a displayed quantity may be rescaled between, largest first, keyed by physical dimension.
# Concentrations keep a per-mL denominator and only rescale the numerator.
const _display_unit_ladders = Dict(
    dimension(u"L") => [u"L", u"mL", u"µL", u"nL"],
    dimension(u"g") => [u"kg", u"g", u"mg", u"µg", u"ng"],
    dimension(u"mol") => [u"mol", u"mmol", u"µmol", u"nmol"],
    dimension(u"OD*mL") => [u"OD*L", u"OD*mL", u"OD*µL", u"OD*nL"],
    dimension(u"g/mL") => [u"g/mL", u"mg/mL", u"µg/mL", u"ng/mL"],
    dimension(u"mol/L") => [u"M", u"mM", u"µM", u"nM"],
)

# `x` formatted to `sigdigits` significant figures, keeping trailing zeros ("2.00", "19.8", "198").
function _format_sigdigits(x::Real, sigdigits::Integer)
    iszero(x) && return "0"
    isfinite(x) || return string(Float64(x)) # e.g. the Inf OD of a culture with no liquid
    r = round(Float64(x); sigdigits=sigdigits)
    decimals = max(sigdigits - 1 - floor(Int, log10(abs(r))), 0)
    return Printf.format(Printf.Format("%.$(decimals)f"), r)
end

"""
    _pretty_quantity(q; sigdigits=3) -> String

Display string for `q` with `sigdigits` significant figures. Volumes, masses, molar amounts,
biomass, mass-per-volume and molar concentrations are rescaled to the metric prefix that puts the
number in `[1, 1000)` -- `2.00 mg` rather than `0.0 g`, `198 μL` rather than `0.2 mL` -- clamped to
the smallest and largest prefixes CHESS displays. Any other unit (percent, OD, ...) keeps its unit.
Zero keeps `q`'s own unit, and `missing` displays as `"missing"`.
"""
_pretty_quantity(::Missing; sigdigits::Integer=3) = "missing"
function _pretty_quantity(q::Unitful.Quantity; sigdigits::Integer=3)
    ladder = get(_display_unit_ladders, dimension(q), nothing)
    if isnothing(ladder) || iszero(ustrip(q))
        u = unit(q)
    else
        i = something(findfirst(u -> abs(ustrip(uconvert(u, q))) >= 1, ladder), length(ladder))
        # rounding can carry into the next prefix up (999.6 μL -> 1.00 mL)
        if i > 1 && abs(round(ustrip(uconvert(ladder[i], q)); sigdigits=sigdigits)) >= 1000
            i -= 1
        end
        u = ladder[i]
    end
    return string(_format_sigdigits(ustrip(uconvert(u, q)), sigdigits), " ", sprint(show, u))
end

# Print one component table (solids, liquids, or organisms) of a stock's text/plain display.
function _show_component_table(io::IO, label::Symbol, dict, total, amount_header::Symbol,
        conc_header::Symbol; sigdigits::Integer=3)
    arr, amounts, concs = _reagent_table(dict, total; digits=nothing)
    df = DataFrame(label => arr, :Name => name.(arr),
        amount_header => String[_pretty_quantity(a; sigdigits=sigdigits) for a in amounts],
        conc_header => String[_pretty_quantity(c; sigdigits=sigdigits) for c in concs])
    show(io, df; eltypes=false, show_row_number=false, summary=false, alignment=[:l, :l, :r, :r])
end

function _show_stock_header(io::IO, s::Stock, n_reagents::Integer; sigdigits::Integer=3)
    q = quantity(s)
    ismissing(q) || printstyled(io, _pretty_quantity(q; sigdigits=sigdigits), " "; bold=true)
    printstyled(io, "$(typeof(s)) ($n_reagents reagent(s))"; bold=true)
end

function Base.show(io::IO,::MIME"text/plain",s::Mixture;sigdigits::Integer=3)
    _show_stock_header(io, s, length(solids(s)); sigdigits=sigdigits)
    print(io, "\n")
    _show_component_table(io, :Solids, solids(s), quantity(s), :Amount, :Concentration; sigdigits=sigdigits)
    print(io,"\n\n")
end

function Base.show(io::IO,::MIME"text/plain",s::Solution;sigdigits::Integer=3)
    _show_stock_header(io, s, length(solids(s))+length(liquids(s)); sigdigits=sigdigits)
    print(io, "\n")
    if length(solids(s)) > 0
        _show_component_table(io, :Solids, solids(s), quantity(s), :Amount, :Concentration; sigdigits=sigdigits)
        print(io,"\n\n")
    end
    _show_component_table(io, :Liquids, liquids(s), quantity(s), :Amount, :Concentration; sigdigits=sigdigits)
end

function Base.show(io::IO,::MIME"text/plain",s::Culture;sigdigits::Integer=3)
    _show_stock_header(io, s, length(solids(s))+length(liquids(s)); sigdigits=sigdigits)
    print(io, "\n")
    _show_component_table(io, :Organisms, organisms(s), quantity(s), :Biomass, :OD; sigdigits=sigdigits)
    print(io,"\n\n")
    if length(solids(s)) > 0
        _show_component_table(io, :Solids, solids(s), quantity(s), :Amount, :Concentration; sigdigits=sigdigits)
        print(io,"\n\n")
    end
    if length(liquids(s)) > 0
        _show_component_table(io, :Liquids, liquids(s), quantity(s), :Amount, :Concentration; sigdigits=sigdigits)
        print(io,"\n\n")
    end
end

function Base.show(io::IO,s::Stock;sigdigits::Integer=3)
    _show_stock_header(io, s, length(solids(s))+length(liquids(s)); sigdigits=sigdigits)
end

function out_dict(chems,amts,concs)

    out_dict=Dict{String,Dict{String,Tuple{Number,String}}}()
    for i in eachindex(chems)
        out_dict[name(chems[i])]=Dict("Amount"=>quantity_split(amts[i]),"Concentration"=>quantity_split(concs[i]))
    end
    return out_dict
end

"""
    reagent_display(s::Stock; digits=2)

Return `(solids, liquids, organisms)` for `s`: all three are `Dict{String,Dict{String,Tuple}}` keyed
by name, each holding `"Amount"`/`"Concentration"` (value, unit) tuples computed by
[`_reagent_table`](@ref) (the same logic `show(::MIME"text/plain",::Stock)` uses). For `organisms`,
`"Amount"` is each organism's [`Biomass`](@ref) and `"Concentration"` is its current, on-demand OD.
"""
function reagent_display(s::Empty;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Dict{String,Dict{String,Tuple{Number,String}}}()
    return out_solids,out_liquids,out_organisms
end

function reagent_display(s::Mixture;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Dict{String,Dict{String,Tuple{Number,String}}}()
    q=quantity(s)
    arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
    out_solids=out_dict(arr_sol,amt_sol,conc_sol)
    return out_solids,out_liquids,out_organisms
end

function reagent_display(s::Solution;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Dict{String,Dict{String,Tuple{Number,String}}}()
    q=quantity(s)
    if length(solids(s))>0
        arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
        out_solids=out_dict(arr_sol,amt_sol,conc_sol)
    end
    arr_liq,amt_liq,conc_liq=_reagent_table(liquids(s),q;digits=digits)
    out_liquids=out_dict(arr_liq,amt_liq,conc_liq)
    return out_solids,out_liquids,out_organisms
end

function reagent_display(s::Culture;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Dict{String,Dict{String,Tuple{Number,String}}}()
    q=quantity(s)
    if length(solids(s))>0
        arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
        out_solids=out_dict(arr_sol,amt_sol,conc_sol)
    end
    if length(liquids(s))>0
        arr_liq,amt_liq,conc_liq=_reagent_table(liquids(s),q;digits=digits)
        out_liquids=out_dict(arr_liq,amt_liq,conc_liq)
    end
    if length(organisms(s))>0
        arr_org,amt_org,conc_org=_reagent_table(organisms(s),q;digits=digits)
        out_organisms=out_dict(arr_org,amt_org,conc_org)
    end
    return out_solids,out_liquids,out_organisms
end
