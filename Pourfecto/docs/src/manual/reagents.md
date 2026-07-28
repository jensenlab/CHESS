# [Reagents](@id pourfecto_reagents)


```@meta
CurrentModule = Pourfecto
```

Pourfecto searches for ways to combine reagents to create desired chemical solutions. Pourfecto uses the [JLIMS](https://github.com/jensenlab/JLIMS) interface internally to identify and compute properties of different reagents. In most Pourfecto workflows, however, you do not need to work with reagents directly . Pourfecto can create JLIMS objects on the fly from reagent names in tables, CSV files, or other user inputs. This page is for advanced users who want a deeper understanding and more control of Pourfecto's behavior. 


## JLIMS Chemical types

All chemicals in JLIMS are subtypes of `Chemical`. The built-in concrete chemical types are:

- [`JLIMS.Solid`]
- [`JLIMS.Liquid`]
- [`JLIMS.Gas`]

Each type represents the phase of the chemical at standard temperature and pressure (STP). For Pourfecto, only `Solid` and `Liquid` types are relevant. 

---

## Chemical properties

Every `Chemical` subtype used by JLIMS has four fields:

| Field | Description |
|---|---|
| `name` | Display name of the chemical |
| `molecular_weight` | Molecular weight, used for conversions between molar and mass quantities |
| `density` | Density at STP, used for conversions between mass and volume quantities |
| `pubchemid` | PubChem identifier associated with the chemical |

JLIMS uses these properties to automatically compute unit conversions, such as a chemical mass to moles. If a property is unknown, it can be set to `missing`.

For example, a chemical with no known molecular weight, density, or PubChem ID can still be represented:

```julia
using JLIMS
unknown = JLIMS.Solid("unknown reagent", missing, missing, missing)
```

!!! note
    JLIMS can create chemicals with missing properties, but some conversions may not be possible without molecular weight or density information.

---


## Creating reagents from strings in Pourfecto 

The main Pourfecto interface for working with reagents is [`string_to_reagent`](@ref).

```julia
using JLIMS
string_to_reagent("water", u"mL")
string_to_reagent("sodium chloride", u"mg")
string_to_reagent("ethanol", JLIMS.Liquid)
string_to_reagent("sodium chloride", JLIMS.Solid)
```

Pourfecto first checks whether the reagent is already [registered](#registered-reagents) in JLIMS or another custom module. If it is registered, the registered chemical object is returned.

If the reagent is not registered, Pourfecto creates a new chemical object on the fly with the given name and unknown physical properties.

For example:

```julia
julia> string_to_reagent("custom buffer", u"mL")
┌ Warning: reagent custom buffer not registered. parsing custom buffer assuming it is a chemical. No chemical properties known.
└ @ Pourfecto ...
custom buffer
```

The returned object is still usable as a reagent identifier in Pourfecto, but its chemical properties are set to `missing`.

!!! note
    Unregistered reagents are useful for planning and labeling liquid-handling workflows.
    However, calculations that require physical properties, such as converting between
    mass and moles or between mass and volume, may require registered chemicals with
    known molecular weight or density.

---

---

## Inferring chemical type from units

For convenience, Pourfecto can infer whether an unregistered reagent should be treated as a `JLIMS.Solid` or a `JLIMS.Liquid` based on the unit associated with it. Both JLIMS and Pourfecto use the [Unitful.jl](https://github.com/JuliaPhysics/Unitful.jl) package for unit definitions and conversions.  

```julia
string_to_reagent(str::AbstractString, unit::Unitful.Units)
```

This is especially useful when parsing [stock] tables. For example, reagents measured by mass are interpreted as solids, while reagents measured by volume are interpreted as liquids.

```julia
using Unitful

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

For example:

```julia
julia> string_to_reagent("unknown salt", u"mg")
┌ Warning: reagent unknown salt not registered. parsing unknown salt assuming it is a chemical. No chemical properties known.
└ @ Pourfecto ...
unknown salt
```

creates a `Solid`.

```julia
julia> string_to_reagent("unknown solvent", u"mL")
┌ Warning: reagent unknown solvent not registered. parsing unknown solvent assuming it is a chemical. No chemical properties known.
└ @ Pourfecto ...
unknown solvent
```

creates a `Liquid`.

---

## Explicitly choosing the chemical type

You can also explicitly specify the chemical type to use if the reagent is not registered.

```julia
string_to_reagent(str::AbstractString, chem_type::Type{<:Chemical})
```

For example:

```julia
using JLIMS

buffer = string_to_reagent("custom buffer", Liquid)
salt = string_to_reagent("custom salt", Solid)
gas = string_to_reagent("oxygen mixture", Gas)
```

This form is useful when the unit alone is not enough to infer the intended phase.

If the reagent is already registered, the registered chemical is returned and `chem_type` is ignored as a fallback.

---

## Converting reagents back to strings

Pourfecto can also convert a chemical object back into a stable string identifier using [`reagent_to_string`](@ref).

```julia
reagent_to_string(chem)
```

For registered chemicals, this returns the registry key that can be parsed again later.

For unregistered chemicals created on the fly, it returns the chemical name.

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


Registered reagents are chemicals already known to JLIMS or to a custom lab module. You may want to register chemicals explicitly when you need:

- accurate molecular weights
- accurate densities
- PubChem identifiers
- reliable mass-to-mole conversions
- reliable mass-to-volume conversions
- shared lab-wide chemical definitions

Reagents can be registered with the `JLIMS.@chemical` macro in custom modules . For example:

```julia
module MyChemicals
    using JLIMS
    using Unitful

    JLIMS.@chemical water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
    JLIMS.@chemical sodium_chloride "sodium chloride" Solid 58.44u"g/mol" 2.16u"g/ml" 5234
end 
```

After registration, Pourfecto can resolve those chemicals by name by including `MyChemicals` module  in the `chem_context` argument of `string_to_reagent`:

```julia
using Pourfecto, MyChemicals
string_to_reagent("water", u"mL"; chem_context=[MyChemicals])
string_to_reagent("sodium_chloride", u"mg";chem_context=[MyChemicals])
```

Pourfecto returns the chemical objects registered in the `MyChemicals` module.







