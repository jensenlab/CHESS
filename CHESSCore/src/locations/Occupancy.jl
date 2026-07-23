
parent_cost(x::Location)=kind(x).default_parent_cost
child_cost(x::Location)=kind(x).default_child_cost

"""
    const occupancy_rules

Data table of explicit occupancy-cost rules, keyed by `(parent_kind_name, child_kind_name)`. Prefer
[`set_occupancy_cost!`](@ref) over mutating this directly.
"""
const occupancy_rules = Dict{Tuple{Symbol,Symbol},Rational}()

"""
    set_occupancy_cost!(parent_kind::Symbol,child_kind::Symbol,cost::Rational)

Register an occupancy-cost rule for a `(parent_kind,child_kind)` pair (or category pair — any of
either kind's [`LocationKind`](@ref) `categories`). An exact kind-to-kind rule always takes
precedence over a category-based one; if more than one category-based rule matches with no exact
rule to break the tie, [`occupancy_cost`](@ref) throws [`AmbiguousOccupancyRuleError`](@ref).
"""
function set_occupancy_cost!(parent_kind::Symbol,child_kind::Symbol,cost::Rational)
    occupancy_rules[(parent_kind,child_kind)]=cost
    return nothing
end

function matching_category_rules(pk::LocationKind,ck::LocationKind)
    pkeys=vcat([pk.name],pk.categories)
    ckeys=vcat([ck.name],ck.categories)
    matches=Rational[]
    for a in pkeys, b in ckeys
        (a,b)==(pk.name,ck.name) && continue
        if haskey(occupancy_rules,(a,b))
            push!(matches,occupancy_rules[(a,b)])
        end
    end
    return unique(matches)
end

"""
    occupancy_cost(parent::Location,child::Location)

Returns a Rational representing the fractional occupancy of `child` in `parent`.

Resolution precedence: an exact `(parent kind, child kind)` rule (see [`set_occupancy_cost!`](@ref))
wins outright; otherwise, a single matching category-based rule applies; if more than one
category-based rule matches with no exact rule to disambiguate, throws
[`AmbiguousOccupancyRuleError`](@ref); otherwise falls back to
`max(parent_cost(parent),child_cost(child))`.
"""
function occupancy_cost(parent::Location,child::Location)
    pk=kind(parent)
    ck=kind(child)
    haskey(occupancy_rules,(pk.name,ck.name)) && return occupancy_rules[(pk.name,ck.name)]
    matches=matching_category_rules(pk,ck)
    length(matches)>1 && throw(AmbiguousOccupancyRuleError(pk,ck,matches))
    length(matches)==1 && return matches[1]
    return max(parent_cost(parent),child_cost(child))
end

"""
    occupancy(x::Location)

return the fractional occupancy of location x.

Occupancies can range from 0 (empty) to 1 (fully occupied).

The occupancy is calculated by summing the `occupancy_cost` of each child in the location.

"""
function occupancy(x::Location)
    occ=0//1

    for child in children(x)
            occ += occupancy_cost(x,child)
    end
    return occ
end
