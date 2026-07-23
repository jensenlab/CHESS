



"""
    struct Organism

A unique species (and strain). organisms can be combined with [`Stock`](@ref) objects to create [`Culture`](@ref) objects

`Organsim` objects have three properties: 
1) `genus`: The strain's taxonomic genus
2) `species`: The Strains taxonomic species
3) `strain`: The strain's identifier


"""
struct Organism
    genus::String
    species::String
    strain::String
end 

"""
    macro organism(labsymb, genus, species, strain)

A macro to quickly define a new `Organism` object and import it into the workspace under `labname`. 

"""
macro organism(labsymb,genus,species,strain)

    expr =Expr(:block)
    push!(expr.args,quote 
        Base.@__doc__ $CHESSCore.@organism_symbols $labsymb $genus $species $strain
        end 
    )

    push!(expr.args,quote
        $labsymb
    end )

    esc(expr)
end 



macro organism_symbols(labsymb,genus,species,strain)
    ls= Symbol(labsymb)
    ln = Meta.quot(ls)
    docstr= """
            $labsymb

       The organism $genus $species $strain  

        See also: [`Organism`](@ref)
        """
    oprops = :($genus,$species,$strain)  
    esc(quote

        $(orgprops_expr(__module__,ln,oprops))
        const global $ls = Organism($genus,$species,$strain)
        @doc $docstr $ls 
    end)
end 





function orgprops_expr(m::Module,n,orgprops)
    if m === CHESSCore
        :($(_orgprops(CHESSCore))[$n]= $orgprops)
    else
        # We add the chemical properties to dictionaries in both CHESSCore and the module `m` so that the factor is available in both
        quote 
            $(_orgprops(m))[$n]=$orgprops
            $(_orgprops(CHESSCore))[$n]=$orgprops
        end 
    end 
end 




macro org_str(organism)
    # Bare Symbol lookup, not Meta.parse -- see the comment in @chem_str (Chemicals.jl) for why.
    sym = Symbol(organism)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        # Find registered lab extension modules which are also loaded by
        # __module__ (required so that precompilation will work).
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, orgstr_check_bool))
end


function orgparse(str; org_context=CHESSCore)
    ex = Meta.parse(str)
    eval(lookup_named_value(org_context, ex, orgstr_check_bool))
end

orgstr_check_bool(::Organism) =true
orgstr_check_bool(::Any) =false










function Base.show(io::IO,str::Organism)
    try
        print(io,symbol(str))
    catch e
        e isa ArgumentError || rethrow()
        print(io,name(str))
    end
end
"""
    genus(x::Organism)
Access the `genus` property of a `Organism` object.
"""
genus(x::Organism) = x.genus
"""
    species(x::Organism)
Access the `species` property of a `Organism` object.
"""
species(x::Organism)= x.species
"""
    strain(x::Organism)
Acces the  `strain` property of a `Organism` object.
"""
strain(x::Organism)= x.strain


"""
    name(x::Organism)
return the full name of a Organism 
"""
name(x::Organism) = "$(genus(x)) $(species(x)) $(strain(x))"