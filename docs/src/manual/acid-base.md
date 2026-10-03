# Acid/Base Chemistry

```@meta
DocTestSetup = :(using CHESS)
```

!!! note
    The `pH` in [Recipes & Solution Chemistry](recipes.md) is a direct estimate from net `H⁺`/`OH⁻`
    concentration. It is correct for strong electrolytes (salts, strong acids and bases) but not
    for weak acids, weak bases, or buffers, which partially dissociate and shift with pH. This page
    describes the equilibrium model for those: [`AcidBaseSystem`](@ref), [`speciation`](@ref), and
    [`adjust_pH`](@ref). `pH(::Stock)` is one function. It uses the strong-electrolyte formula
    when a stock contains no registered weak acid or base, so stocks that do not need the
    equilibrium model are unaffected.

## Conjugate acid/base families

An [`AcidBaseSystem`](@ref) represents a chain of [`Chemical`](@ref) protonation states, from
fully-protonated to fully-deprotonated, linked by a `pKa` per step. Phosphoric acid is a
three-step example:

```jldoctest acid_base
julia> acid_base_system(rgt"potassium_phosphate_mono")
AcidBaseSystem(Chemical[H3PO4, H2PO4⁻, HPO4²⁻, PO4³⁻], [2.148, 7.198, 12.375])
```

Each step's `pKa[i]` links `species[i] ⇌ species[i+1] + H⁺`, and the constructor checks that the
charge drops by exactly 1 at each step. The same shape represents zwitterions. An amino acid's
cation, zwitterion, and anion chain is an `AcidBaseSystem` whose fully protonated state has a net
positive charge instead of being neutral:

```jldoctest acid_base
julia> acid_base_system(rgt"aspartic_acid")
AcidBaseSystem(Chemical[AspartateCation, L-aspartic acid, AspartateAnion, AspartateDianion], [1.99, 3.9, 9.9])
```

## Registering one

[`set_acid_base_system!`](@ref) registers a system for a [`Reagent`](@ref), and
[`acid_base_system`](@ref) looks it up. The systems are held in [`acid_base_systems`](@ref), keyed
by the reagent, like the composition rules. The lookup returns `nothing` for a reagent with no
registered weak acid or base, which is the default. This registry is independent of a reagent's
[`CompositionRule`](@ref) (see [Reagents & Chemicals](reagents-chemicals.md)). A `Reagent` can have
either, both, or neither, because they answer different questions: complete-dissociation mass
bookkeeping and pH-dependent equilibrium speciation.

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

`pH(::Stock)` uses any registered acid/base chemistry automatically. The example compares a strong
acid with a weak one at about the same number of moles (1 mL of acetic acid is roughly 0.0175 mol):

```jldoctest acid_base
julia> acid = 0.0175u"mol" * rgt"HCl" + 100u"mL" * rgt"water";

julia> pH(acid)
0.7569619513137055

julia> vinegar = 1u"mL" * rgt"acetic_acid" + 100u"mL" * rgt"water";

julia> pH(vinegar)
2.7434825265372638
```

`acetic_acid`'s registered [`AcidBaseSystem`](@ref) (`[Acetic Acid, OAc⁻]`, `pKa=4.76`) only
partially dissociates, so `vinegar` is far less acidic than `acid` at a similar loading. The
strong-electrolyte formula in [Recipes & Solution Chemistry](recipes.md) cannot capture this.

## Speciation

[`speciation`](@ref) reports the equilibrium fraction and concentration of every protonation state
at a stock's solved `pH` and returns one [`SpeciationResult`](@ref) per distinct family present.
Mixing `acetic_acid` with its conjugate salt, `sodium_acetate_anhydrous`, makes an acetate buffer.
Both reagents feed the same `OAc⁻` family. 5.725 mL of acetic acid is 0.1 mol, matching the sodium
acetate:

```jldoctest acid_base
julia> buffer = 5.725u"mL" * rgt"acetic_acid" + 0.1u"mol" * rgt"sodium_acetate_anhydrous" + 1u"L" * rgt"water";

julia> speciation(buffer)
1-element Vector{SpeciationResult}:
 SpeciationResult(AcidBaseSystem(Chemical[Acetic Acid, OAc⁻], [4.76]), [0.4998782904645701, 0.5001217095354299], Union{Quantity{T, 𝐍 𝐋⁻³, U}, Level{L, S, Quantity{T, 𝐍 𝐋⁻³, U}} where {L, S}} where {T, U}[0.09940924549192721 mol L⁻¹, 0.0994576534877016 mol L⁻¹])
```

