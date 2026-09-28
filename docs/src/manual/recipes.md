# Recipes & Solution Chemistry

```@meta
DocTestSetup = :(using CHESS)
```

!!! note
    This chapter's chemistry model is intentionally simple -- pitched at what a biology lab needs
    (dissociation into ions, molar concentration, pH), not a complete physical chemistry treatment.
    `pH` here is a direct estimate from net `H⁺`/`OH⁻` concentration, not a full equilibrium
    calculation -- correct for strong electrolytes, but not for weak acids/bases or buffers. See
    [Acid/Base Chemistry](acid-base.md) for activity coefficients, ionic strength, and
    buffer/equilibrium effects; `pH(::Stock)` picks up that model automatically whenever a stock
    contains a reagent with registered weak acid/base chemistry, falling back to the formula below
    otherwise.

A `Stock` is measured in `Reagent`s -- physical things you weigh out. [`Recipe`](@ref) reduces that
to real molar quantities of `Chemical`s instead, accounting for dissociation, derived
one-directionally via [`recipe(s::Stock)`](@ref). Using the saline from [Stocks](stocks.md):

```jldoctest recipes
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> r = recipe(saline)
Recipe(Dict{Chemical, Union{Quantity{T, 𝐍, U}, Level{L, S, Quantity{T, 𝐍, U}} where {L, S}} where {T, U}}(Na⁺ => 0.08555817485063207 mol, Cl⁻ => 0.08555817485063207 mol, water => 0.055509297807382736 mol))
```

`water` itself is in there too -- `recipe` sums every reagent's contribution, dissociating or not.
`water` doesn't dissociate, so its only contribution is its own identity, per `composition`'s
default from the previous chapters.

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
[`H⁺`](@ref)/[`OH⁻`](@ref) `Chemical`s -- introduced in [Reagents & Chemicals](reagents-chemicals.md)
-- against each other. `saline` is a neutral salt, so it comes out flat:

```jldoctest recipes
julia> pH(saline)
7.0
```

CHESS registers hydrochloric acid with its dissociation formula, `H⁺ + Cl⁻`, which makes a more
interesting example:

```jldoctest recipes
julia> acid = 0.1u"g" * rgt"HCl" + 100u"mL" * rgt"water";

julia> net_hydrogen_ion_concentration(acid)
2.7428822206374456e-5 mol mL⁻¹

julia> pH(acid)
1.5617928406001496
```

This explicit `H⁺`-minus-`OH⁻` subtraction is exactly why a base registers its real dissociation
formula (e.g. `Na⁺ + OH⁻` for NaOH) rather than a negative `H⁺` count -- `CompositionRule`
coefficients must stay non-negative, and mixing an acid and a base nets out through this
subtraction instead.
