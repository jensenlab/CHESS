# Organisms & Cultures

```@meta
DocTestSetup = :(using CHESS)
```

A [`Culture`](@ref) also tracks living organisms, not just chemicals -- an [`Organism`](@ref) is a
species-and-strain identity: `genus`, `species`, and `strain`. Each `Organism` present in a `Culture`
carries a [`Biomass`](@ref CHESSCore.Biomass) quantity, not just presence/absence.

## Registering an organism

`using CHESS` registers several lab strains. Register a new one with [`@organism`](@ref):

```jldoctest organisms
julia> @organism BSU_168 "Bacillus" "subtilis" "168"
Bacillus subtilis 168

julia> genus(BSU_168)
"Bacillus"

julia> species(BSU_168)
"subtilis"

julia> strain(BSU_168)
"168"

julia> name(BSU_168)
"Bacillus subtilis 168"
```

`name(x)` joins all three fields for display. `show(x)` prints the recoverable binding name
instead (`BSU_168`), the same convention [`Reagent`](@ref)/[`Chemical`](@ref) use.

## Recalling with `@org_str`

[`@org_str`](@ref) is the collision-safe lookup, mirroring
[`@loc_str`](@ref)/[`@attr_str`](@ref)/[`@rgt_str`](@ref)/[`@chem_str`](@ref). It finds
organisms registered by CHESS or a lab module:

```jldoctest organisms
julia> org"SMU_UA159"
SMU_UA159
```

## Biomass: a quantity, not just presence

Organisms can't be counted directly -- the only real measurement is optical density (OD), which is
a concentration, not a count. [`Biomass`](@ref CHESSCore.Biomass) is the quantity CHESS tracks for an organism: an
absolute, conserved amount dimensioned as `OD * Volume`, so `biomass / volume` recovers an OD
reading by construction (no separate calibration factor). Like a solid's `Mass` or a liquid's
`Volume`, `Biomass` isn't tied to *this stock's* current liquid volume -- a `Culture` can validly
have organisms and zero liquid (see [Stocks](stocks.md)).

Write an inoculum by multiplying a `Biomass` quantity by an `Organism`, the same way a `Reagent`
quantity builds a `Mixture`/`Solution`:

```jldoctest organisms
julia> inoculum = 1u"OD*mL" * org"SMU_UA159"
0.0 mL Culture (0 reagent(s))
 Organisms  Name                        Biomass    OD
──────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  Inf OD
```

The inoculum has no liquid, so its total quantity is `0.0 mL` and its OD, biomass divided by liquid
volume, shows as `Inf` until it is mixed into a liquid.

## Promoting a Stock to a Culture

Adding a quantified `Organism` to any `Stock` promotes it to a `Culture`, shown here with the saline
from [Stocks](stocks.md). `Biomass` is conserved under `+`/`-`/scalar `*`/`/` exactly like
solids/liquids, so diluting or mixing a culture visibly dilutes or combines its organism content:

```jldoctest organisms
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> culture = saline + inoculum
1.0 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass    OD
──────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  1.0 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %

julia> diluted = 10u"mL" * culture # dilute to 10 mL total -- biomass scales down with it
10.0 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
───────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  10.0 mL OD  1.0 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  50.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  10.0 mL        100.0 %
```

Since `quantity(::Stock)` is total *liquid* volume, `"OD"` in the `Concentration`/`OD` column above
is the culture's current, on-demand-derived optical density -- `Biomass / quantity(culture)` --
never a value stored directly on the `Organism`.

### Removing organisms

`-` mixes by subtraction just like solids/liquids (see [The non-negativity constraint](stocks.md)),
so an organism's biomass can now be reduced or fully removed -- e.g. centrifuging off a supernatant
or autoclaving a stock are just applications of `-` with an explicitly constructed `Stock`, not
special-cased operations:

```jldoctest organisms
julia> sterilized = culture - inoculum # remove exactly this much biomass -- no organisms left
1.0 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %
```
