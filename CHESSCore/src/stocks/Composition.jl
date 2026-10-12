
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
    struct Composition

A `Stock`-level analog acting on [`Species`](@ref) values rather than [`Reagent`](@ref)s. It describes real
quantities of species ("5g of Na⁺") without committing to which physical `Reagent`
supplies them. See [`composition`](@ref) for the (one-directional) derivation from a `Stock`.

Stores molar `amounts` natively (not mass) -- this is what dissociation math (`_reagent_moles`,
`dissolution(::Reagent)`) naturally produces, and what [`total_concentration`](@ref)/[`pH`](@ref)
need, with no dependency on any individual `Species`'s own `molecular_weight`. [`mass`](@ref) is
therefore the *derived* accessor, returning `missing` when a chemical is present but its mass can't
be computed (unknown `molecular_weight`) -- as opposed to `0u"g"` when the chemical isn't present at
all.
"""
struct Composition
    amounts::Dict{Species,Unitful.Amount}
end

"""
    composition(s::Stock)

Derive the [`Composition`](@ref) (species-level, in real molar quantities) of `s`: for each
`Reagent` in `s`, convert its tracked quantity to moles (via [`_reagent_moles`](@ref)) and distribute
across its [`dissolution(::Reagent)`](@ref) `Dissolution`'s species, summing across every reagent present.

