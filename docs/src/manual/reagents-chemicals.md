# Reagents & Chemicals

A `Well`'s contents are described along two axes, not one: *physical form* (what you weigh out and
store) and *chemical identity* (what it behaves as once dissolved). Table salt is a solid you weigh
out -- but once dissolved, it's really two separate chemical identities, Na⁺ and Cl⁻. `CHESSCore`
keeps these as two deliberately distinct concepts: [`Reagent`](@ref) and [`Chemical`](@ref).

## Reagents: physical form

`Reagent` is an abstract type with three concrete subtypes -- `Solid`, `Liquid`, and `Gas` --
sharing four fields: `name`, `molecular_weight`, `density`, and `pubchemid`. Register one with
[`@reagent`](@ref):

```julia
@reagent water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
```

```julia-repl
julia> molecular_weight(water)
18.015 g mol⁻¹

julia> density(water)
1.0 g mL⁻¹

julia> pubchemid(water)
962
```

Any of the three properties can be `missing` if unknown -- a reagent doesn't need complete data to
be registered and used:

```julia-repl
julia> @reagent myreagent "my made-up reagent" Solid missing missing missing
myreagent

julia> molecular_weight(myreagent)
missing
```

Recall a registered reagent with [`@rgt_str`](@ref):

```julia-repl
julia> rgt"water" 
water 
```

## Chemicals: identity

`Chemical` is a single concrete type (`name`, `charge` -- defaults to `0` for neutral species --
and `molecular_weight`). Register one with [`@chemical`](@ref):

```julia
@chemical Na⁺ "Na+" 1 22.99u"g/mol"
@chemical Cl⁻ "Cl-" -1 35.45u"g/mol"
```

Recall one with [`@chem_str`](@ref) (`chem"Na+"`), which is mainly used to build a
[`Formula`](@ref) -- a stoichiometric expression combining `Chemical`s with `+`/`*`, `*` supplying a
coefficient for a doubly-charged ion like Ca²⁺:

```julia-repl
julia> chem"Na+" + chem"Cl-"
```

```julia
@chemical Ca²⁺ "Ca2+" 2 40.08u"g/mol"
```

```julia-repl
julia> chem"Ca2+" + 2*chem"Cl-"
```

## Dissociation: how a reagent breaks down

Every `Reagent` has a [`composition`](@ref) -- a [`CompositionRule`](@ref) describing which
`Chemical`s it breaks down into when dissolved. The default, for anything not registered otherwise,
is simply the reagent's own identity as a single `Chemical`: "no dissociation" isn't a special case,
it's just the default rule.

```julia-repl
julia> composition(water)
CompositionRule(Dict{Chemical, Int64}(water => 1))
```

[`@reagent_formula`](@ref) registers a reagent and its real dissociation formula in one step, and
derives `molecular_weight` from that formula rather than storing a separate number that could drift
out of sync with it:

```julia-repl
julia> @reagent_formula NaCl "sodium chloride" Solid (chem"Na+"+chem"Cl-") missing missing
NaCl

julia> molecular_weight(NaCl)
58.44 g mol⁻¹
```

`CompositionRule` coefficients must be non-negative. A base's hydroxide contribution is represented
with the canonical [`OH⁻`](@ref) `Chemical`, not a negative [`H⁺`](@ref) count -- this is what lets
`pH` (covered in [Recipes & Solution Chemistry](recipes.md)) net acid and base contributions by
explicit subtraction, rather than relying on signed stoichiometry.
