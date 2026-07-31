# [Reagents](@id pourfecto_reagents)


```@meta
CurrentModule = Pourfecto
```

Pourfecto searches for ways to combine reagents to create desired chemical solutions. Pourfecto uses [CHESSCore](https://jensenlab.github.io/CHESS/dev/)'s `Reagent` interface internally to identify and compute properties of different reagents. In most Pourfecto workflows, however, you do not need to work with reagents directly. Pourfecto can create `Reagent` objects on the fly from reagent names in tables, CSV files, or other user inputs. This page is for advanced users who want a deeper understanding and more control of Pourfecto's behavior.


## CHESSCore reagent types

All reagents in CHESSCore are subtypes of `Reagent`. The built-in concrete reagent types are:

- `Solid`
- `Liquid`
- `Gas`

Each type represents the phase of the reagent at standard temperature and pressure (STP). For Pourfecto, only `Solid` and `Liquid` types are relevant.

---

## Reagent properties

Every `Reagent` subtype has four fields:

| Field | Description |
|---|---|
| `name` | Display name of the reagent |
| `molecular_weight` | Molecular weight, used for conversions between molar and mass quantities |
| `density` | Density at STP, used for conversions between mass and volume quantities |
| `pubchemid` | PubChem identifier associated with the reagent |

CHESSCore uses these properties to automatically compute unit conversions, such as a reagent mass to moles. If a property is unknown, it can be set to `missing`.

For example, a reagent with no known molecular weight, density, or PubChem ID can still be represented:

```julia
using CHESSCore
unknown = Solid("unknown reagent", missing, missing, missing)
```

!!! note
    CHESSCore can create reagents with missing properties, but some conversions may not be possible without molecular weight or density information.

---


## Creating reagents from strings in Pourfecto

The main interface for working with reagents on the fly is `string_to_reagent`.

```julia
using Pourfecto, CHESSCore, Unitful
string_to_reagent("water", Liquid)
string_to_reagent("sodium chloride", Solid)
```

`string_to_reagent` first checks whether the reagent is already [registered](#registered-reagents) in CHESSCore or another custom lab module. If it is registered, the registered reagent object is returned.

If the reagent is not registered, `string_to_reagent` creates a new reagent object on the fly with the given name and unknown physical properties — this is the intended shortcut for using reagents without going through full registration: the returned object is under-defined (only its `name` is known), but that's enough to plan and label a liquid-handling workflow.

For example:

```julia
julia> string_to_reagent("custom buffer", Liquid)
┌ Warning: reagent custom buffer not registered. parsing custom buffer assuming it is a chemical. No chemical properties known.
└ @ CHESSCore ...
custom buffer
```

The returned object is still usable as a reagent identifier in Pourfecto, but its chemical properties are set to `missing`.

!!! note
    Unregistered reagents are useful for planning and labeling liquid-handling workflows.
    However, calculations that require physical properties, such as converting between
    mass and moles or between mass and volume, may require registered reagents with
    known molecular weight or density.

---

## Explicitly choosing the reagent type

`string_to_reagent` takes the reagent name and the concrete `Reagent` subtype to fall back on if the name is not registered:

```julia
string_to_reagent(str::AbstractString, chem_type::Type{<:Reagent})
```

For example:

```julia
using Pourfecto, CHESSCore

buffer = string_to_reagent("custom buffer", Liquid)
salt = string_to_reagent("custom salt", Solid)
gas = string_to_reagent("oxygen mixture", Gas)
```

If the reagent is already registered, the registered reagent is returned and `chem_type` is ignored as a fallback.

This is the form used throughout Pourfecto's own examples and tests.

---

## Inferring reagent type from units

CHESSCore also provides an overload that infers whether an unregistered reagent should be treated as a `Solid` or a `Liquid` based on the unit associated with it. Both CHESSCore and Pourfecto use the [Unitful.jl](https://github.com/JuliaPhysics/Unitful.jl) package for unit definitions and conversions.

```julia
string_to_reagent(str::AbstractString, unit::Unitful.Units)
```

This is especially useful when parsing [stock](@ref pourfecto_stocks) tables, where reagents measured by mass are interpreted as solids, while reagents measured by volume are interpreted as liquids.

```julia
using Pourfecto, CHESSCore, Unitful

string_to_reagent("sodium chloride", u"mg")
string_to_reagent("water", u"mL")
```

The unit-based parser uses the following conventions for unknown reagents:

| Unit type | Interpreted as |
|---|---|
| mass units, e.g. `u"mg"` or `u"g"` | `Solid` |
| amount units, e.g. `u"mol"` or `u"mmol"` | `Solid` |
| density or molarity units, e.g. `u"mg/L"` or `u"mM"` | `Solid` |
| volume units, e.g. `u"µL"` or `u"mL"` | `Liquid` |
| dimensionless units, e.g. percent-style concentrations | `Liquid` |

---

## Converting reagents back to strings

Pourfecto can also convert a reagent object back into a stable string identifier using `reagent_to_string`.

```julia
reagent_to_string(chem)
```

For registered reagents, this returns the registry symbol that can be parsed again later.

For unregistered reagents created on the fly, it returns the reagent name.

```julia
chem = string_to_reagent("custom buffer", Liquid)

reagent_to_string(chem)
```

returns:

```julia
"custom buffer"
```

This is useful for serialization, DataFrame export, JSON export, and converting Pourfecto objects into text-based formats.

---



## Registered reagents


Registered reagents are chemicals already known to CHESSCore or to a custom lab module. You may want to register chemicals explicitly when you need:

- accurate molecular weights
- accurate densities
- PubChem identifiers
- reliable mass-to-mole conversions
- reliable mass-to-volume conversions
- shared lab-wide chemical definitions

Reagents can be registered with CHESSCore's `@reagent` macro in a custom module. For example:

```julia
module MyChemicals
    using CHESSCore
    using Unitful

    @reagent water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
    @reagent sodium_chloride "sodium chloride" Solid 58.44u"g/mol" 2.16u"g/mL" 5234
end
```

Registering the module globally with `CHESSCore.register_lab` (typically done once, in the module's own `__init__`) merges its labware/attribute/read registries into CHESSCore's:

```julia
CHESSCore.register_lab(MyChemicals)
```

`string_to_reagent` itself, however, only looks up reagents in the module(s) named by its `reagent_context` keyword — `register_lab` does not add `MyChemicals` to the *default* `reagent_context` (which is just `CHESSCore`), so `MyChemicals` still needs to be listed explicitly:

```julia
using Pourfecto, CHESSCore, MyChemicals
string_to_reagent("water", Liquid; reagent_context=[CHESSCore, MyChemicals])
string_to_reagent("sodium_chloride", Solid; reagent_context=[CHESSCore, MyChemicals])
```

!!! note
    Lookups match the reagent's *lab symbol* (`water`, `sodium_chloride`), not its free-text
    display `name` (`"sodium chloride"`) — the string passed to `string_to_reagent`/`reagent_context`
    lookups is parsed as a Julia identifier, so it must be valid Julia syntax (no spaces).
