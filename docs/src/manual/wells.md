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

[`deposit!`](@ref)/[`withdraw!`](@ref) add to and remove from a well's stock, guarded by its
capacity. The examples use the saline from [Stocks](stocks.md):

```jldoctest wells
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> deposit!(a1, saline)
ERROR: Well Capacity Error: 1 mL is greater than the well's capacity (400 μL)

julia> small_saline = 100u"µL" * saline
0.1 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %

julia> deposit!(a1, small_saline)

julia> stock(a1)
0.1 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %
```

`deposit!`'s third argument is a `cost` -- a plain tracked number (e.g. a reagent cost), apportioned
proportionally whenever `withdraw!` pulls material back out. It defaults to `0`.

## Transferring between wells

[`transfer!(donor, recipient, quantity)`](@ref) is `withdraw!` then `deposit!` in one call:

```jldoctest wells
julia> a2 = plate["A2"];

julia> transfer!(a1, a2, 40u"µL")

julia> stock(a1)
0.06 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.3 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.06 mL        100.0 %

julia> stock(a2)
0.04 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.2 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.04 mL        100.0 %
```

## Clearing a well

[`empty!`](@ref) resets a well to `Empty()` outright. [`sterilize!`](@ref) and [`drain!`](@ref) are
more selective -- demonstrated on a fresh well holding a `Culture`:

```jldoctest wells
julia> a3 = plate["A3"];

julia> culture = small_saline + 1u"OD*mL" * org"SMU_UA159"
0.1 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass    OD
───────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  10.0 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %

julia> deposit!(a3, culture)
```

`sterilize!` keeps the chemicals, drops the organism:

```jldoctest wells
julia> sterilize!(a3)

julia> stock(a3)
0.1 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %
```

`drain!` is the inverse -- keeps the organism, drops the chemicals. Shown on a fresh well with its
own deposit of `culture`, so it doesn't stack on top of `a3`'s already-sterilized contents:

```jldoctest wells
julia> a4 = plate["A4"];

julia> deposit!(a4, culture)

julia> drain!(a4)

julia> stock(a4)
0.0 mL Culture (0 reagent(s))
 Organisms  Name                        Biomass    OD
──────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  Inf OD
```
