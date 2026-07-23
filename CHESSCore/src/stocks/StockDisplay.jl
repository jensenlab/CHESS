
function Base.show(io::IO,::MIME"text/plain",s::Empty;digits::Integer=2)
    printstyled(io, "Empty Stock";bold=true)
end
function Base.show(io::IO,s::Empty;digits::Integer=2)
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
    _reagent_table(dict::Union{SolidDict,LiquidDict}, total; digits=2)

Shared display logic behind both `show(::MIME"text/plain",::Stock)` and [`reagent_display`](@ref):
sort `dict`'s reagents by name and compute each one's raw amount and concentration relative to
`total` (the stock's overall `quantity`/`volume_estimate`), via [`_relative_amount`](@ref). Returns
`(sorted_reagents, amounts, concentrations)`, all empty if `dict` is empty.
"""
function _reagent_table(dict::Union{SolidDict,LiquidDict}, total; digits=2)
    arr = sort(reagents(dict), by=name)
    isempty(arr) && return arr, Unitful.Quantity[], Unitful.Quantity[]
    amounts = round.([dict[x] for x in arr]; digits=digits)
    concs = [_relative_amount(dict[x],total;digits=digits) for x in arr]
    return arr, amounts, concs
end

function Base.show(io::IO,::MIME"text/plain",s::Mixture;digits::Integer=2)
    typstr=string(typeof(s))
    q=quantity(s)
    printstyled(io,round(q;digits=digits)," ";bold=true)
    printstyled(io, "$typstr ($(length(solids(s))) reagent(s))\n";bold=true)
    arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
    df_sol=DataFrame(Solids=arr_sol,Name=name.(arr_sol),Amount=amt_sol,Concentration=conc_sol)
    show(io,df_sol;eltypes=false,show_row_number=false,summary=false)
    print(io,"\n\n")
end

function Base.show(io::IO,::MIME"text/plain",s::Solution;digits::Integer=2)
    typstr=string(typeof(s))
    q=quantity(s)
    printstyled(io,round(q;digits=digits)," ";bold=true)
    printstyled(io, "$typstr ($(length(solids(s))+length(liquids(s))) reagent(s))\n";bold=true)
    if length(solids(s)) > 0
        arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
        df_sol=DataFrame(Solids=arr_sol,Name=name.(arr_sol),Amount=amt_sol,Concentration=conc_sol)
        show(io,df_sol;eltypes=false,show_row_number=false,summary=false)
        print(io,"\n\n")
    end
    arr_liq,amt_liq,conc_liq=_reagent_table(liquids(s),q;digits=digits)
    df_liq=DataFrame(Liquids=arr_liq,Name=name.(arr_liq),Amount=amt_liq,Concentration=conc_liq)
    show(io,df_liq;eltypes=false,show_row_number=false,summary=false)
end
function Base.show(io::IO,::MIME"text/plain",s::Culture;digits::Integer=2)
    typstr=string(typeof(s))
    q=quantity(s)
    printstyled(io,round(q;digits=digits)," ";bold=true)
    printstyled(io, "$typstr ($(length(solids(s))+length(liquids(s))) reagent(s))\n";bold=true)
    arr_org=sort(collect(organisms(s)),by=name)
    df_org=DataFrame(Organisms=arr_org)
    show(io,df_org;eltypes=false,show_row_number=false,summary=false)
    print(io,"\n\n")
    if length(solids(s)) > 0
        arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
        df_sol=DataFrame(Solids=arr_sol,Name=name.(arr_sol),Amount=amt_sol,Concentration=conc_sol)
        show(io,df_sol;eltypes=false,show_row_number=false,summary=false)
        print(io,"\n\n")
    end
    if length(liquids(s)) > 0
        arr_liq,amt_liq,conc_liq=_reagent_table(liquids(s),q;digits=digits)
        df_liq=DataFrame(Liquids=arr_liq,Name=name.(arr_liq),Amount=amt_liq,Concentration=conc_liq)
        show(io,df_liq;eltypes=false,show_row_number=false,summary=false)
        print(io,"\n\n")
    end
end
function Base.show(io::IO,s::Stock;digits::Integer=2)
    typstr=string(typeof(s))
    if !ismissing(quantity(s))
        printstyled(io,round(quantity(s);digits=digits)," ";bold=true)
    end
    printstyled(io, "$typstr ($(length(solids(s))+length(liquids(s))) reagent(s))";bold=true)
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

Return `(solids, liquids, organisms)` for `s`: `solids`/`liquids` are `Dict{String,Dict{String,Tuple}}`
keyed by reagent name, each holding `"Amount"`/`"Concentration"` (value, unit) tuples computed by
[`_reagent_table`](@ref) (the same logic `show(::MIME"text/plain",::Stock)` uses); `organisms` lists
the stock's organisms.
"""
function reagent_display(s::Empty;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Vector{String}[]
    return out_solids,out_liquids,out_organisms
end

function reagent_display(s::Mixture;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Vector{String}[]
    q=quantity(s)
    arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
    out_solids=out_dict(arr_sol,amt_sol,conc_sol)
    return out_solids,out_liquids,out_organisms
end

function reagent_display(s::Solution;digits=2)
    out_solids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_liquids=Dict{String,Dict{String,Tuple{Number,String}}}()
    out_organisms=Vector{String}[]
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
    out_organisms=Vector{String}[]
    q=quantity(s)
    if length(solids(s))>0
        arr_sol,amt_sol,conc_sol=_reagent_table(solids(s),q;digits=digits)
        out_solids=out_dict(arr_sol,amt_sol,conc_sol)
    end
    if length(liquids(s))>0
        arr_liq,amt_liq,conc_liq=_reagent_table(liquids(s),q;digits=digits)
        out_liquids=out_dict(arr_liq,amt_liq,conc_liq)
    end
    out_organisms=sort(collect(organisms(s)),by=name)
    return out_solids,out_liquids,out_organisms
end
