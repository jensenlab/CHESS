# Registering Lab Constants

```@meta
DocTestSetup = :(using CHESS)
```

Seven macros register lab constants: [`@location_kind`](@ref), [`@attribute`](@ref),
[`@read`](@ref), [`@chemical`](@ref), [`@reagent`](@ref), [`@organism`](@ref), and
[`@stock`](@ref). Each defines a constant in the calling module and records it in a registry so
that it can be found by name. The pattern follows
[Unitful.jl](https://github.com/PainterQubits/Unitful.jl), which registers units and dimensions
with `@unit` and `@dimension` and recalls them with `u"..."`. This page describes the shared
machinery using a small lab module:

```jldoctest registering
julia> module MyLab
       using CHESS
       @location_kind Flask Symbol[] nothing nothing nothing nothing nothing
       @attribute Turbidity u"percent"
       @organism EC_K12 "Escherichia" "coli" "K-12"
       @reagent ethanol "ethanol" Liquid 46.07u"g/mol" 0.789u"g/mL" 702
       end;

julia> CHESSCore.register_lab(MyLab);
```

## Per-module registries and the central merge

Each registration macro keeps a private dictionary scoped to the module that calls it. For
example, `@location_kind` stores every kind it defines in a dictionary kept in hidden storage that
user code cannot reference by accident. The central `location_kinds` registry of `CHESSCore` is a
dictionary of the same kind, scoped to `CHESSCore`.

[`CHESSCore.register_lab(lab_module)`](@ref) connects the two. It adds `lab_module` to
`CHESSCore.labmodules` and, unless `lab_module` is `CHESSCore`, merges the module's registries into
the central ones: `chemprops`, `orgprops`, `location_kinds`, `attribute_kinds`, `read_kinds`, and
`stock_recipes`. Reagents have no central registry (see [`registry_summary`](@ref) below). A lab
module can therefore be developed and tested alone, because its own dictionary works before
`register_lab` is called, and is merged into the shared namespace once, typically from the module's
`__init__`.

## Duplicate registration

[`@location_kind`](@ref), [`@attribute`](@ref), [`@read`](@ref), and [`@stock`](@ref) throw
`ArgumentError` when a name is registered twice, checked against the central registry. `MyLab`
already registered `Flask`, so registering it again fails:

```jldoctest registering
julia> @location_kind Flask Symbol[] nothing nothing nothing nothing nothing
ERROR: ArgumentError: LocationKind Flask already exists
```

[`@organism`](@ref), [`@reagent`](@ref), and [`@chemical`](@ref) have no such check. Registering a
name again with these macros rebinds it to the new value without a warning.

## Namespaces

A lab module can register hundreds of constants, and loading it should not add all of them to the
namespace of the loading code. None of the seven macros exports the names it defines. The constant
exists in the module, and `names` lists it only when called with `all=true`. Each macro has a
paired string macro that looks a name up safely: `@loc_str`, `@attr_str`, `@read_str`, `@chem_str`,
`@rgt_str`, `@org_str`, and `@stock_str`.

## How the string macros resolve a name

All string macros use the same lookup:

1. Search the lab modules visible to the caller. When the code runs, this list is built from
   `CHESSCore.labmodules`, keeping only modules that the calling module has itself loaded.
   Registering a lab module globally is not enough on its own.
2. If nothing matches, try charge-symbol candidates, in which ASCII `+` and `-` are converted to
   Unicode superscripts (see [Reagents & Chemicals](reagents-chemicals.md)).
3. If the name exists in a globally registered lab module that is not visible to the caller, an
   error names the module that must be loaded:

   ```jldoctest registering
   julia> module OtherModule
          using CHESS
          flask_kind() = loc"Flask"
          end
   ERROR: LoadError: ArgumentError: Symbol `Flask` was found in the globally registered lab module MyLab
   but was not in the provided list of lab modules CHESSCore, CHESSLabConstants.

   (Consider `using MyLab` in your module?)
   ```
4. If the name does not exist anywhere, a typo-tolerant "did you mean" search runs against the
   visible modules.

If a name resolves in more than one visible module, the last registered one wins, and a warning is
logged if the values differ.

## Browsing registered constants

[`registry_summary`](@ref) collects every registered constant into one `NamedTuple`, keyed by
category. It is the fastest way to see what a lab module such as `CHESSLabConstants` defines:

```jldoctest registering
julia> registry_summary([CHESSCore, MyLab]).reagents
1-element Vector{NamedTuple}:
 (module_ = MyLab, name = :ethanol, type = Liquid, molecular_weight = 46.07 g mol⁻¹, density = 0.789 g mL⁻¹, pubchemid = 702)
```

With no arguments, `registry_summary()` covers every lab module registered globally. Unlike the
string macros, it is not limited to modules visible to the caller. The `organisms`, `locations`,
`attributes`, and `reads` entries come from the central registries. The `reagents`, `chemicals`,
and `stocks` entries are found by scanning each module's names and filtering by type, because
reagents and chemicals have no central registry and `stock_recipes` holds only stocks registered
with `@stock`.

## Generating registration lines

`CHESSLabConstants` has four functions that help write the registrations of a lab module. They are
used while the module is being written and are not needed to use registered constants.
[`register_reagent!`](@ref), [`register_chemical!`](@ref), and [`register_organism!`](@ref) each
return a line of code that registers the constant, ready to paste into the source of the module.
They do not register anything and do not write to any source file.

For a reagent or a chemical, the function looks up the molecular weight and density in a local
cache. If the cache has no entry, it fetches them from PubChem with [`get_mw_density`](@ref) and
stores them in the cache. The lookup needs a PubChem ID and a network connection. A chemical has no
density, so the fetched density is discarded. For an organism, the function does not look anything
up. It records the genus, species, strain, and optional ATCC ID and notes in the cache.

```julia
using CHESSLabConstants

register_reagent!(CHESSCore.Solid, "boric_acid", "Boric Acid", 7628)
# "@reagent boric_acid \"Boric Acid\" Solid 61.84u\"g/mol\" 1.435u\"g/mL\" 7628"

register_chemical!("Na⁺", "Na+", 1, 923)
# "@chemical Na⁺ \"Na+\" 1 22.9897693u\"g/mol\""

register_organism!("SMU_UA159", "Streptococcus", "mutans", "UA159"; atcc_id = "700610", notes = "wild type")
# "@organism SMU_UA159 \"Streptococcus\" \"mutans\" \"UA159\""
```

A compound with no PubChem entry, such as a rich-media broth, is registered without a PubChem ID,
and its molecular weight and density are recorded as `missing`. [`get_mw_density`](@ref) takes a
PubChem ID and returns the molecular weight in g/mol and the density in g/mL.

[Database Architecture](db-architecture.md) describes how CHESSDatabase stores the locations and
stocks built from registered constants.
