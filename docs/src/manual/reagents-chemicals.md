# Reagents & Chemicals

```@meta
DocTestSetup = :(using CHESS)
```

A `Well`'s contents are described along two axes: *physical form*, what is weighed out and stored,
and *chemical identity*, what the material is once dissolved. Table salt is a solid that is weighed
out, and once dissolved it is two chemical identities, Na⁺ and Cl⁻. `CHESSCore` represents these as
two concepts: [`Reagent`](@ref) and [`Chemical`](@ref).

## Reagents: physical form

`Reagent` is an abstract type with three concrete subtypes, `Solid`, `Liquid`, and `Gas`, which
share four fields: `name`, `molecular_weight`, `density`, and `pubchemid`. `using CHESS` registers
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

[`@reagent`](@ref) registers a new reagent. Any of the three properties can be `missing`, so a
reagent can be registered and used with incomplete data:

```jldoctest reagents
julia> @reagent myreagent "my made-up reagent" Solid missing missing missing
my made-up reagent

julia> molecular_weight(myreagent)
missing
```

## Chemicals: identity

`Chemical` is a single concrete type with the fields `name`, `charge` (`0` for neutral species),
and `molecular_weight`. CHESS registers common ions such as Na⁺, Cl⁻, and Ca²⁺. [`@chemical`](@ref)
registers a new one:

```jldoctest reagents
julia> @chemical Li⁺ "Li+" 1 6.94u"g/mol"
Li⁺
```

[`@chem_str`](@ref) recalls a registered chemical (`chem"Na+"`). It is mainly used to build a
[`Formula`](@ref), a stoichiometric expression that combines `Chemical`s with `+` and supplies
coefficients with `*`, as for the two chlorides that balance Ca²⁺:

```jldoctest reagents
julia> chem"Na+" + chem"Cl-"
Formula(Dict{Chemical, Int64}(Na⁺ => 1, Cl⁻ => 1))

julia> chem"Ca2+" + 2*chem"Cl-"
Formula(Dict{Chemical, Int64}(Cl⁻ => 2, Ca²⁺ => 1))
```

## Dissociation: how a reagent breaks down

Every `Reagent` has a [`composition`](@ref), a [`CompositionRule`](@ref) that describes which
`Chemical`s it breaks down into when dissolved. The default rule is the reagent's own identity as a
single `Chemical`, which means no dissociation.

```jldoctest reagents
julia> composition(rgt"water")
CompositionRule(Dict{Chemical, Int64}(water => 1))
```

[`@reagent_formula`](@ref) registers a reagent and its dissociation formula in one step. It
derives `molecular_weight` from the formula, so the two cannot disagree:

```jldoctest reagents
julia> @reagent_formula LiCl "lithium chloride" Solid (Li⁺ + chem"Cl-") missing missing
lithium chloride

julia> molecular_weight(LiCl)
42.39 g mol⁻¹
```

`CompositionRule` coefficients must be non-negative. A base's hydroxide is represented by the
canonical [`OH⁻`](@ref) `Chemical`, not a negative [`H⁺`](@ref) count. This lets `pH` (see
[Recipes & Solution Chemistry](recipes.md)) net acid and base contributions by explicit
subtraction instead of signed stoichiometry.

A weak acid or base only partially dissociates, so a fixed `CompositionRule` cannot describe it.
It is registered as an [`AcidBaseSystem`](@ref) instead. See [Acid/Base Chemistry](acid-base.md).
