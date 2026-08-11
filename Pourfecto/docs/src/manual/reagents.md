# [Reagents](@id pourfecto_reagents)


```@meta
CurrentModule = Pourfecto
```

Pourfecto uses [CHESSCore](https://jensenlab.github.io/CHESS/dev/)'s `Reagent` interface directly — `Solid`/`Liquid`/`Gas` types, registration, and unit conversions are all CHESSCore's, not Pourfecto's own. For the full reagent/chemical type reference, see CHESSCore's [Reagents & Chemicals](https://jensenlab.github.io/CHESS/dev/manual/reagents-chemicals/) manual page.

This page covers only the one piece of that interface Pourfecto workflows use directly: creating reagents on the fly.

## Creating reagents on the fly

Most Pourfecto workflows don't require full reagent registration. `string_to_reagent` is the shortcut: given a name and a concrete `Reagent` subtype, it returns the registered reagent if one exists, or otherwise creates an under-defined one (only the name is known; physical properties are `missing`) with a warning.

```julia
using Pourfecto, CHESSCore

buffer = string_to_reagent("custom buffer", Liquid)
salt = string_to_reagent("custom salt", Solid)
gas = string_to_reagent("oxygen mixture", Gas)
```

```julia
julia> string_to_reagent("custom buffer", Liquid)
┌ Warning: reagent custom buffer not registered. parsing custom buffer assuming it is a chemical. No chemical properties known.
└ @ CHESSCore ...
custom buffer
```

The returned object is still usable as a reagent identifier in Pourfecto — for planning and labeling a workflow — but calculations that require molecular weight or density (e.g. mass ↔ mole or mass ↔ volume conversions) need a registered reagent instead. See CHESSCore's [Reagents & Chemicals](https://jensenlab.github.io/CHESS/dev/manual/reagents-chemicals/) page for registration (the `@reagent` macro, `register_lab`, and the `reagent_context` keyword) and for `reagent_to_string`, the inverse operation.

This is the form used throughout Pourfecto's own examples and tests; it's also what Pourfecto calls internally when parsing reagent names out of [stock](@ref pourfecto_stocks) tables.

!!! note
    CHESSCore's `reagent_context` keyword (used with `stock_to_dict`/`dict_to_stock` round-tripping
    -- see [Interop](https://jensenlab.github.io/CHESS/dev/manual/interop/)) isn't used anywhere in
    Pourfecto's own DataFrame interface (`df_to_labware`/`labware_to_df`), which resolves reagents
    through `string_to_reagent` instead. If you're only using Pourfecto's table-based workflow, the
    `reagent_context` silent-fallback failure mode described in that chapter doesn't apply to you.
