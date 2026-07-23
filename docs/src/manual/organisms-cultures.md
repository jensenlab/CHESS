# Organisms & Cultures

A [`Culture`](@ref) also tracks living organisms, not just chemicals -- an [`Organism`](@ref) is a
species-and-strain identity: `genus`, `species`, and `strain`.

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

## Promoting a Stock to a Culture

Adding an `Organism` to any `Stock` -- e.g. `saline`, built in [Stocks](stocks.md) -- promotes it
to a `Culture`:

```julia-repl
julia> culture = saline + org"SMU_UA159"
1.0 mL Culture (2 reagent(s))
 Organisms
───────────
 SMU_UA159

 Solids  Name             Amount  Concentration
────────────────────────────────────────────────
 NaCl    sodium chloride   5.0 g     5.0 g mL⁻¹

 Liquids  Name   Amount  Concentration
───────────────────────────────────────
 water    water  1.0 mL        100.0 %
```
