# Recipes & Solution Chemistry

```@meta
DocTestSetup = :(using CHESS)
```

!!! note
    The chemistry model on this page covers what a biology lab needs: dissociation into ions, molar
    concentration, and pH. It is not a complete physical chemistry treatment. `pH` here is a
    direct estimate from net `H⁺`/`OH⁻` concentration. It is correct for strong electrolytes but
    not for weak acids, weak bases, or buffers. [Acid/Base Chemistry](acid-base.md) describes
    activity coefficients, ionic strength, and equilibrium effects. `pH(::Stock)` uses that model
    when a stock contains a reagent with registered weak acid or base chemistry, and the formula
    below otherwise.

A `Stock` is measured in `Reagent`s, the physical things that are weighed out. A
[`Recipe`](@ref) expresses the same stock as molar quantities of `Chemical`s, accounting for
dissociation. [`recipe(s::Stock)`](@ref) derives it, and the derivation is one-directional. The
examples use the saline from [Stocks](stocks.md):

```jldoctest recipes
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> r = recipe(saline)
Recipe(Dict{Chemical, Union{Quantity{T, 𝐍, U}, Level{L, S, Quantity{T, 𝐍, U}} where {L, S}} where {T, U}}(Na⁺ => 0.08555817485063207 mol, Cl⁻ => 0.08555817485063207 mol, water => 0.055509297807382736 mol))
```

`recipe` sums the contribution of every reagent, dissociating or not. `water` does not dissociate,
so it contributes its own identity, the default `composition`.

## Reading a `Recipe`

[`mass`](@ref) and [`molar_amount`](@ref) read a `Recipe`'s quantity of a given `Chemical`:

```jldoctest recipes
julia> mass(r, chem"Na+")
1.966962701545093 g

julia> molar_amount(r, chem"Na+")
0.08555817485063207 mol
```

## `total_concentration`

The molar concentration of a `Chemical` across the whole stock:

```jldoctest recipes
julia> total_concentration(saline, chem"Na+")
0.08555817485063207 mol mL⁻¹
```

## `pH` and `net_hydrogen_ion_concentration`

[`pH`](@ref) is derived from [`net_hydrogen_ion_concentration`](@ref), which nets the canonical
[`H⁺`](@ref) and [`OH⁻`](@ref) `Chemical`s (see [Reagents & Chemicals](reagents-chemicals.md))
against each other. `saline` is a neutral salt, so the result is neutral:

```jldoctest recipes
julia> pH(saline)
7.0
```

CHESS registers hydrochloric acid with the dissociation formula `H⁺ + Cl⁻`:

```jldoctest recipes
julia> acid = 0.1u"g" * rgt"HCl" + 100u"mL" * rgt"water";

julia> net_hydrogen_ion_concentration(acid)
2.7428822206374456e-5 mol mL⁻¹

julia> pH(acid)
1.5617928406001496
```

Because `pH` subtracts `OH⁻` from `H⁺`, a base is registered with its dissociation formula (for
example `Na⁺ + OH⁻` for NaOH) and not a negative `H⁺` count. `CompositionRule` coefficients must be
non-negative, and mixing an acid and a base nets out through the subtraction.
