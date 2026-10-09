# Composition & Solution Chemistry

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
[`Composition`](@ref) expresses the same stock as molar quantities of `Species` values, accounting for
dissociation. [`composition(s::Stock)`](@ref) derives it, and the derivation is one-directional. The
examples use the saline from [Stocks](stocks.md):

```jldoctest composition
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> r = composition(saline);

julia> sort(string.(keys(r.amounts)))
3-element Vector{String}:
 "Cl⁻"
 "Na⁺"
 "water"
```

`composition` sums the contribution of every reagent, dissociating or not. `water` does not dissociate,
so it contributes its own identity, the default dissolution.

## Reading a `Composition`

[`mass`](@ref) and [`molar_amount`](@ref) read a `Composition`'s quantity of a given `Species`:

```jldoctest composition
julia> mass(r, spc"Na+")
1.9669627005070887 g

julia> molar_amount(r, spc"Na+")
0.08555817487991287 mol
```

## Atoms

[`atoms`](@ref) gives the amount of each element in a stock, from the elemental formulas of the
species in its composition. The reagents here are defined with a formula and with a dissolution
(see [Reagents & Chemicals](reagents-chemicals.md)):

```jldoctest composition
julia> @reagent formulawater "water with a formula" Liquid "H2O" 1.0u"g/mL" missing
water with a formula

julia> @reagent formulasalt "salt with a formula" Solid (spc"Na+" + spc"Cl-") 2.16u"g/mL" missing
salt with a formula

julia> s = 18.015u"mL" * formulawater + 0.1u"mol" * formulasalt;

julia> atoms(s, :H)
2.0 mol

julia> atoms(s, :Cl)
0.1 mol

julia> atoms(s, :Fe)
0 mol
```

Multiplying an amount by `Unitful.Na` gives a number of atoms. Only reagents contribute, and a
reagent contributes only if it has a registered formula. When a stock holds a reagent whose formula
is not registered, or whose amount cannot be computed, `atoms` returns what it can count and warns
that the result is a lower bound. A reagent declared `opaque` contributes nothing and does not
warn.

## `total_concentration`

The molar concentration of a `Species` across the whole stock:

```jldoctest composition
julia> total_concentration(saline, spc"Na+")
0.08555817487991287 mol mL⁻¹
```

## `pH` and `net_hydrogen_ion_concentration`

[`pH`](@ref) is derived from [`net_hydrogen_ion_concentration`](@ref), which nets the canonical
[`H⁺`](@ref) and [`OH⁻`](@ref) `Species` values (see [Reagents & Chemicals](reagents-chemicals.md))
against each other. `saline` is a neutral salt, so the result is neutral:

```jldoctest composition
julia> pH(saline)
7.0
```

CHESS registers hydrochloric acid with the dissociation formula `H⁺ + Cl⁻`:

```jldoctest composition
julia> acid = 0.1u"g" * rgt"HCl" + 100u"mL" * rgt"water";

julia> net_hydrogen_ion_concentration(acid)
2.7428822206374456e-5 mol mL⁻¹

julia> pH(acid)
1.5617928406001496
```

Because `pH` subtracts `OH⁻` from `H⁺`, a base is registered with its dissociation formula (for
example `Na⁺ + OH⁻` for NaOH) and not a negative `H⁺` count. `Dissolution` coefficients must be
non-negative, and mixing an acid and a base nets out through the subtraction.
