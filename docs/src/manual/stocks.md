# Stocks

```@meta
DocTestSetup = :(using CHESS)
DocTestFilters = [r"└ @ CHESSCore .*"]
```

A [`Stock`](@ref) is a combination of organisms and chemicals -- what actually lives inside a
`Well`. `Stock` is an abstract type; which concrete subtype you get is determined by what it
contains, not chosen directly: [`Empty`](@ref) (nothing), [`Mixture`](@ref) (solids only),
[`Solution`](@ref) (at least one liquid, any solids), [`Culture`](@ref) (at least one organism, any
solids/liquids -- including zero liquid, since an organism's [`Biomass`](@ref CHESSCore.Biomass) is an absolute
quantity, not one derived from the stock's own volume -- covered in
[Organisms & Cultures](organisms-cultures.md)). The generic
[`Stock(organisms,solids,liquids)`](@ref) constructor automatically picks the right one,
checking in order whether any organisms, then liquids, then solids are present:

| Organisms | Liquids | Solids | Result |
|:---:|:---:|:---:|:---|
| ≥ 1 | any | any | [`Culture`](@ref) |
| 0 | ≥ 1 | any | [`Solution`](@ref) |
| 0 | 0 | ≥ 1 | [`Mixture`](@ref) |
| 0 | 0 | 0 | [`Empty`](@ref) |

```jldoctest stocks
julia> Empty()
Empty Stock
```

## Building a stock from a quantity

The natural way to build one is multiplying a quantity by a [`Reagent`](@ref):

```jldoctest stocks
julia> water_solution = 1u"mL" * rgt"water"
1.0 mL Solution (1 reagent(s))
 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %

julia> salt = 5u"g" * rgt"sodium_chloride"
5.0 g Mixture (1 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   5.0 g        100.0 %
```

## Mixing with `+`

Combining two stocks via `+` always produces whichever subtype the *combined* contents call for --
water plus salt is genuinely saline now, so that's what this one gets called:

```jldoctest stocks
julia> saline = water_solution + salt
1.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %
```

[`quantity(::Stock)`](@ref) reports total *liquid* volume only (`1.0 mL` here, not counting the
dissolved solid's mass). Solids contribute to [`volume_estimate`](@ref) instead, which falls back to
density-based estimation and warns when a solid's density is unknown -- as it is for CHESS's
`sodium_chloride`, which is registered with a `missing` density:

```jldoctest stocks
julia> volume_estimate(salt)
┌ Warning: volume_estimate: density unknown for Sodium Chloride; excluded from the estimate (result is a lower bound)
└ @ CHESSCore ...
0 mL
```

## Scaling

`*`/`/` by a plain number scales every reagent (and any organism's [`Biomass`](@ref CHESSCore.Biomass)) proportionally;
multiplying by a *quantity* instead scales the whole stock to hit that quantity as its new total --
this is how diluting a `Culture` to a target volume also dilutes its organism content:

```jldoctest stocks
julia> double = 2*saline
2.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  10.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  2.0 mL        100.0 %

julia> tenmL = 10u"mL" * saline
10.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  50.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  10.0 mL        100.0 %
```

## The non-negativity constraint

`-` mixes by subtraction, and throws [`MixingError`](@ref) if any reagent would go negative. This
applies identically to organism [`Biomass`](@ref CHESSCore.Biomass) -- an organism's biomass can be reduced or fully
removed via `-`, the same way a chemical amount can (see
[Removing organisms](organisms-cultures.md#Removing-organisms)):

```jldoctest stocks
julia> saline - double
ERROR: Mixing Error with sodium_chloride
: attempted to add a negative quantity to a Stock
```

## `@stock_str` for named recipes

Register one with [`@stock`](@ref) (mirroring [`@location_kind`](@ref)/[`@reagent`](@ref)/
[`@chemical`](@ref)/[`@organism`](@ref)), then recall it with [`@stock_str`](@ref). Unlike a bare
`const` binding, only recipes registered this way are reachable -- an ordinary intermediate `Stock`
(e.g. a concentrated stock solution combined into a larger recipe) never accidentally becomes
discoverable:

```jldoctest stocks
julia> @stock saline_recipe 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride"
1.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %
```

As with location kinds, `saline_recipe` is also bound as a constant where it was registered.
`stock"..."` recalls stocks registered by CHESS or a lab module, such as CHESS's LB broth recipe:

```jldoctest stocks
julia> stock"lb_1000mL"
1000.0 mL Solution (2 reagent(s))
 Solids  Name      Amount  Concentration
─────────────────────────────────────────
 lb      LB Broth  25.0 g    0.02 g mL⁻¹

 Liquids  Name   Amount     Concentration
──────────────────────────────────────────
 water    water  1000.0 mL        100.0 %
```
