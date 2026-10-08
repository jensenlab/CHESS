# [Defining a New Instrument](@id pourfecto_new_instrument)

```@meta
CurrentModule = Pourfecto
```

This page is for building support for a liquid handler that Pourfecto does not already include,
typically in an instrument definition kept in a separate package. Forking Pourfecto is not
necessary. A new [`InstrumentModel`](@ref) subtype defined in the new package, together with methods
added to the exported generic functions of Pourfecto (`Mask`, `write_instrument_files`,
`packing_greedy`, and others), is enough. Julia's multiple dispatch allows a package to add a method
to a function from another package when one of the argument types belongs to the new package.

A complete instrument definition has four parts:

1. A data model: an [`InstrumentModel`](@ref) subtype, a [`Head`](@ref), a `Deck`, and a
   [`Configuration`](@ref). [Configurations](@ref pourfecto_configurations) describes them.
2. A [`Mask`](@ref) method, which defines the valid `(well, position, channel)` combinations.
3. Compiler hooks, which turn a solved plan into files that the instrument control software can run.
4. Registration and tests, which make the instrument discoverable and verify it.

The Cobra instrument is a worked example of all four parts. Its source is
`Pourfecto/src/instruments/Cobra.jl`, and it is a good template to read from start to finish. Cobra
is specific to the Jensen Lab: it has a hardcoded lab file path, a lab-specific plate-name mapping,
and a vendor XML format tied to the SoftLinx installation of the lab. It will not run correctly in
another lab without changes. The caveats are documented on the `Cobra` type.

## Masks

A [`Mask`](@ref) records, for a `(Head, Labware)` pair, which combinations of well, head position,
and channel are physically valid for aspirating and dispensing. If an instrument has no `Mask`
method, the default always returns `false`. This is not an error. It means the instrument cannot
aspirate or dispense from anything yet.

The [`Mask`](@ref) entry in the [API Reference](@ref) gives its fields.

### Mask rules

The recommended way to define a mask is a table of [`MaskRule`](@ref)s, one for each combination of
labware kinds, direction, and geometry archetype. [`build_mask_from_rules`](@ref) turns the table
into a mask. Deriving both the mask and the deck admissibility (the `labware` field of
`ConstrainedPosition`) from one table keeps them consistent, and the table is what the
[conformance test kit](@ref pourfecto_testing_instruments) uses for automatic coverage testing.
[`MaskRule`](@ref), [`build_mask_from_rules`](@ref), and [`mask_rules_for`](@ref) are described in
the [API Reference](@ref).

### Example: mask rules for Cobra

```julia
const cobra_mask_rules = [
    MaskRule(Set([:WP96,:DeepWP96]), :aspirate, :sliding_window, (;)),
    MaskRule(Set([:WP96,:DeepWP96]), :dispense, :sliding_window, (;v_out=true)), # the mask can exit the plate vertically
    MaskRule(Set([:WP384]), :aspirate, :sliding_window, (;v_spacing=2)),
    MaskRule(Set([:WP384]), :dispense, :sliding_window, (;v_spacing=2,v_out=true)),
]
const cobra_wellplate_kinds = union((r.kinds for r in cobra_mask_rules)...)
```

The Cobra head aspirates from and dispenses into `:WP96` and `:DeepWP96` plates with the
`:sliding_window` archetype, in which the channel grid of the head slides across the well grid of the
labware. Dispensing can also overhang the plate edge vertically (`v_out=true`). `:WP384` plates use
the same archetype with `v_spacing=2`, because the 4-channel head of the Cobra touches only every
other row at the finer pitch of a 384-well plate. `cobra_wellplate_kinds`, the set of labware kinds
that the deck positions of the Cobra admit, is derived from the same table with `union`, so the deck
and the mask stay consistent.

Two lines connect the rule table to the instrument:

```julia
Mask(h::Head{Cobra}, l::Labware) = build_mask_from_rules(h, l, cobra_mask_rules)
mask_rules_for(::Configuration{Cobra}) = cobra_mask_rules
```

The first line is required for scheduling. The second is optional but recommended. Without it, the
mask-coverage check of the conformance test kit skips the instrument and shows a warning. A `Mask`
method without a rule table is not wrong, only unverified.

An instrument whose geometry does not fit `:sliding_window` or `:blanket` can call the lower-level
functions directly or use a custom predicate. The fields of `Mask` (`asp`, `disp`, `asp_positions`,
`disp_positions`) are exported accessors for this purpose.

```@docs
sliding_window_mask
blanket_mask
effective_head_size
```

