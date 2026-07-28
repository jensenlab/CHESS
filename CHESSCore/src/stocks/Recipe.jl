
"""
    _reagent_moles(r::Reagent, quantity)

Convert a reagent's tracked `quantity` (mass for a `Solid`, volume for a `Liquid`) to moles, using
`molecular_weight(r)` -- and, for a volume, `density(r)` first (volume × density → mass). Returns
`missing` if a required physical property isn't known.
"""
function _reagent_moles(r::Reagent, quantity::Unitful.Mass)
    mw = molecular_weight(r)
    ismissing(mw) && return missing
    return uconvert(u"mol",quantity/mw)
end
function _reagent_moles(r::Reagent, quantity::Unitful.Volume)
    mw = molecular_weight(r)
    d = density(r)
    (ismissing(mw) || ismissing(d)) && return missing
    return uconvert(u"mol",quantity*d/mw)
end

"""
    struct Recipe

A `Stock`-level analog acting on [`Chemical`](@ref)s rather than [`Reagent`](@ref)s — describes real
quantities of chemical identities ("5g of Na⁺") without committing to which physical `Reagent`
supplies them. See [`recipe`](@ref) for the (one-directional) derivation from a `Stock`.

Stores molar `amounts` natively (not mass) -- this is what dissociation math (`_reagent_moles`,
`composition(::Reagent)`) naturally produces, and what [`total_concentration`](@ref)/[`pH`](@ref)
need, with no dependency on any individual `Chemical`'s own `molecular_weight`. [`mass`](@ref) is
therefore the *derived* accessor, returning `missing` when a chemical is present but its mass can't
be computed (unknown `molecular_weight`) -- as opposed to `0u"g"` when the chemical isn't present at
all.
"""
struct Recipe
    amounts::Dict{Chemical,Unitful.Amount}
end

"""
    recipe(s::Stock)

Derive the [`Recipe`](@ref) (chemical-level composition, in real molar quantities) of `s`: for each
`Reagent` in `s`, convert its tracked quantity to moles (via [`_reagent_moles`](@ref)) and distribute
across its [`composition(::Reagent)`](@ref) rule's `Chemical`s, summing across every reagent present.

There is deliberately no `Stock`-from-`Recipe` conversion — going the other way is underdetermined (a
target chemical profile doesn't uniquely determine which reagent(s) produce it).
"""
function recipe(s::Stock)
    out=Dict{Chemical,Unitful.Amount}()
    for (reagent,quantity) in Iterators.flatten((solids(s),liquids(s)))
        moles=_reagent_moles(reagent,quantity)
        ismissing(moles) && continue
        for (chem,coeff) in composition(reagent).products
            out[chem]=get(out,chem,0u"mol") + coeff*moles
        end
    end
    return Recipe(out)
end

Base.:*(quantity::Unitful.Amount,c::Chemical) = Recipe(Dict(c=>quantity))
Base.:*(quantity::Unitful.Mass,c::Chemical) = Recipe(Dict(c=>convert(u"mol",quantity,c)))

"""
    mass(r::Recipe,c::Chemical)

Return the mass of `c` tracked in `Recipe` `r`: `0u"g"` if `c` isn't present at all, `missing` if `c`
is present but its `molecular_weight` is unknown (so a mass genuinely can't be computed), otherwise
the mass derived from `r`'s stored molar amount.
"""
function mass(r::Recipe,c::Chemical)
    haskey(r.amounts,c) || return 0u"g"
    mw = molecular_weight(c)
    ismissing(mw) && return missing
    return uconvert(u"g",r.amounts[c]*mw)
end

"""
    molar_amount(r::Recipe,c::Chemical)

Return the molar amount of `c` tracked in `Recipe` `r` (`0u"mol"` if absent) -- `Recipe`'s native,
directly-stored unit.
"""
molar_amount(r::Recipe,c::Chemical) = get(r.amounts,c,0u"mol")

