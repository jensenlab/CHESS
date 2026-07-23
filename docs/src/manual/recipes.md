# Recipes & Solution Chemistry

!!! note
    This chapter's chemistry model is intentionally simple -- pitched at what a biology lab needs
    (dissociation into ions, molar concentration, pH), not a complete physical chemistry treatment.
    Activity coefficients, ionic strength, and buffer/equilibrium effects are out of scope; `pH`
    here is a direct estimate from net `H⁺`/`OH⁻` concentration, not a full equilibrium
    calculation.

A `Stock` is measured in `Reagent`s -- physical things you weigh out. [`Recipe`](@ref) reduces that
to real molar quantities of `Chemical`s instead, accounting for dissociation, derived
one-directionally via [`recipe(s::Stock)`](@ref):

```julia-repl
julia> r = recipe(saline)
Recipe(Dict(Cl⁻ => 0.0856 mol, Na⁺ => 0.0856 mol, water => 0.0555 mol))
```

`water` itself is in there too -- `recipe` sums every reagent's contribution, dissociating or not.
`water` doesn't dissociate, so its only contribution is its own identity, per `composition`'s
default from the previous chapters.

## Reading a `Recipe`

[`mass`](@ref) and [`molar_amount`](@ref) read a `Recipe`'s quantity of a given `Chemical`:

```julia-repl
julia> mass(r, Na⁺)
1.97 g

julia> molar_amount(r, Na⁺)
0.0856 mol
```

## `total_concentration`

The molar concentration of a `Chemical` across the whole stock:

```julia-repl
julia> total_concentration(saline, Na⁺)
0.0856 mol mL⁻¹
```

## `pH` and `net_hydrogen_ion_concentration`

[`pH`](@ref) is derived from [`net_hydrogen_ion_concentration`](@ref), which nets the canonical
[`H⁺`](@ref)/[`OH⁻`](@ref) `Chemical`s -- introduced in [Reagents & Chemicals](reagents-chemicals.md)
-- against each other. `saline` is a neutral salt, so it comes out flat:

```julia-repl
julia> pH(saline)
7.0
```

A new reagent, registered here specifically to show this meaningfully:

```julia
@reagent_formula HCl "hydrochloric acid" Liquid (H⁺+Cl⁻) 1.18u"g/mL" missing
```

```julia-repl
julia> acid = 1u"mL"*HCl + 100u"mL"*water

julia> net_hydrogen_ion_concentration(acid)
0.00032 mol mL⁻¹

julia> pH(acid)
0.49
```

This explicit `H⁺`-minus-`OH⁻` subtraction is exactly why a base registers its real dissociation
formula (e.g. `Na⁺ + OH⁻` for NaOH) rather than a negative `H⁺` count -- `CompositionRule`
coefficients must stay non-negative, and mixing an acid and a base nets out through this
subtraction instead.