At a 1:1 acid to conjugate base ratio, `speciation` reports an even split. This matches the
Henderson-Hasselbalch result but comes from the same charge-balance solver used for every other
case, not a buffer-specific formula.

A stock with no registered acid/base chemistry, such as `saline` from [Stocks](stocks.md), has
nothing to speciate, and `speciation` returns an empty vector.

## Ionic strength correction

By default, `pH` and `speciation` correct for ionic strength with the Davies equation
([`activity_coefficient`](@ref)), which is valid to roughly 0.5-1 mol/L. Ionic strength shifts weak
acid and base equilibria (the salt effect) in realistic lab solutions. Pass
`ionic_strength_correction=false` for the infinite-dilution result, for example to compare with a
textbook value computed from thermodynamic `pKa`s. Without the correction, the 1:1 buffer's pH is
acetic acid's `pKa` of 4.76. With it, the 0.1 mol/L of dissolved salt lowers the pH by about 0.2:

```jldoctest acid_base
julia> pH(buffer; ionic_strength_correction=false)
4.760128250432899

julia> pH(buffer)
4.570325410721125
```

## Open systems and the water correction

The equilibrium solver takes its inputs as families. An [`AnalyticalSpecies`](@ref) is an
[`AcidBaseSystem`](@ref) together with its total concentration in a stock. Every family that comes
from the recipe of a stock is of this kind. An [`OpenSystemSpecies`](@ref) is a family held at a
fixed concentration of its first species. It models a species in equilibrium with an external
reservoir, such as dissolved atmospheric carbon dioxide, whose concentration is set by the partial
pressure and not by how much of the conjugate base forms. Its total concentration grows with pH.
Both types are subtypes of [`AbstractAnalyticalSpecies`](@ref). The constant [`Kw`](@ref) is the
autoionization constant of water that the solver uses.

`pH` takes `water_correction=true` to add an open-system species to the equilibrium. Most stocks do
not need this. It matters for poorly buffered basic solutions, such as a solution of a pure
conjugate-base salt, which atmospheric carbon dioxide shifts much more than a fixed dose would. The
species is `water_correction_source` if given, and otherwise [`default_water_correction`](@ref),
which a lab module registers with [`set_default_water_correction!`](@ref). `CHESSLabConstants`
registers an atmospheric carbon dioxide correction:

```jldoctest acid_base
julia> acetate = 0.01u"mol" * rgt"sodium_acetate_anhydrous" + 100u"mL" * rgt"water";

julia> pH(acetate)
8.68439649164793

julia> pH(acetate; water_correction=true)
7.746718884707661
```

## Ion parameters

The Davies equation corrects for ionic strength with the charge of an ion alone. For an ion with
published parameters, [`set_ion_parameters!`](@ref) registers the ion-size parameter `å` in Ångströms
and the empirical parameter `b` of the Truesdell-Jones equation. The parameters are held in
[`ion_parameters`](@ref), keyed by the chemical. An ion without parameters uses the Davies equation.
`CHESSLabConstants` registers parameters for common inorganic ions:

```jldoctest acid_base
julia> set_ion_parameters!(MyConjugateBase, 4.5, 0.1)

julia> ion_parameters[MyConjugateBase]
(4.5, 0.1)
```

## Adjusting pH

[`adjust_pH`](@ref) returns a new `Stock`: `s` plus the amount of an `acid` or `base` reagent
needed to reach a target pH. It does not modify `s`, since `Stock`s are immutable (see
[Stocks](stocks.md)):

```jldoctest acid_base
julia> adjusted = adjust_pH(vinegar, 4.0, rgt"acetic_acid", rgt"NaOH");

julia> pH(adjusted)
3.999987245275406

julia> pH(vinegar) # the original stock is untouched
2.7434825265372638
```

`adjust_pH` works whether `s` or the titrant is strong or weak, buffered or not, because every
trial pH is computed by `pH(::Stock)`.
