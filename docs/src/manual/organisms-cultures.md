# Organisms & Cultures

```@meta
DocTestSetup = :(using CHESS)
```

A [`Culture`](@ref) tracks living organisms as well as chemicals. An [`Organism`](@ref) is a
species and strain identity with the fields `genus`, `species`, and `strain`. Each `Organism` in a
`Culture` carries a [`Biomass`](@ref CHESSCore.Biomass) quantity.

## Registering an organism

CHESS already includes several lab strains. The [`@organism`](@ref) macro defines a new one:

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

`name(x)` joins all three fields. `show(x)` prints the binding name (`BSU_168`), as it does for
[`Reagent`](@ref) and [`Chemical`](@ref).

## Recalling with `@org_str`

[`@org_str`](@ref) looks up organisms registered by CHESS or a lab module, like
[`@loc_str`](@ref), [`@attr_str`](@ref), [`@rgt_str`](@ref), and [`@chem_str`](@ref):

```jldoctest organisms
julia> org"SMU_UA159"
SMU_UA159
```

## Biomass

Organisms cannot be counted directly. The available measurement is optical density (OD), which is
a concentration. [`Biomass`](@ref CHESSCore.Biomass) is the quantity CHESS tracks for an organism:
an absolute, conserved amount with dimensions `OD * Volume`, so `biomass / volume` gives an OD
reading with no calibration factor. Like a solid's `Mass` or a liquid's `Volume`, `Biomass` is not
tied to the stock's liquid volume, so a `Culture` can have organisms and no liquid (see
[Stocks](stocks.md)).

Multiplying a `Biomass` quantity by an `Organism` writes an inoculum, as multiplying a quantity by
a `Reagent` builds a `Mixture` or `Solution`:

```jldoctest organisms
julia> inoculum = 1u"OD*mL" * org"SMU_UA159"
0 mL Culture (0 reagent(s))
 Organisms  Name                        Biomass     OD
───────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.00 mL OD  Inf OD
```

The inoculum has no liquid, so its total quantity is `0 mL` and its OD, biomass divided by liquid
volume, shows as `Inf` until it is mixed into a liquid.

## Promoting a Stock to a Culture

Adding a quantified `Organism` to any `Stock` promotes it to a `Culture`. The example uses the
saline from [Stocks](stocks.md). `Biomass` is conserved under `+`, `-`, and scalar `*` and `/`, like
solids and liquids, so diluting or mixing a culture dilutes or combines its organisms:

```jldoctest organisms
julia> saline = 1u"mL" * rgt"water" + 5u"g" * rgt"sodium_chloride";

julia> culture = saline + inoculum
1.00 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.00 mL OD  1.00 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  5.00 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %

julia> diluted = 10u"mL" * culture # dilute to 10 mL total; biomass scales with it
10.0 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
────────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  10.0 mL OD  1.00 OD

 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  50.0 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  10.0 mL          100 %
```

The `OD` column above is the culture's current optical density, `Biomass / quantity(culture)`,
where `quantity(::Stock)` is the total liquid volume. It is derived on demand and never stored on
the `Organism`.

### Removing organisms

`-` subtracts organism biomass as it does solids and liquids (see
[The non-negativity constraint](stocks.md)). Centrifuging off a supernatant or autoclaving a stock
is `-` with an explicitly constructed `Stock`:

```jldoctest organisms
julia> sterilized = culture - inoculum # remove exactly this much biomass; no organisms left
1.00 mL Solution (2 reagent(s))
 Solids           Name             Amount  Concentration
─────────────────────────────────────────────────────────
 sodium_chloride  Sodium Chloride  5.00 g    5.00 g mL⁻¹

 Liquids  Name   Amount   Concentration
────────────────────────────────────────
 water    water  1.00 mL          100 %
```
