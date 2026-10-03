# Wells: Depositing & Transferring Material

```@meta
DocTestSetup = :(using CHESS)
```

A `Well` holds exactly one [`Stock`](@ref), accessed with [`stock(w)`](@ref). Its capacity is fixed
by its `LocationKind` ([`wellcapacity`](@ref)):

```jldoctest wells
julia> plate = build_location(loc"WP96", "Plate 1");

julia> a1 = plate["A1"];

julia> wellcapacity(a1)
400 μL

julia> stock(a1)
Empty Stock
```

## Depositing and withdrawing

[`deposit!`](@ref) and [`withdraw!`](@ref) add to and remove from a well's stock, within the well's
capacity. The examples use the saline from [Stocks](stocks.md):

```jldoctest wells
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> deposit!(a1, saline)
ERROR: Well Capacity Error: 1 mL is greater than the well's capacity (400 μL)

julia> small_saline = 100u"µL" * saline
100 μL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  500 mg    5.00 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  100 μL          100 %

julia> deposit!(a1, small_saline)

julia> stock(a1)
100 μL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  500 mg    5.00 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  100 μL          100 %
```

The third argument of `deposit!` is a `cost`, a tracked number such as a reagent cost. `withdraw!`
apportions it proportionally when material is removed. It defaults to `0`.

## Transferring between wells

[`transfer!(donor, recipient, quantity)`](@ref) is `withdraw!` then `deposit!` in one call:

```jldoctest wells
julia> a2 = plate["A2"];

julia> transfer!(a1, a2, 40u"µL")

julia> stock(a1)
60.0 μL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  300 mg    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  60.0 μL          100 %

julia> stock(a2)
40.0 μL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  200 mg    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  40.0 μL          100 %
```

## Clearing a well

[`empty!`](@ref) resets a well to `Empty()`. [`sterilize!`](@ref) and [`drain!`](@ref) remove only
part of the contents. The examples use a fresh well holding a `Culture`:

```jldoctest wells
julia> a3 = plate["A3"];

julia> culture = small_saline + 1u"OD*mL" * org"SMU_UA159"
100 μL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.00 mL OD  10.0 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  500 mg    5.00 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  100 μL          100 %

julia> deposit!(a3, culture)
```

`sterilize!` keeps the chemicals, drops the organism:

```jldoctest wells
julia> sterilize!(a3)

julia> stock(a3)
100 μL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  500 mg    5.00 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  100 μL          100 %
```

`drain!` is the inverse: it keeps the organism and drops the chemicals. This example uses a fresh
well so that it does not stack on the sterilized contents of `a3`:

```jldoctest wells
julia> a4 = plate["A4"];

julia> deposit!(a4, culture)

julia> drain!(a4)

julia> stock(a4)
0 mL Culture (0 reagent(s))
 Organisms  Name                        Biomass     OD
───────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.00 mL OD  Inf OD
```