"""
    volume(r::Recipe,c::Chemical,density::Unitful.Density)
    volume(r::Recipe,c::Chemical,source::Reagent)

Return the volume of `c` tracked in `Recipe` `r`, using an explicit `density` or a reference
`Reagent` to source it from. `Chemical` deliberately has no density field of its own — density is a
property of physical state, not chemical identity (e.g. ice vs. liquid water), so it stays on
`Reagent`. `missing` if [`mass`](@ref) can't be computed (unknown `molecular_weight`).
"""
volume(r::Recipe,c::Chemical,density::Unitful.Density) = uconvert(u"mL", mass(r,c)/density)
volume(r::Recipe,c::Chemical,source::Reagent) = uconvert(u"mL", mass(r,c)/density(source))

Base.:+(a::Recipe,b::Recipe) = Recipe(mergewith(+,a.amounts,b.amounts))
Base.:*(num::Real,r::Recipe) = Recipe(Dict(k=>v*num for (k,v) in r.amounts))
Base.:*(r::Recipe,num::Real) = num*r

"""
    total_concentration(s::Stock,chem::Chemical)

Return the molar concentration of `chem` in `s`, derived from [`recipe(::Stock)`](@ref) — e.g.
the total potassium ion concentration in a stock containing dissolved KCl.
"""
function total_concentration(s::Stock,chem::Chemical)
    return molar_amount(recipe(s),chem) / volume_estimate(s)
end

"""
    net_hydrogen_ion_concentration(s::Stock)

Return the net molar concentration of hydrogen ions in `s`: [`H⁺`](@ref) minus [`OH⁻`](@ref),
derived from [`recipe(::Stock)`](@ref). This nets the one acid/base ion pair explicitly by
name rather than relying on signed stoichiometry in registered [`CompositionRule`](@ref)s (which
are otherwise always non-negative, real formulas) — see [`pH`](@ref), its only consumer.
"""
function net_hydrogen_ion_concentration(s::Stock)
    r = recipe(s)
    net = molar_amount(r,H⁺) - molar_amount(r,OH⁻)
    return net/volume_estimate(s)
end

"""
    pH(s::Stock; ionic_strength_correction=true)

Estimate the pH of `s`. General case: partitions `s`'s [`recipe`](@ref) into any registered
[`AcidBaseSystem`](@ref) families (see [`acid_base_system`](@ref)) plus every other charged species,
and root-finds the generalized electroneutrality condition (see
[`CHESSCore._charge_balance_residual`](@ref)) -- optionally corrected for ionic strength via the
Davies equation (see [`activity_coefficient`](@ref)), which self-consistently iterates since `γ`
depends on the very speciation it corrects. Set `ionic_strength_correction=false` for the ideal
(infinite-dilution) estimate instead.

Fast path: when no reagent in `s` has a registered `AcidBaseSystem` (the common
complete/strong-electrolyte-only case -- e.g. a stock built only from NaCl, HCl, NaOH, ...), this
computes the exact original closed-form formula directly from
[`net_hydrogen_ion_concentration`](@ref) (`7.0` if net-neutral, `-log10` of the net H⁺ concentration
if acidic, `14 - (-log10(...))` if basic) -- guaranteed bit-identical to CHESSCore's original
strong-electrolyte-only `pH`, not merely expected to converge to the same place via the general
solver. Strong bases should still register their real dissociation formula (e.g. `Na⁺ + OH⁻` for
NaOH) via [`composition(::Reagent)`](@ref) -- mixing an acid and a base nets out through this same
mechanism either way.

If `s` has *no* registered `AcidBaseSystem` and *no* charged species at all (e.g. a `Mixture` of pure
glucose, or an `Empty` stock) -- as opposed to charged species that happen to exactly cancel (e.g.
equimolar HCl + NaOH, or plain NaCl) -- the returned `7.0` isn't a computed result, just the neutral
default with nothing behind it; this case emits a `@warn` so it isn't mistaken for a real answer.

See also [`speciation`](@ref) for a per-family breakdown at the solved pH.
"""
function pH(s::Stock;ionic_strength_correction::Bool=true)
    families,strong_ions = _analytical_species(s)
    if isempty(families)
        isempty(strong_ions) && @warn "pH: no chemicals in this Stock participate in acid/base equilibrium (no registered AcidBaseSystem, no charged species) -- returning the neutral default (7.0), not a computed value"
        return _pH_strong_electrolyte_only(net_hydrogen_ion_concentration(s))
    end
    return pH(families,strong_ions;ionic_strength_correction)
end
