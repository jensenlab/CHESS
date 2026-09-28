# Acid/Base Chemistry

```@meta
DocTestSetup = :(using CHESS)
```

!!! note
    [Recipes & Solution Chemistry](recipes.md)'s `pH` is a direct estimate from net `H⁺`/`OH⁻`
    concentration -- correct for strong electrolytes (salts, strong acids/bases), but not for weak
    acids, weak bases, or buffers, which only partially dissociate and shift with pH. This chapter
    covers the equilibrium model that handles those: [`AcidBaseSystem`](@ref), [`speciation`](@ref),
    and [`adjust_pH`](@ref). `pH(::Stock)` itself is one function either way -- it automatically
    falls back to the exact strong-electrolyte formula from the previous chapter whenever a stock
    contains no registered weak acid/base chemistry, so nothing here changes behavior for stocks
    that don't need it.

## `AcidBaseSystem`: conjugate families

An [`AcidBaseSystem`](@ref) represents a chain of [`Chemical`](@ref) protonation states, from
fully-protonated to fully-deprotonated, linked by a `pKa` per step. Phosphoric acid is a
three-step example:

```jldoctest acid_base
julia> acid_base_system(rgt"potassium_phosphate_mono")
AcidBaseSystem(Chemical[H3PO4, H2PO4⁻, HPO4²⁻, PO4³⁻], [2.148, 7.198, 12.375])
```

Each step's `pKa[i]` links `species[i] ⇌ species[i+1] + H⁺`; the constructor checks that charge
drops by exactly 1 at each step. The same linear shape represents zwitterions too -- an amino
acid's cation/zwitterion/anion chain is just an `AcidBaseSystem` whose fully-protonated reference
state happens to carry a net positive charge rather than being neutral:

```jldoctest acid_base
julia> acid_base_system(rgt"aspartic_acid")
AcidBaseSystem(Chemical[AspartateCation, L-aspartic acid, AspartateAnion, AspartateDianion], [1.99, 3.9, 9.9])
```

## Registering one

[`set_acid_base_system!`](@ref) registers a system against a [`Reagent`](@ref); [`acid_base_system`](@ref)
looks it up again, returning `nothing` for a reagent with no registered weak acid/base chemistry
(the default -- most reagents are inert here). This registry is independent of a reagent's
[`CompositionRule`](@ref) (covered in [Reagents & Chemicals](reagents-chemicals.md)): a `Reagent`
can have either, both, or neither, since they answer different questions -- complete-dissociation
mass bookkeeping vs. pH-dependent equilibrium speciation.

```jldoctest acid_base
julia> @reagent my_weak_acid "my weak acid" Solid 100.0u"g/mol" missing missing
my weak acid

julia> @chemical MyWeakAcid "my weak acid" 0 100.0u"g/mol"
MyWeakAcid

julia> @chemical MyConjugateBase "my conjugate base" -1 99.0u"g/mol"
MyConjugateBase

julia> set_acid_base_system!(my_weak_acid, AcidBaseSystem([MyWeakAcid,MyConjugateBase],[5.0]))

julia> acid_base_system(my_weak_acid)
AcidBaseSystem(Chemical[my weak acid, my conjugate base], [5.0])
```

## `pH` with weak acid/base families

`pH(::Stock)` needs no separate entry point for this -- the same function used in the previous
chapter picks up any registered acid/base chemistry automatically. Contrast a strong acid with a
weak one with about the same number of moles (1 mL of acetic acid is roughly 0.0175 mol):

```jldoctest acid_base
julia> acid = 0.0175u"mol" * rgt"HCl" + 100u"mL" * rgt"water";

julia> pH(acid)
0.7569619513137055

julia> vinegar = 1u"mL" * rgt"acetic_acid" + 100u"mL" * rgt"water";

julia> pH(vinegar)
2.7434825265372638
```

`acetic_acid`'s registered [`AcidBaseSystem`](@ref) (`[Acetic Acid, OAc⁻]`, `pKa=4.76`) only
partially dissociates, so `vinegar` comes out far less acidic than `acid` despite similar
stoichiometric loading -- exactly the effect the strong-electrolyte-only formula from
[Recipes & Solution Chemistry](recipes.md) can't capture.

## `speciation`: per-species breakdown

[`speciation`](@ref) reports the equilibrium fraction and concentration of every protonation state
at a stock's solved `pH`, returning one [`SpeciationResult`](@ref) per distinct family present.
Mixing `acetic_acid` with its own conjugate salt, `sodium_acetate_anhydrous`, makes a classic
acetate buffer -- both reagents feed the same `OAc⁻`-anchored family. 5.725 mL of acetic acid is
0.1 mol, matching the sodium acetate:

```jldoctest acid_base
julia> buffer = 5.725u"mL" * rgt"acetic_acid" + 0.1u"mol" * rgt"sodium_acetate_anhydrous" + 1u"L" * rgt"water";

julia> speciation(buffer)
1-element Vector{SpeciationResult}:
 SpeciationResult(AcidBaseSystem(Chemical[Acetic Acid, OAc⁻], [4.76]), [0.4998782904645701, 0.5001217095354299], Union{Quantity{T, 𝐍 𝐋⁻³, U}, Level{L, S, Quantity{T, 𝐍 𝐋⁻³, U}} where {L, S}} where {T, U}[0.09940924549192721 mol L⁻¹, 0.0994576534877016 mol L⁻¹])
```

At a 1:1 acid:conjugate-base ratio, `speciation` reports an even 50/50 split -- the textbook
Henderson-Hasselbalch result, but derived from the same general charge-balance solver used for
every other case in this chapter, not a buffer-specific formula.

Stocks with no registered acid/base chemistry (e.g. `saline` from [Stocks](stocks.md)) have
nothing to speciate: `speciation` returns an empty vector for those.

## Ionic strength correction

By default, `pH` and `speciation` correct for ionic strength using the Davies equation
([`activity_coefficient`](@ref)), valid to roughly 0.5-1 mol/L -- realistic lab solutions are
rarely at infinite dilution, and ionic strength measurably shifts weak acid/base equilibria (the
"salt effect"). Pass `ionic_strength_correction=false` to get the idealized, infinite-dilution
result instead, e.g. to compare against a textbook value computed from thermodynamic `pKa`s alone.
Without the correction, the 1:1 buffer's pH lands on acetic acid's `pKa` of 4.76; with it, the
0.1 mol/L of dissolved salt lowers the pH by about 0.2:

```jldoctest acid_base
julia> pH(buffer; ionic_strength_correction=false)
4.760128250432899

julia> pH(buffer)
4.570325410721125
```

## `adjust_pH`: titrating to a target

[`adjust_pH`](@ref) returns a *new* `Stock` -- `s` plus whatever amount of an `acid` or `base`
reagent is needed to reach a target pH -- without modifying `s` itself, consistent with `Stock`'s
immutable design elsewhere (`+`/`*` always build new values; see [Stocks](stocks.md)):

```jldoctest acid_base
julia> adjusted = adjust_pH(vinegar, 4.0, rgt"acetic_acid", rgt"NaOH");

julia> pH(adjusted)
3.999987245275406

julia> pH(vinegar) # the original stock is untouched
2.7434825265372638
```

It works the same way regardless of whether `s` or the titrant is strong or weak, buffered or
not -- every trial pH along the way is computed by calling `pH(::Stock)` itself, so `adjust_pH`
needs no separate solver logic of its own.
