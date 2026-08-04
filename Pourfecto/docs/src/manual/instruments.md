# [Defining a New Instrument](@id pourfecto_new_instrument)

```@meta
CurrentModule = Pourfecto
```

This page is for anyone building support for a liquid handler Pourfecto doesn't already know about --
typically a different lab, writing an instrument definition in **their own package**. You do not need
to fork Pourfecto. Everything below is achievable with `using Pourfecto` and Julia's multiple
dispatch: you define a new [`InstrumentModel`](@ref) subtype in your own module, then add methods to
Pourfecto's exported generic functions (`Mask`, `write_instrument_files`, `packing_greedy`, ...) --
multiple dispatch lets you add a method to a function defined in another package, as long as one of
the method's argument types is your own.

A complete instrument definition has four pieces:

1. A data model -- [`InstrumentModel`](@ref) subtype, [`Head`](@ref), `Deck`, and
   [`Configuration`](@ref). Covered in [Configurations](@ref pourfecto_configurations); not repeated
   here.
2. A [`Mask`](@ref) method -- which (well, position, channel) combinations are actually valid. Covered
   below.
3. Compiler hooks -- how a solved plan turns into files your instrument's control software can run.
   Covered below.
4. Registration and tests -- making your instrument discoverable and verifying it's correct. Covered
   below.

