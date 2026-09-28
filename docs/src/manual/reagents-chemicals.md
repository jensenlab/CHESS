# Reagents & Chemicals

```@meta
DocTestSetup = :(using CHESS)
```

A `Well`'s contents are described along two axes, not one: *physical form* (what you weigh out and
store) and *chemical identity* (what it behaves as once dissolved). Table salt is a solid you weigh
out -- but once dissolved, it's really two separate chemical identities, Na⁺ and Cl⁻. `CHESSCore`
keeps these as two deliberately distinct concepts: [`Reagent`](@ref) and [`Chemical`](@ref).

## Reagents: physical form

`Reagent` is an abstract type with three concrete subtypes -- `Solid`, `Liquid`, and `Gas` --
sharing four fields: `name`, `molecular_weight`, `density`, and `pubchemid`. `using CHESS` registers
a starter set of reagents, recalled by name with [`@rgt_str`](@ref):

```jldoctest reagents
julia> rgt"water"
water

julia> molecular_weight(rgt"water")
18.015 g mol⁻¹

julia> density(rgt"water")
1.0 g mL⁻¹

julia> pubchemid(rgt"water")
962
```

Register a new one with [`@reagent`](@ref). Any of the three properties can be `missing` if
unknown -- a reagent doesn't need complete data to be registered and used:

```jldoctest reagents
julia> @reagent myreagent "my made-up reagent" Solid missing missing missing
my made-up reagent

julia> molecular_weight(myreagent)
missing
```

## Chemicals: identity

`Chemical` is a single concrete type (`name`, `charge` -- defaults to `0` for neutral species --
and `molecular_weight`). CHESS registers common ions such as Na⁺, Cl⁻, and Ca²⁺. Register a new one
with [`@chemical`](@ref):

```jldoctest reagents
julia> @chemical Li⁺ "Li+" 1 6.94u"g/mol"
Li⁺
```

Recall a registered chemical with [`@chem_str`](@ref) (`chem"Na+"`), which is mainly used to build
a [`Formula`](@ref) -- a stoichiometric expression combining `Chemical`s with `+`/`*`, `*` supplying
a coefficient, as for the two chlorides that balance Ca²⁺:

```jldoctest reagents
julia> chem"Na+" + chem"Cl-"
Formula(Dict{Chemical, Int64}(Na⁺ => 1, Cl⁻ => 1))

julia> chem"Ca2+" + 2*chem"Cl-"
Formula(Dict{Chemical, Int64}(Cl⁻ => 2, Ca²⁺ => 1))
```

## Dissociation: how a reagent breaks down

Every `Reagent` has a [`composition`](@ref) -- a [`CompositionRule`](@ref) describing which
`Chemical`s it breaks down into when dissolved. The default, for anything not registered otherwise,
is simply the reagent's own identity as a single `Chemical`: "no dissociation" isn't a special case,
it's just the default rule.

```jldoctest reagents
julia> composition(rgt"water")
CompositionRule(Dict{Chemical, Int64}(water => 1))
```

[`@reagent_formula`](@ref) registers a reagent and its real dissociation formula in one step, and
derives `molecular_weight` from that formula rather than storing a separate number that could drift
out of sync with it:

```jldoctest reagents
julia> @reagent_formula LiCl "lithium chloride" Solid (Li⁺ + chem"Cl-") missing missing
lithium chloride

julia> molecular_weight(LiCl)
42.39 g mol⁻¹
```

`CompositionRule` coefficients must be non-negative. A base's hydroxide contribution is represented
with the canonical [`OH⁻`](@ref) `Chemical`, not a negative [`H⁺`](@ref) count -- this is what lets
`pH` (covered in [Recipes & Solution Chemistry](recipes.md)) net acid and base contributions by
explicit subtraction, rather than relying on signed stoichiometry. A weak acid or base -- one that
only partially dissociates, and so can't be captured by a fixed `CompositionRule` at all -- is
registered separately as an [`AcidBaseSystem`](@ref) instead; see
[Acid/Base Chemistry](acid-base.md).
