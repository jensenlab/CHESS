# [Reagents](@id pourfecto_reagents)

```@meta
CurrentModule = Pourfecto
```

Pourfecto uses the `Reagent` interface of [CHESSCore](https://jensenlab.github.io/CHESS/dev/). The `Solid`, `Liquid`, and `Gas` types, registration, and unit conversions all belong to CHESSCore. Its [Reagents & Chemicals](https://jensenlab.github.io/CHESS/dev/manual/reagents-chemicals/) page describes them.

This page describes the one part of that interface that Pourfecto workflows use directly: creating reagents from a name.

## Creating reagents on the fly

Most Pourfecto workflows do not need reagents to be registered. `string_to_component` takes a name and a concrete `Reagent` subtype. It returns the registered reagent if one exists. Otherwise it creates a reagent with only a name, leaves the physical properties `missing`, and shows a warning. Given `Organism` instead of a reagent type, it parses an organism name in the same way, and an organism name that is neither registered nor in the form "genus species strain" is an error.

```julia
using Pourfecto, CHESSCore

buffer = string_to_component("custom buffer", Liquid)
salt = string_to_component("custom salt", Solid)
gas = string_to_component("oxygen mixture", Gas)
```

```julia
julia> string_to_component("custom buffer", Liquid)
┌ Warning: reagent custom buffer not registered. parsing custom buffer assuming it is a chemical. No chemical properties known.
└ @ CHESSCore ...
custom buffer
```

The returned reagent identifies the reagent in planning and labeling. Calculations that need molecular weight or density, such as conversions between mass and moles or between mass and volume, need a registered reagent. CHESSCore's [Reagents & Chemicals](https://jensenlab.github.io/CHESS/dev/manual/reagents-chemicals/) page describes registration with the `@reagent` macro, `register_lab`, and the `reagent_context` keyword, and `component_to_string`, the inverse of `string_to_component`.

Pourfecto's examples and tests use this form, and Pourfecto calls it when it parses reagent names from [stock](@ref pourfecto_stocks) tables.

!!! note
    The `reagent_context` keyword of CHESSCore is used when converting stocks with `stock_to_dict` and
    `dict_to_stock` (see [Interop](https://jensenlab.github.io/CHESS/dev/manual/interop/)). Pourfecto's
    table interface, `df_to_labware` and `labware_to_df`, does not use it. It resolves reagents with
    `string_to_component`. A table-based workflow is therefore not affected by the silent fallback
    that the Interop page describes for `reagent_context`.