Cobra (`Pourfecto/src/instruments/Cobra.jl`) is Pourfecto's own worked example of all four pieces
together -- read it end to end as a template. It is **Jensen-Lab-specific** (hardcoded lab file path,
lab-specific plate-name mapping, and a vendor XML format tied to that lab's SoftLinx installation) and
will not run correctly unmodified in another lab -- see the caveats documented on the `Cobra` type
itself. That's expected: it's a template to adapt, not a drop-in default.

---

## The Mask/MaskRule system

A [`Mask`](@ref) records, for a given `(Head, Labware)` pairing, which combinations of well, head
position, and channel are physically valid for aspirating and dispensing. If you don't define a
`Mask` method for your instrument, the default is a trivial always-`false` predicate -- this is *not*
an error, it just means your instrument can't actually aspirate or dispense from anything yet.

See the [`Mask`](@ref) entry in the [API Reference](@ref) for its exact field layout.

### The declarative pattern: MaskRule

Rather than hand-writing predicate closures, the recommended approach is a declarative table of
[`MaskRule`](@ref)s -- one entry per (labware kind set, direction, geometry archetype) combination --
consumed by [`build_mask_from_rules`](@ref). This keeps your `Mask` logic and your deck admissibility
(`ConstrainedPosition`'s `labware` field) derived from a single source of truth, and is what plugs
into the [conformance test kit](@ref pourfecto_testing_instruments) for automatic coverage testing.
See [`MaskRule`](@ref), [`build_mask_from_rules`](@ref), and [`mask_rules_for`](@ref) in the
[API Reference](@ref) for exact signatures.

### Worked example: Cobra's mask rules

```julia
const cobra_mask_rules = [
    MaskRule(Set([:WP96,:DeepWP96]), :aspirate, :sliding_window, (;)),
    MaskRule(Set([:WP96,:DeepWP96]), :dispense, :sliding_window, (;v_out=true)), # the mask can exit the plate vertically
    MaskRule(Set([:WP384]), :aspirate, :sliding_window, (;v_spacing=2)),
    MaskRule(Set([:WP384]), :dispense, :sliding_window, (;v_spacing=2,v_out=true)),
]
const cobra_wellplate_kinds = union((r.kinds for r in cobra_mask_rules)...)
```

Reading this: Cobra's head can aspirate from and dispense into `:WP96`/`:DeepWP96` plates using the
`:sliding_window` archetype (the head's channel grid slides across the labware's well grid); dispense
is additionally allowed to overhang the plate edge vertically (`v_out=true`); `:WP384` plates use the
same archetype but with `v_spacing=2` (Cobra's 4-channel head only touches every other row on a
384-well plate's finer pitch). `cobra_wellplate_kinds` -- the set of labware kinds Cobra's deck
positions admit -- is *derived* from this same table via `union`, so the deck and the mask can never
drift out of sync.

Once you have a rule table, two one-liners wire it into your instrument:

```julia
Mask(h::Head{Cobra}, l::Labware) = build_mask_from_rules(h, l, cobra_mask_rules)
mask_rules_for(::Configuration{Cobra}) = cobra_mask_rules
```

The first is required for scheduling to work at all. The second is optional but strongly
recommended -- without it, the conformance test kit's mask-coverage check silently skips your
instrument (it warns rather than failing, since a `Mask` method with no rule table isn't wrong, just
unverified).

If your instrument's geometry doesn't fit `:sliding_window` or `:blanket`, you can call the lower-level
primitives directly, or write a fully custom predicate -- `Mask`'s fields (`asp`, `disp`,
`asp_positions`, `disp_positions`) are exported accessors for exactly this case.

```@docs
sliding_window_mask
blanket_mask
effective_head_size
```

### Asymmetric aspirate/dispense topology

Most instruments aspirate and dispense with the same channel topology, but some genuinely don't --
Tempest's 8 pistons share one intake channel while aspirating, but fan out to 8 independent nozzles
while dispensing. For these, build your `Head` with the `channel_routing` keyword rather than the
simple 3-argument constructor:

```julia
Head{Tempest}(pistons, aspirate_channels, aspirate_mask, dispense_channels, dispense_mask; channel_routing)
```

See the [`Head`](@ref) docstring for the full explanation of `channel_routing`'s semantics, and
`Pourfecto/src/instruments/Tempest.jl` or `Nimbus.jl` for worked examples.

---

## The compiler pipeline

Once a `Pourcast` is solved, [`compile`](@ref) turns it into protocol files on disk, per instrument
configuration. For the user-facing view of this pipeline -- running `compile` and inspecting its
output -- see [Compiling Protocols](@ref pourfecto_compiling); this section covers the same pipeline
from the perspective of someone extending it for a new instrument.

```
pourfecto(...) solves a Pourcast
  -> compile(directory, pourcast)
       -> per Configuration: slotting_requirements determines which source/target labware
          pairs must be co-slotted
       -> packing_method (default packing_greedy) produces one or more SlottingDict layouts
       -> for each layout: write_instrument_files(protocol_directory, design, sources, targets,
          config, slotting; kwargs...)
```

### write_instrument_files

This is the required extension point for a custom protocol file format:

```julia
write_instrument_files(directory::AbstractString, design::DataFrame,
                        source::Vector{<:Labware}, target::Vector{<:Labware},
                        config::Configuration{YourInstrument},
                        slotting::SlottingDict = slotting_greedy(vcat(source,target), config);
                        kwargs...) -> Nothing
```

If you don't override this, the generic fallback writes a plain `transfer_table.csv` -- so a
brand-new instrument with zero custom compiler code already produces valid (if generic) output the
moment it has a `Configuration` and a `Mask`. Instrument-specific file formats (Cobra's SoftLinx XML,
Mantis's `.dl.txt`, Tempest's `.mdl.txt`) are an optional enhancement layered on top, dispatched on
`Configuration{YourInstrument}`.

You'll often see instrument files delegate to a private helper (e.g. `convert_design`) inside their
own `write_instrument_files` method -- this is just an author-chosen internal naming convention, not
something Pourfecto dispatches on generically. Name your own helpers however you like.

### packing_greedy

Most instruments never need to override this -- the generic [`packing_greedy`](@ref)/
[`slotting_greedy`](@ref) pair handles typical bin-packing-style slotting. Cobra is the one exception:
it only has two deck slots and deliberately wants exactly one protocol per source/target pairing
(to force a fresh protocol whenever the labware pairing changes), so it overrides `packing_greedy` to
loop trivially instead of using the generic bin-packer. Only override this if your instrument has
similarly unusual slotting constraints.

```@docs
write_instrument_files
packing_greedy
slotting_greedy
```

---

## Registering your instrument

```@docs
register_instrument!
```

Call this once per `Configuration` you define -- typically at your package's module top level, right
after building the `Configuration`. If your settings need to read from `Preferences.jl` or other
environment state at load time (e.g. a lab-specific file path, the way Cobra's `cobra_path` works --
see [`set_cobra_path!`](@ref)), do this from your package's `__init__()` instead so it re-evaluates on
every load.

---

## [Testing your instrument](@id pourfecto_testing_instruments)

`Pourfecto.TestUtils` is a submodule of reusable conformance checks -- the same checks Pourfecto's own
test suite runs against its seven built-in instruments. Bring it into your own test suite with
`using Pourfecto.TestUtils`.

**Tier 1 -- no solver required, safe for any CI:**

```julia
using Pourfecto, Pourfecto.TestUtils

@test test_instrument_interface(my_config)
```

This runs `test_mask_coverage` (brute-force-verifies your `Mask` against your `mask_rules_for` table,
if you defined one) and `test_json_roundtrip` (verifies your `Configuration` survives a JSON
serialize/deserialize round trip).

**Tier 2 -- requires a real solve:**

```julia
pc = pourfecto(source_labware, target_labware, [my_config]; optimizer=SCIP.Optimizer)
test_pourcast_compilation("My Instrument Compilation", pc)
```

This compiles the solved `Pourcast` to a temp directory and asserts the expected output structure
exists -- verifying `write_instrument_files` actually produces files, not just that your `Mask`/deck
logic is internally consistent. It doesn't run a solver itself; you need one already configured (SCIP
is already a Pourfecto dependency and works as a free default -- see
[Choosing a solver](@ref pourfecto_choosing_a_solver) for tradeoffs between SCIP, HiGHS, and Gurobi).

```@docs
Pourfecto.TestUtils.test_instrument_interface
Pourfecto.TestUtils.test_mask_coverage
Pourfecto.TestUtils.test_json_roundtrip
Pourfecto.TestUtils.test_pourcast_compilation
```

---

## Full worked example: Cobra

Read `Pourfecto/src/instruments/Cobra.jl` end to end as a template covering all four pieces above --
piston/head/deck/settings, a real `MaskRule` table, a custom `packing_greedy` override, and a full
`write_instrument_files` implementation emitting vendor XML. Its module docstring documents exactly
which parts are Jensen-Lab-specific and would need to change for another lab or another Cobra
deployment.
