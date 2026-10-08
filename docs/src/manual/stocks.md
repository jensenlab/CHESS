# Stocks

```@meta
DocTestSetup = :(using CHESS)
DocTestFilters = [r"└ @ CHESSCore .*"]
```

A [`Stock`](@ref) is a combination of organisms and chemicals. It is what a `Well` holds. `Stock`
is an abstract type, and the concrete subtype depends on the contents:

- [`Empty`](@ref): nothing.
- [`Mixture`](@ref): solids only.
- [`Solution`](@ref): at least one liquid, and any solids.
- [`Culture`](@ref): at least one organism, and any solids and liquids. A culture can have no
  liquid, because an organism's [`Biomass`](@ref CHESSCore.Biomass) is an absolute quantity, not
  one derived from the stock's volume. See [Organisms & Cultures](organisms-cultures.md).

The generic [`Stock(organisms,solids,liquids)`](@ref) constructor picks the subtype by checking for
organisms, then liquids, then solids:

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

Multiplying a quantity by a [`Reagent`](@ref) builds a stock:

```jldoctest stocks
julia> water_solution = 1u"mL" * rgt"water"
1.00 mL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %

julia> salt = 5u"g" * rgt"sodium_chloride"
5.00 g Mixture (1 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  5.00 g          100 %
```

## Mixing stocks

Adding two stocks produces the subtype that the combined contents call for. Water plus
salt is a `Solution`:

```jldoctest stocks
julia> saline = water_solution + salt
1.00 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  5.00 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %
```

[`quantity(::Stock)`](@ref) reports the total liquid volume only (1.00 mL here, excluding the
dissolved solid). Solids contribute to [`volume_estimate`](@ref), which estimates from density and
warns when a solid's density is unknown. CHESS's `sodium_chloride` is registered without a
density:

```jldoctest stocks
julia> volume_estimate(salt)
┌ Warning: volume_estimate: density unknown for Sodium Chloride; excluded from the estimate (result is a lower bound)
└ @ CHESSCore ...
0 mL
```

## Scaling

Multiplying or dividing a stock by a plain number scales every reagent and every organism's
[`Biomass`](@ref CHESSCore.Biomass) proportionally. Multiplying by a quantity scales the whole stock
so that the quantity is its new total. This is how diluting a `Culture` to a target volume also
dilutes its organisms:

```jldoctest stocks
julia> double = 2*saline
2.00 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  10.0 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  2.00 mL          100 %

julia> tenmL = 10u"mL" * saline
10.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  50.0 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  10.0 mL          100 %
```

## The non-negativity constraint

Subtracting one stock from another throws [`MixingError`](@ref) if any reagent would go negative. The
same applies to organism [`Biomass`](@ref CHESSCore.Biomass), which subtraction can reduce or remove like a
chemical amount (see [Removing organisms](organisms-cultures.md#Removing-organisms)):

```jldoctest stocks
julia> saline - double
ERROR: Mixing Error with sodium_chloride
: attempted to add a negative quantity to a Stock
```

## Components

Reagents and organisms are the two kinds of component that a stock tracks. Both are
[`StockComponent`](@ref)s. [`all_reagents`](@ref) lists the solid and liquid reagents of a stock or
of a vector of stocks without duplicates, and [`all_components`](@ref) also lists the organisms.
[`set_component`](@ref) returns a copy of a stock with one component at an exact quantity, which is
a mass for a solid, a volume for a liquid, and a [`Biomass`](@ref CHESSCore.Biomass) for an organism.
A zero quantity removes the component:

```jldoctest stocks
julia> all_reagents(saline)
2-element Vector{Reagent}:
 sodium_chloride
 water

julia> all_components(saline + 1u"OD*mL" * org"SMU_UA159")
3-element Vector{StockComponent}:
 sodium_chloride
 water
 SMU_UA159

julia> set_component(saline, rgt"sodium_chloride", 2u"g")
1.00 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  2.00 g    2.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %

julia> set_component(saline, rgt"sodium_chloride", 0u"g")
1.00 mL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %
```

[`reagent_df`](@ref) tabulates a vector of stocks with one row for each stock and one column for each
reagent. The cells hold the concentration of the reagent, or its quantity with `measure=quantity`.
[`component_df`](@ref) also has columns for organisms. The column names come from
[`component_to_string`](@ref). It uses the registered name of a component when it finds the component
in the `reagent_context` that is passed as a keyword, and the display name otherwise:

```jldoctest stocks
julia> reagent_df([saline, tenmL])
2×2 DataFrame
 Row │ Sodium Chloride  water
     │ Any              Any
─────┼──────────────────────────
   1 │ 5.0 g mL⁻¹       100.0 %
   2 │ 5.0 g mL⁻¹       100.0 %

julia> reagent_df([saline, tenmL]; measure=quantity)
2×2 DataFrame
 Row │ Sodium Chloride  water
     │ Any              Any
─────┼─────────────────────────────
   1 │ 5 g              1000 μL
   2 │ 50.0 g           10000.0 μL
```

[`reagent_display`](@ref) returns the solids, liquids, and organisms of a stock as dictionaries from
name to amount and concentration, which are the values that the printed table of a stock shows:

```jldoctest stocks
julia> solids, liquids, organisms = reagent_display(saline);

julia> collect(keys(solids))
1-element Vector{String}:
 "Sodium Chloride"

julia> solids["Sodium Chloride"]["Amount"]
(5.0, "g")
```

## Named stocks

[`@stock`](@ref) registers a named stock, like [`@location_kind`](@ref), [`@reagent`](@ref),
[`@chemical`](@ref), and [`@organism`](@ref). [`@stock_str`](@ref) recalls it. Only stocks
registered this way can be recalled, so an intermediate stock, such as a concentrated solution
combined into a larger recipe, is never recalled by accident:

```jldoctest stocks
julia> @stock saline_recipe 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride"
1.00 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  5.00 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %
```

`saline_recipe` is also bound as a constant where it was registered. `stock"..."` recalls stocks
registered by CHESS or a lab module, such as CHESS's LB broth recipe:

```jldoctest stocks
julia> stock"lb_1000mL"
1.00 L Solution (2 reagent(s))
 Solids  Name      Amount  Concentration
─────────────────────────────────────────
 lb      LB Broth  25.0 g   25.0 mg mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.00 L          100 %
```
