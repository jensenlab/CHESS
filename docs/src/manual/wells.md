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

A well holds no cost. The cost of what a well contains is found by tracing the material back to the lots
it came from. See [Observations](observations.md#Tracing-contents-to-lots).

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

## Discarding material

[`discard!`](@ref) removes a quantity from a well and sends it nowhere: it is used up, poured to waste,
or thrown away. It takes a proportional slice of every component, as [`withdraw!`](@ref) does, and
throws if the well holds less than the quantity. In a database, `upload(discard!, well, quantity)`
records a withdrawal in the `Discards` table instead of a lower observed amount, so the ledger keeps
the fact that material was taken. Replay, [`trace_contents`](@ref) and cache repair treat it as a
withdrawal from the source, and `update(discard!, ...; replace = s)` or `insert = s` amends one like any
other entry; a discard can replace only a discard. Planned operations (encumbrances) do not include
discards.

[`remove_from_parent!`](@ref) is the matching operation for location: it takes a location out of its
parent and leaves it located nowhere. It refuses a locked location and a well. In a database it is a
movement with no parent, and amends like a move.

## Well names and positions

[`plate_namer`](@ref) returns the standard microplate name of a well from its row and column.
[`add_stock!`](@ref) deposits a stock into the well at a row and column of a `Labware` and is a
shorthand for `deposit!` on that well. It shows a warning if the well is not empty and then deposits
anyway:

```jldoctest wells
julia> plate_namer(1, 1), plate_namer(8, 12)
("A1", "H12")

julia> add_stock!(plate, 50u"µL" * rgt"water", 2, 1);

julia> stock(plate["B1"])
50.0 μL Solution (1 reagent(s))
 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  50.0 μL          100 %
```

With `LabwarePlotting` and `Plots` loaded, `plot_well_heatmap!` overlays a heatmap of the quantity
in each well, in µL, on a plot. Empty wells count as zero.

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
