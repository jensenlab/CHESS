# internal function
# mixing just performs the element wise operation on each key (chemical or organism) to compute the
# new Stock component dict. addition and subtraction are very similar, this is a single routine for
# both, differentiated by "operation". Generic over SolidDict/LiquidDict/OrganismDict alike -- note
# these dict-value aliases (Unitful.Mass/Volume, Biomass) are NOT themselves subtypes of
# Unitful.Quantity (they're Union{Quantity,Level} dimension aliases), so the constraint has to name
# the three concrete dict aliases directly rather than bound the value type. See the +/- overloads
# below.
function mix(a::T,b::T;operation=+) where {T<:Union{SolidDict,LiquidDict,OrganismDict}}
    new_dict=T()

    a_c=reagents(a)
    b_c=reagents(b)
    unique_keys=union(a_c,b_c)
    for k in unique_keys
        a_has=k in a_c
        b_has=k in b_c
        # V (e.g. Unitful.Mass) is an unparameterized dimension alias, so zero(V) can't construct a
        # concrete zero quantity on its own -- borrow the unit from whichever operand is actually
        # present at this key (guaranteed to be at least one, since k comes from the union).
        q1 = a_has ? a[k] : zero(b[k])
        q2 = b_has ? b[k] : zero(a[k])
        tot=operation(q1,q2)
        tt=ustrip(tot)
        if tt== 0
            continue
        elseif tt > 0
            new_dict[k] = tot
        else
            throw(MixingError(k,": attempted to add a negative quantity to a Stock"))
        end
    end
    return new_dict
end



# overload the +/- operators for mixing Stocks. 
"""
    +(c1::Stock,c2::Stock)

Overload the additon operator to mix `c1` and `c2`.
"""
function +(c1::Stock,c2::Stock)
    orgs=mix(organisms(c1),organisms(c2);operation=+)
    sols=mix(solids(c1),solids(c2);operation=+)
    liqs=mix(liquids(c1),liquids(c2);operation=+)
    return Stock(orgs,sols,liqs)
end

"""
    -(c1::Stock,c2::Stock)

Overload the subtraction operator to remove `c2` from `c1`.

If the result contains a chemical or organism with a negative quantity, a MixingError will be thrown saying which one is causing the problem -- this includes organism biomass, which (unlike the old presence-only model) can now be fully removed, e.g. `c - c == Empty()` once biomass cancels exactly.
"""
function -(c1::Stock,c2::Stock)
    orgs=mix(organisms(c1),organisms(c2);operation=-)
    sols=mix(solids(c1),solids(c2);operation=-)
    liqs=mix(liquids(c1),liquids(c2);operation=-)
    return Stock(orgs,sols,liqs)
end

