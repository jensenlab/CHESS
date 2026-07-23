# internal function
# mixing just performs the element wise operation on each chemical to compute the new Stock
# addition and subtraction are very similar, this is a single routine for both addition and subtraction but we replace the  differences with "operation". See the +/- overloads below. 
function mix(a::SolidDict,b::SolidDict;operation=+)
    new_solids=SolidDict() 

    a_sc=reagents(a)
    b_sc=reagents(b)
    unique_chemicals=union(a_sc,b_sc)
    for chem in unique_chemicals
        q1=0u"g"
        q2=0u"g"
        if chem in a_sc
            q1=a[chem]
        end
        if chem in b_sc
            q2=b[chem] 
        end 
        tot=operation(q1,q2)
        tt=ustrip(tot)
        if tt== 0 
            continue
        elseif tt > 0 
            new_solids[chem] = tot 
        else
            throw(MixingError(chem,": attempted to add a negative quantity to a Stock"))
        end
    end
    return new_solids
end 


function mix(a::LiquidDict,b::LiquidDict;operation=+)
    new_liquids=LiquidDict()
    a_lc=reagents(a)
    b_lc=reagents(b)
    unique_chemicals=union(a_lc,b_lc)
    for chem in unique_chemicals
        q1=0u"mL"
        q2=0u"mL"
        if chem in a_lc
            q1=a[chem]
        end
        if chem in b_lc
            q2=b[chem]
        end 
        tot=operation(q1,q2)
        tt=ustrip(tot)
        if tt== 0 
            continue
        elseif tt > 0 
            new_liquids[chem] = tot 
        else
            throw(MixingError(chem,": attempted to add a negative quantity to a Stock"))
        end
    end
    return new_liquids
end 

# internal addition operator for the Organism math. Organisms can be added, but not removed independently. 
+(a::Set{Organism},b::Set{Organism})=union(a,b)
-(a::Set{Organism},b::Set{Organism})=a 





# overload the +/- operators for mixing Stocks. 
"""
    +(c1::Stock,c2::Stock)

Overload the additon operator to mix `c1` and `c2`.
"""
function +(c1::Stock,c2::Stock)
    orgs=organisms(c1)+organisms(c2)
    sols=mix(solids(c1),solids(c2);operation=+)
    liqs=mix(liquids(c1),liquids(c2);operation=+)
    return Stock(orgs,sols,liqs)
end 

"""
    -(c1::Stock,c2::Stock)

Overload the subtraction operator to remove `c2` from `c1`. 

If the result contains a chemical with a negative quantity, a MixingError will be thrown saying which chemical is causing the problem.
"""
function -(c1::Stock,c2::Stock)
    orgs=organisms(c1)-organisms(c2)
    sols=mix(solids(c1),solids(c2);operation=-)
    liqs=mix(liquids(c1),liquids(c2);operation=-)
    return Stock(orgs,sols,liqs)
end 
 

+(st::Stock,b::Organism)=st + Stock(Set{Organism}([b]),SolidDict(),LiquidDict())
+(b::Organism,st::Stock) = +(st,b) # associative property 
