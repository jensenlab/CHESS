# Organisms & Cultures

A [`Culture`](@ref) also tracks living organisms, not just chemicals -- an [`Organism`](@ref) is a
species-and-strain identity: `genus`, `species`, and `strain`. Each `Organism` present in a `Culture`
carries a [`Biomass`](@ref) quantity, not just presence/absence.

## Registering an organism

Register one with [`@organism`](@ref):

```julia
@organism SMU_UA159 "Streptococcus" "mutans" "UA159"
```

```julia-repl
julia> genus(SMU_UA159)
"Streptococcus"

julia> species(SMU_UA159)
"mutans"

julia> strain(SMU_UA159)
"UA159"

julia> name(SMU_UA159)
"Streptococcus mutans UA159"
```

`name(x)` joins all three fields for display. `show(x)` prints the recoverable binding name
instead (`SMU_UA159`), the same convention [`Reagent`](@ref)/[`Chemical`](@ref) use.

## Recalling with `@org_str`

[`@org_str`](@ref) is the collision-safe lookup, mirroring
[`@loc_str`](@ref)/[`@attr_str`](@ref)/[`@rgt_str`](@ref)/[`@chem_str`](@ref):

```julia-repl
julia> org"SMU_UA159"
SMU_UA159
```

## Biomass: a quantity, not just presence

Organisms can't be counted directly -- the only real measurement is optical density (OD), which is
a concentration, not a count. [`Biomass`](@ref) is the quantity CHESS tracks for an organism: an
absolute, conserved amount dimensioned as `OD * Volume`, so `biomass / volume` recovers an OD
reading by construction (no separate calibration factor). Like a solid's `Mass` or a liquid's
`Volume`, `Biomass` isn't tied to *this stock's* current liquid volume -- a `Culture` can validly
have organisms and zero liquid (see [Stocks](stocks.md)).

Write an inoculum by multiplying a `Biomass` quantity by an `Organism`, the same way a `Reagent`
quantity builds a `Mixture`/`Solution`:

```julia-repl
julia> inoculum = 1u"OD*mL" * org"SMU_UA159"
1.0 mL OD Culture (0 reagent(s))
 Organisms  Name                        Biomass    OD
───────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  1.0 OD
```

## Promoting a Stock to a Culture

Adding a quantified `Organism` to any `Stock` -- e.g. `saline`, built in [Stocks](stocks.md) --
promotes it to a `Culture`. `Biomass` is conserved under `+`/`-`/scalar `*`/`/` exactly like
solids/liquids, so diluting or mixing a culture visibly dilutes or combines its organism content:

```julia-repl
julia> culture = saline + inoculum
1.0 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass    OD
───────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  1.0 mL OD  1.0 OD

 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %

julia> diluted = 10u"mL" * culture # dilute to 10 mL total -- biomass scales down with it
10.0 mL Culture (2 reagent(s))
 Organisms  Name                        Biomass     OD
────────────────────────────────────────────────────────
 SMU_UA159  Streptococcus mutans UA159  10.0 mL OD  1.0 OD
```

Since `quantity(::Stock)` is total *liquid* volume, `"OD"` in the `Concentration`/`OD` column above
is the culture's current, on-demand-derived optical density -- `Biomass / quantity(culture)` --
never a value stored directly on the `Organism`.

### Removing organisms

`-` mixes by subtraction just like solids/liquids (see [The non-negativity constraint](stocks.md)),
so an organism's biomass can now be reduced or fully removed -- e.g. centrifuging off a supernatant
or autoclaving a stock are just applications of `-` with an explicitly constructed `Stock`, not
special-cased operations:

```julia-repl
julia> sterilized = culture - inoculum # remove exactly this much biomass -- no organisms left
1.0 mL Solution (2 reagent(s))
 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %
```