### Asymmetric aspirate and dispense topology

Most instruments aspirate and dispense with the same channel topology, but some do not. The 8 pistons
of the Tempest share one intake channel while aspirating and fan out to 8 independent nozzles while
dispensing. For these instruments, build the `Head` with the `channel_routing` keyword instead of
the three-argument constructor:

```julia
Head{Tempest}(pistons, aspirate_channels, aspirate_mask, dispense_channels, dispense_mask; channel_routing)
```

The [`Head`](@ref) docstring describes `channel_routing`. The Tempest and Nimbus definitions in
`Pourfecto/src/instruments/` are worked examples.

## The compiler pipeline

[`compile`](@ref) turns a solved `Pourcast` into protocol files on disk for each instrument
configuration. [Compiling Protocols](@ref pourfecto_compiling) describes running `compile` and
reading its output. This section describes the same pipeline for someone extending it.

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

`write_instrument_files` is the required extension point for a custom protocol file format:

```julia
write_instrument_files(directory::AbstractString, design::DataFrame,
                        source::Vector{<:Labware}, target::Vector{<:Labware},
                        config::Configuration{YourInstrument},
                        slotting::SlottingDict = slotting_greedy(vcat(source,target), config);
                        kwargs...) -> Nothing
```

Without an override, a generic fallback writes a plain `transfer_table.csv`. An instrument with a
`Configuration` and a `Mask` and no custom compiler code therefore already produces valid, generic
output. Instrument-specific formats, such as the SoftLinx XML of the Cobra, the `.dl.txt` file of the
Mantis, and the `.mdl.txt` file of the Tempest, are optional and are dispatched on
`Configuration{YourInstrument}`.

Existing instruments often move work into a private helper such as `convert_design` inside their
`write_instrument_files` method. The name is a local convention, and Pourfecto does not dispatch on
it.

### packing_greedy

Most instruments do not need to override [`packing_greedy`](@ref). It works with
[`slotting_greedy`](@ref) to handle typical bin-packing slotting. Cobra overrides it because it has
two deck slots and needs exactly one protocol for each source and target pairing, so that every
change of labware pairing starts a new protocol. Override `packing_greedy` only for similarly
unusual slotting constraints.

```@docs
write_instrument_files
packing_greedy
slotting_greedy
```

## Registering an instrument

```@docs
register_instrument!
```

Call `register_instrument!` once for each `Configuration`, usually at the top level of the package
module right after the `Configuration` is built. If the settings read `Preferences.jl` or other
state at load time, such as the lab-specific file path that `cobra_path` supplies (see
[`set_cobra_path!`](@ref)), do so in the `__init__()` function of the package, which runs on every
load.

## [Testing an instrument](@id pourfecto_testing_instruments)

`Pourfecto.TestUtils` is a submodule of reusable conformance checks. The test suite of Pourfecto runs
the same checks on its seven built-in instruments. `using Pourfecto.TestUtils` loads them in another
test suite.

**Tier 1** needs no solver and is safe for any CI:

```julia
using Pourfecto, Pourfecto.TestUtils

@test test_instrument_interface(my_config)
```

It runs `test_mask_coverage`, which checks the `Mask` against the `mask_rules_for` table by brute
force if the table exists, and `test_json_roundtrip`, which checks that the `Configuration` survives
JSON serialization and deserialization.

**Tier 2** needs a real solve:

```julia
pc = pourfecto(source_labware, target_labware, [my_config]; optimizer=SCIP.Optimizer)
test_pourcast_compilation("My Instrument Compilation", pc)
```

It compiles the solved `Pourcast` into a temporary directory and checks that the expected output
structure exists. This verifies that `write_instrument_files` produces files, which the mask and
deck checks do not. The test does not run a solver itself, so one must already be configured. SCIP is
a Pourfecto dependency and works as a free default. [Choosing a solver](@ref pourfecto_choosing_a_solver)
compares SCIP, HiGHS, and Gurobi.

```@docs
Pourfecto.TestUtils.test_instrument_interface
Pourfecto.TestUtils.test_mask_coverage
Pourfecto.TestUtils.test_json_roundtrip
Pourfecto.TestUtils.test_pourcast_compilation
```

## Example: Cobra

`Pourfecto/src/instruments/Cobra.jl` covers all four parts: the piston, head, deck, and settings, a
`MaskRule` table, a `packing_greedy` override, and a `write_instrument_files` implementation that
writes vendor XML. Its module docstring lists which parts are specific to the Jensen Lab and would
change for another lab or another Cobra deployment.
