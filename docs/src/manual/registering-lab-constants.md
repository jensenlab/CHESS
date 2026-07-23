# Registering Lab Constants

Every registration macro used so far -- [`@location_kind`](@ref), [`@attribute`](@ref),
[`@read`](@ref), [`@chemical`](@ref), [`@reagent`](@ref), [`@organism`](@ref), [`@stock`](@ref) --
does two things at once: define a `const` binding in the calling module, and record that binding in
a registry so it can be found later by name. This pattern is closely modeled on
[Unitful.jl](https://github.com/PainterQubits/Unitful.jl)'s own approach to registering units and
dimensions (`@unit`/`@dimension`, recalled via `u"..."`). This chapter covers the shared machinery
directly, using a small worked lab module:

```julia
module MyLab
using CHESSCore, Unitful
@location_kind Flask Symbol[] nothing nothing nothing nothing nothing
@attribute Turbidity u"percent"
@organism EC_K12 "Escherichia" "coli" "K-12"
@reagent ethanol "ethanol" Liquid 46.07u"g/mol" 0.789u"g/mL" 702
end

CHESSCore.register_lab(MyLab)
```

## Per-module registries and the central merge

Each registration macro keeps a private dict scoped to the module it's called in -- e.g.
`@location_kind` stores every kind it defines into a dict kept in an internal, hidden storage
location that no user code can accidentally reference. `CHESSCore`'s own central
`location_kinds` registry *is* that same kind of per-module dict, just scoped to `CHESSCore` itself
rather than a separate structure.

[`CHESSCore.register_lab(lab_module)`](@ref) is what connects the two: it always adds `lab_module`
to `CHESSCore.labmodules`, and then -- unless `lab_module` is `CHESSCore` itself -- folds the
module's own registries into CHESSCore's central ones (`chemprops`, `orgprops`, `location_kinds`,
`attribute_kinds`, `read_kinds`, `stock_recipes`; reagents have no central registry, see
[`registry_summary`](@ref) below). This means a lab module can be developed and tested standalone --
its own dict already works before `register_lab` is ever called -- and gets folded into the shared
global namespace exactly once, typically from the module's `__init__`.

## Duplicate registration -- not uniform across the seven

[`@location_kind`](@ref), [`@attribute`](@ref), [`@read`](@ref), and [`@stock`](@ref) throw
`ArgumentError` when a name is registered twice (checked against the always-current central
registry):

```julia-repl
julia> @location_kind Flask Symbol[] nothing nothing nothing nothing nothing
Flask

julia> @location_kind Flask Symbol[] nothing nothing nothing nothing nothing
ERROR: ArgumentError: LocationKind Flask already exists
```

[`@organism`](@ref), [`@reagent`](@ref), and [`@chemical`](@ref) have no such guard --
re-registering a name under these macros silently rebinds it to a new value. This is a real
asymmetry among the seven macros, not a uniform rule.

## Namespace hygiene: why none of these export

A lab module registering hundreds of constants doesn't want to flood the namespace of anyone who
`using`s it -- so none of the seven macros `export` the names they define. The binding still exists
(`isdefined` is `true`) but doesn't appear in `names(m)` unless you pass `all=true`. The collision-safe
way to look a name up regardless is the paired string macro: `@loc_str`/`@attr_str`/`@read_str`/
`@chem_str`/`@rgt_str`/`@org_str`/`@stock_str`.

## How the string macros resolve a name

Every string macro shares the same lookup algorithm:

1. Search the caller-visible lab modules only. This list is built, when that code actually runs,
   from `CHESSCore.labmodules`, filtered down to modules the *calling* module has itself `using`'d
   -- registering a lab module globally isn't enough on its own.
2. If nothing matches, try charge-symbol candidates (ASCII `+`/`-` normalized to unicode
   superscript, covered in [Reagents & Chemicals](reagents-chemicals.md)).
3. If the name exists in some globally registered lab module, but isn't visible to the caller, a
   specific error names the missing `using`:

   ```julia-repl
   julia> loc"Flask"
   ERROR: ArgumentError: Symbol `Flask` was found in the globally registered lab module Main.MyLab
   but was not in the provided list of lab modules CHESSCore.

   (Consider `using Main.MyLab` in your module?)
   ```
4. If the name doesn't exist anywhere at all, a fuzzy, typo-tolerant "did you mean" search runs
   against the caller-visible list instead.

If a name resolves in more than one caller-visible module, the last-registered one wins, and a
`@warn` fires if the values actually differ.

## `registry_summary`: browsing everything registered

[`registry_summary`](@ref) assembles every registered constant into one `NamedTuple`, keyed by
category -- the practical payoff of the whole registry system, and the fastest way to answer "what's
already defined" for a lab module like `CHESSLabConstants`:

```julia-repl
julia> registry_summary([CHESSCore, MyLab]).reagents
1-element Vector{NamedTuple}:
 (module_ = Main.MyLab, name = :ethanol, type = Liquid, molecular_weight = 46.07 g mol⁻¹, density = 0.789 g mL⁻¹, pubchemid = 702)
```

Called with no arguments, `registry_summary()` covers every lab module ever registered globally --
unlike the string macros, it isn't restricted to modules visible to the caller. `organisms`,
`locations`, `attributes`, and `reads` are read straight from the always-current central registries;
`reagents`, `chemicals`, and `stocks` are found instead by scanning each module's names and
filtering by type, since reagents/chemicals have no central registry at all, and `stock_recipes`
only reflects stocks explicitly registered via `@stock`.

[Database Architecture](db-architecture.md) covers what happens next: what CHESSDatabase does with
the locations and stocks built from these registered constants.
