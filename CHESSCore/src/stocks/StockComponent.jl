"""
    abstract type StockComponent end

Common supertype for anything a [`Stock`](@ref) can contain and track a quantity of --
[`Reagent`](@ref) (chemical substances: `Solid`/`Liquid`/`Gas`) and [`Organism`](@ref). Exists purely
as a dispatch/gathering anchor -- e.g. so Pourfecto's planning code can enumerate everything in a
Stock uniformly -- not as a shared-behavior contract: `StockComponent` has no fields or methods of
its own, and `Reagent`'s chemistry-specific machinery (molecular weight, density, composition,
PubChem-backed persistence) is not inherited by `Organism`, nor is anything organism-specific
inherited by `Reagent`.
"""
abstract type StockComponent end