There is deliberately no `Stock`-from-`Composition` conversion — going the other way is underdetermined (a
target chemical profile doesn't uniquely determine which reagent(s) produce it).
"""
function composition(s::Stock)
    out=Dict{Species,Unitful.Amount}()
    for (reagent,quantity) in Iterators.flatten((solids(s),liquids(s)))
        moles=_reagent_moles(reagent,quantity)
        ismissing(moles) && continue
        for (chem,coeff) in dissolution(reagent).products
            out[chem]=get(out,chem,0u"mol") + coeff*moles
        end
    end
    return Composition(out)
end

Base.:*(quantity::Unitful.Amount,c::Species) = Composition(Dict(c=>quantity))
Base.:*(quantity::Unitful.Mass,c::Species) = Composition(Dict(c=>convert(u"mol",quantity,c)))

"""
    mass(r::Composition,c::Species)

Return the mass of `c` tracked in `Composition` `r`: `0u"g"` if `c` isn't present at all, `missing` if `c`
is present but its `molecular_weight` is unknown (so a mass genuinely can't be computed), otherwise
the mass derived from `r`'s stored molar amount.
"""
function mass(r::Composition,c::Species)
    haskey(r.amounts,c) || return 0u"g"
    mw = molecular_weight(c)
    ismissing(mw) && return missing
    return uconvert(u"g",r.amounts[c]*mw)
end

"""
    molar_amount(r::Composition,c::Species)

Return the molar amount of `c` tracked in `Composition` `r` (`0u"mol"` if absent) -- `Composition`'s native,
directly-stored unit.
"""
molar_amount(r::Composition,c::Species) = get(r.amounts,c,0u"mol")

"""
    volume(r::Composition,c::Species,density::Unitful.Density)
    volume(r::Composition,c::Species,source::Reagent)

Return the volume of `c` tracked in `Composition` `r`, using an explicit `density` or a reference
`Reagent` to source it from. `Species` deliberately has no density field of its own — density is a
property of physical state, not of the species (e.g. ice vs. liquid water), so it stays on
`Reagent`. `missing` if [`mass`](@ref) can't be computed (unknown `molecular_weight`).
"""
volume(r::Composition,c::Species,density::Unitful.Density) = uconvert(u"mL", mass(r,c)/density)
volume(r::Composition,c::Species,source::Reagent) = uconvert(u"mL", mass(r,c)/density(source))

Base.:+(a::Composition,b::Composition) = Composition(mergewith(+,a.amounts,b.amounts))
Base.:*(num::Real,r::Composition) = Composition(Dict(k=>v*num for (k,v) in r.amounts))
Base.:*(r::Composition,num::Real) = num*r

"""
    total_concentration(s::Stock,chem::Species)

Return the molar concentration of `chem` in `s`, derived from [`composition(::Stock)`](@ref) — e.g.
the total potassium ion concentration in a stock containing dissolved KCl.
"""
function total_concentration(s::Stock,chem::Species)
    return molar_amount(composition(s),chem) / volume_estimate(s)
end

# Adds `amount` of `spc` to the per-element atom amounts in `counts`. Returns `:counted` when `spc` has
# a formula, `:opaque` when it was declared opaque (it contributes nothing, deliberately), and
# `:unknown` when it has no formula registered (it contributes nothing, but that is a gap).
function _add_atoms!(counts::Dict{Symbol,Unitful.Amount},spc::Species,amount)
    f = formula(spc)
    f isa OpaqueFormula && return :opaque
    ismissing(f) && return :unknown
    for (element,n) in f
        counts[element] = get(counts,element,0u"mol") + n*amount
    end
    return :counted
end

function _warn_incomplete_atoms(names)
    n = length(names)
    shown = join(("\"$nm\"" for nm in first(sort!(collect(names)),5)),", ")
    more = n > 5 ? ", and $(n-5) more" : ""
    @warn "atoms: $n $(n==1 ? "reagent has" : "reagents have") no registered formula (or an amount that cannot be computed), so the atom amounts are a lower bound: $shown$more. Register a formula for each, or declare a reagent `opaque` if its atomic content is intentionally not described."
end

"""
    atoms(s::Stock) -> Dict{Symbol,Unitful.Amount}
    atoms(s::Stock,element::Symbol) -> Unitful.Amount
    atoms(c::Composition) -> Dict{Symbol,Unitful.Amount}
    atoms(c::Composition,element::Symbol) -> Unitful.Amount

Return the amount (in moles) of each element's atoms in a stock or [`Composition`](@ref), found by
summing every species' amount times its atom count from its elemental formula. With an `element`
symbol such as `:Fe`, return just that element's amount (`0u"mol"` if it is absent). Multiply by
`Unitful.Na` to get a number of atoms.

Only reagents contribute; organisms in a culture are not counted. A reagent contributes nothing, and
the result is a lower bound, when it has no registered formula or when its amount cannot be computed
(for example a liquid without a density). In that case `atoms` emits one warning naming the reagents.
A reagent declared `opaque` contributes nothing without a warning.

```julia
julia> s = 18.015u"mL" * water + 0.1u"mol" * NaCl; # water defined as "H2O", NaCl as Na⁺ + Cl⁻

julia> atoms(s,:H)
2.0 mol

julia> atoms(s,:Cl)
0.1 mol
```
"""
function atoms(s::Stock)
    counts = Dict{Symbol,Unitful.Amount}()
    incomplete = String[]
    for (reagent,quantity) in Iterators.flatten((solids(s),liquids(s)))
        species = collect(keys(dissolution(reagent).products))
        all(is_opaque,species) && continue
        moles = _reagent_moles(reagent,quantity)
        if ismissing(moles)
            push!(incomplete,name(reagent))
            continue
        end
        results = [_add_atoms!(counts,spc,coeff*moles) for (spc,coeff) in dissolution(reagent).products]
        :unknown in results && push!(incomplete,name(reagent))
    end
    isempty(incomplete) || _warn_incomplete_atoms(incomplete)
    return counts
end

function atoms(c::Composition)
    counts = Dict{Symbol,Unitful.Amount}()
    incomplete = String[]
    for (spc,amount) in c.amounts
        _add_atoms!(counts,spc,amount) === :unknown && push!(incomplete,name(spc))
    end
    isempty(incomplete) || _warn_incomplete_atoms(incomplete)
    return counts
end

function atoms(x::Union{Stock,Composition},element::Symbol)
    element in _element_symbols || throw(ArgumentError("\"$element\" is not an element symbol"))
    return get(atoms(x),element,0u"mol")
end

"""
    net_hydrogen_ion_concentration(s::Stock)

Return the net molar concentration of hydrogen ions in `s`: [`H⁺`](@ref) minus [`OH⁻`](@ref),
derived from [`composition(::Stock)`](@ref). This nets the one acid/base ion pair explicitly by
name rather than relying on signed stoichiometry in registered [`Dissolution`](@ref)s (which
are otherwise always non-negative, real formulas) — see [`pH`](@ref), its only consumer.
"""
function net_hydrogen_ion_concentration(s::Stock)
    r = composition(s)
    net = molar_amount(r,H⁺) - molar_amount(r,OH⁻)
    return net/volume_estimate(s)
end

"""
    pH(s::Stock; ionic_strength_correction=true, water_correction=false, water_correction_source=nothing)

Estimate the pH of `s`. General case: partitions `s`'s [`composition`](@ref) into any registered
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
solver. Strong bases should still register their real dissolution (e.g. `Na⁺ + OH⁻` for
NaOH) via [`set_dissolution!`](@ref) -- mixing an acid and a base nets out through this same
mechanism either way.

If `s` has *no* registered `AcidBaseSystem` and *no* charged species at all (e.g. a `Mixture` of pure
glucose, or an `Empty` stock) -- as opposed to charged species that happen to exactly cancel (e.g.
equimolar HCl + NaOH, or plain NaCl) -- the returned `7.0` isn't a computed result, just the neutral
default with nothing behind it; this case emits a `@warn` so it isn't mistaken for a real answer.

Set `water_correction=true` to add a background open-system correction (e.g. dissolved atmospheric
CO2) to `s`'s equilibrium before estimating pH -- most stocks don't need this level of detail and
should leave it `false` (the default). Modeled as an [`OpenSystemSpecies`](@ref) (a fixed *free-species*
concentration, not a fixed total dose) so its contribution grows correctly with pH -- important for
poorly-buffered basic solutions (e.g. a pure conjugate-base salt), which real atmospheric CO2 shifts
much more than a fixed dose would. With no `water_correction_source` given, this uses
[`default_water_correction`](@ref) (registered by a lab module, e.g. CHESSLabConstants's atmospheric-CO2
correction, via [`set_default_water_correction!`](@ref)); pass `water_correction_source` explicitly to
use a different [`OpenSystemSpecies`](@ref) instead.

See also [`speciation`](@ref) for a per-family breakdown at the solved pH.
"""
function pH(s::Stock;ionic_strength_correction::Bool=true,
            water_correction::Bool=false,water_correction_source::Union{Nothing,OpenSystemSpecies}=nothing)
    families,strong_ions = _analytical_species(s)
    families = Vector{AbstractAnalyticalSpecies}(families)
    if water_correction
        spec = water_correction_source === nothing ? default_water_correction[] : water_correction_source
        spec === nothing && throw(ArgumentError(
            "water_correction=true requires either water_correction_source, or a lab module registering a default via set_default_water_correction! (e.g. CHESSLabConstants)"))
        push!(families,spec)
    end
    if isempty(families)
        isempty(strong_ions) && @warn "pH: no chemicals in this Stock participate in acid/base equilibrium (no registered AcidBaseSystem, no charged species) -- returning the neutral default (7.0), not a computed value"
        return _pH_strong_electrolyte_only(net_hydrogen_ion_concentration(s))
    end
    return pH(families,strong_ions;ionic_strength_correction)
end
