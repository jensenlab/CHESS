# CHESSCore API Reference

`CHESSCore` is the in-memory "lab engine": the `Location`, `Stock`, `Attribute`, and `Read` types and
the operations that act on them. It has no database dependency. The reference is split by topic:

- [Locations & Operations](core-locations.md): building locations, moving them, occupancy,
  locking and activity, transfers between wells, and instrument capability.
- [Stocks](core-stocks.md): reagents, chemicals, organisms, stocks, and CHESS's extra units.
- [Solution Chemistry](core-chemistry.md): molar recipes, pH, and acid/base equilibria.
- [Attributes & Reads](core-environment.md): environmental attributes, inheritance, and instrument
  reads.
- [Interop](core-interop.md): table and JSON conversion of stocks and locations.

The entry points most code starts from are [`build_location`](@ref), [`move_into!`](@ref),
[`deposit!`](@ref), [`transfer!`](@ref), [`set_attribute!`](@ref), and [`record_read!`](@ref).

This page lists the error types CHESSCore throws and [`register_lab`](@ref CHESSCore.register_lab), which registers a lab's constants module. The
[Troubleshooting](../manual/troubleshooting.md) page explains the most common errors.

```@autodocs
Modules = [CHESS.CHESSCore]
Pages = ["CHESSCore.jl", "user.jl", "exceptions.jl"]
```
