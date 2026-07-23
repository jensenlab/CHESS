# Wells: Depositing & Transferring Material

A `Well` holds exactly one [`Stock`](@ref), accessed with [`stock(w)`](@ref). Its capacity is fixed
by its `LocationKind` ([`wellcapacity`](@ref)):

```julia-repl
julia> plate = build_location(loc"WP96", "Plate 1")
Plate 1

julia> a1 = plate["A1"]
A1

julia> wellcapacity(a1)
200 μL

julia> stock(a1)
Empty Stock
```

## Depositing and withdrawing

[`deposit!`](@ref)/[`withdraw!`](@ref) add to and remove from a well's stock, guarded by its
capacity:

```julia-repl
julia> deposit!(a1, saline)
ERROR: Well Capacity Error: 1 mL is greater than the well's capacity (200 μL)

julia> small_saline = 100u"µL" * saline

julia> deposit!(a1, small_saline)

julia> stock(a1)
0.1 mL Solution (2 reagent(s))
 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %
```

`deposit!`'s third argument is a `cost` -- a plain tracked number (e.g. a reagent cost), apportioned
proportionally whenever `withdraw!` pulls material back out. It defaults to `0`.

## Transferring between wells

[`transfer!(donor, recipient, quantity)`](@ref) is `withdraw!` then `deposit!` in one call:

```julia-repl
julia> a2 = plate["A2"]
A2

julia> transfer!(a1, a2, 40u"µL")

julia> stock(a1)
0.06 mL Solution (2 reagent(s))
 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   0.3 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.06 mL        100.0 %

julia> stock(a2)
0.04 mL Solution (2 reagent(s))
 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   0.2 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  0.04 mL        100.0 %
```

## Clearing a well

[`empty!`](@ref) resets a well to `Empty()` outright. [`sterilize!`](@ref) and [`drain!`](@ref) are
more selective -- demonstrated on a fresh well holding a `Culture`:

```julia-repl
julia> a3 = plate["A3"]
A3

julia> culture = small_saline + org"SMU_UA159"

julia> deposit!(a3, culture)
```

`sterilize!` keeps the chemicals, drops the organism:

```julia-repl
julia> sterilize!(a3)

julia> stock(a3)
0.1 mL Solution (2 reagent(s))
 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   0.5 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  0.1 mL        100.0 %
```

`drain!` is the inverse -- keeps the organism, drops the chemicals. Shown on a fresh well with its
own deposit of `culture`, so it doesn't stack on top of `a3`'s already-sterilized contents:

```julia-repl
julia> a4 = plate["A4"]
A4

julia> deposit!(a4, culture)

julia> drain!(a4)

julia> stock(a4)
0.0 mL Culture (0 reagent(s))
 Organisms
───────────
 SMU_UA159
```
