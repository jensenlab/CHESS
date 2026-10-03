# [Compiling Pourcasts](@id pourfecto_compiling)

```@meta
CurrentModule = Pourfecto
```

[`compile`](@ref) turns a solved [`Pourcast`](@ref pourfecto_pourcasts) into one or more protocol
folders on disk, containing files that a liquid handler can run. This page describes what `compile`
does, why labware must be assigned to deck slots, and what the output directory contains.

## Running `compile`

```julia
compile(directory, pc)
```

`pourfecto` calls `compile` when it is given a target directory:

```julia
pc = pourfecto(directory, source_labware, target_labware, configs)
```

Calling `compile` directly is useful to compile a solved `Pourcast` again, for example with a
different `packing_method`, or to inspect the output layout.

```@docs
compile
```

## Why labware is slotted

The [`Deck`](@ref) of a [`Configuration`](@ref) has a fixed number of slots, and not every piece of
labware fits in every slot. [Configurations](@ref pourfecto_configurations) describes how deck
positions and their admissible labware are defined. Before a solved design is written as a protocol,
every piece of labware needs a `(DeckPosition, slot)` assignment that respects those constraints.
The slotting functions on this page find that assignment.

## The compile pipeline

```
pourfecto(...) solves a Pourcast
  -> compile(directory, pourcast)
       -> per Configuration: slotting_requirements determines which source/target labware
          pairs must be co-slotted
       -> packing_method (default packing_greedy) produces one or more SlottingDict layouts
       -> for each layout: write_instrument_files(protocol_directory, design, sources, targets,
          config, slotting; kwargs...)
```

For each `Configuration` in the `Pourcast`, `compile` first determines which source and target
labware pairs must be on the deck at the same time. A pair matters only if the solved plan transfers
a nonzero volume between them on that configuration. A deck has a limited number of slots, so not
every pair can share one layout. `compile` calls a `packing_method`, which is
[`packing_greedy`](@ref) by default, to split the pairs across one or more layouts. Each layout
becomes its own protocol folder.

["The compiler pipeline"](@ref pourfecto_new_instrument) on the
[Defining a New Instrument](@ref pourfecto_new_instrument) page describes the same pipeline for
instrument authors who override `write_instrument_files` or `packing_greedy`. This page describes
the built-in instruments and how to read the results.

## Slotting layouts

Each layout is a [`SlottingDict`](@ref), a mapping from each piece of labware to the
`(DeckPosition, slot)` assigned to it. [`slotting_greedy`](@ref) assigns one set of labware to open
slots, and [`packing_greedy`](@ref) calls `slotting_greedy` repeatedly until every required pair is
covered.

`slotting_greedy` assigns labware to slots in the order the labware is given, taking the first open
slot that admits each piece:

1. It collects every open `(position, slot)` pair on the deck.
2. It removes duplicate labware by name, so a plate used as both a source and a target needs one
   slot.
3. For each unique piece of labware, it scans the open slots in order and claims the first one that
   admits it, which removes that slot from consideration.
4. Labware that cannot be placed on the deck at all raises an error. Labware that could be placed
   but finds no open slot is set aside without an error.
5. Duplicate labware is mapped to the slot of its counterpart, so one physical plate never has two
   slots.

`packing_greedy` calls `slotting_greedy` to cover the required pairs one layout at a time:

1. It starts from every `(source, target)` pair that must be co-slotted.
2. It runs `slotting_greedy` over the labware that is still unresolved.
3. It checks which pairs the layout covers, meaning both members received a slot, and keeps the
   layout as one protocol.
4. It repeats with the remaining pairs until none are left. If a pass covers no new pair, it raises
   an error.

`slottingdict_to_df` shows a layout as a table:

```julia
using DataFrames

df = slottingdict_to_df(slotting)
```

```@docs
slottingdict_to_df
```

## Output files

Each call to `compile` writes these files once:

| File | Contents |
|---|---|
| `pourcast.json` | The compiled `Pourcast`, serialized (see [Serializing Pourcasts](@ref pourfecto_pourcasts)) |
| `target_plate_images/<name>.png` | A well heatmap for each target plate |

Each `<config_type>/<protocol_name>/` folder, one per layout, contains:

| File | Contents |
|---|---|
| instrument-specific protocol files | Written by the `write_instrument_files` method of the instrument, such as the SoftLinx XML of the Cobra or the `.dl.txt` file of the Mantis. An instrument without its own method gets a generic `transfer_table.csv`. |
| `loading_table.csv` | The `SlottingDict` of the layout, written by `slottingdict_to_df` |
| `loading_instructions.png` | A diagram of the deck with the labware placed as in the layout, drawn by `plot_slotting` |

```@docs
plot_slotting
```

## Nimbus batching

The generic fallback writes one transfer per row. The `write_instrument_files` method of the Nimbus
instead batches several dispenses under one aspirate when they fit within the channel capacity. Its
protocol CSV has one row per action:

| Column | Meaning |
|---|---|
| `Labware ID`, `Labware Position ID` | The labware and position of the row |
| `Volume (uL)` | The volume aspirated, dispensed, or blown out, rounded to `volume_precision` decimal places (default 1) |
| `Action` | `"Aspirate"`, `"Dispense"`, or `"Blowout"` |
| `Change Tip Before` | `1` on an aspirate row that follows a tip change, and `0` on every `Dispense` and `Blowout` row |

An aspirate row is followed by the rows it feeds: its dispenses and, when one applies, a trailing
blowout. The volumes of those rows sum to the aspirate volume minus a small fixed
**`aspirate_buffer`**, `0.01` µL by default. The sum is exact at the rounded precision. The last
value in each cycle absorbs the rounding remainder, so no value is rounded independently. This
avoids a residual such as `-1.42e-14`, which a strict `available >= requested` check on the
instrument would reject.

`aspirate_buffer` is a deliberate margin and not a rounding artifact. It is a physical safety
allowance against pipetting inaccuracy that could leave a tip short for the last action in a cycle,
and it applies whether or not `insert_blowouts` is used. It is added to the rounded sum without
being rounded again, because a buffer finer than `volume_precision`, like the default `0.01` with
`volume_precision=1`, would round away.

A distance-aware greedy bin-packing pass decides which destinations share an aspirate. It prefers
destinations that are close together on the target plate, within the channel capacity minus
`aspirate_buffer` and a rounding margin of `0.5 * 10^(-volume_precision)`, the most that a raw value
can round up. A transfer larger than the capacity is split across several aspirates, and the
remainder can share a batch with other destinations.

### Reserved waste conical

One slot on the Nimbus deck, `TubeRack50ML_0006` slot 5, is reserved for a Conical50 tube that
holds liquid waste. It is the slot nearest the tip rack and waste area. The reservation is a fixture
of the physical deck, not a per-protocol choice. The `Configuration{Nimbus}` method of
`slotting_greedy` places a waste-conical `Labware` in that slot on every Nimbus compile, whether or
not the protocol uses `insert_blowouts`, and excludes the slot from ordinary source and target
slotting. The other 35 of the 36 `Conical50` rack slots remain available for reagents. The waste
conical appears in `loading_table.csv` and in the deck diagram drawn by `plot_slotting`, so whoever
loads the deck can see it.

### Dead-volume blowout

Tips are often reused across several re-aspirate cycles without a tip change, and draining a tip to
exactly zero is fragile against real pipetting tolerances. **`insert_blowouts` defaults to `true`
and `dead_volume_buffer` defaults to `20.0` µL.** A `Blowout` row drains `dead_volume_buffer` to
`waste_target` after any batch that is followed by a re-aspirate under the same tip. A batch
followed by a tip change gets no blowout, and neither does the last batch. The aspirate volume of
such a batch covers its dispenses plus the buffer, and the blowout, as the last value in its cycle,
absorbs the rounding remainder. Batch formation reserves this headroom in every batch so that the
sum stays within the true channel capacity.

```julia
write_instrument_files(directory, design, source, target, configurations["nimbus"])
# equivalent to explicitly passing insert_blowouts=true, dead_volume_buffer=20.0
```

`waste_target` defaults to the reserved waste conical, so it does not need to be given. A
`(labware id, position)` tuple targets a different location. `insert_blowouts=false` disables
blowouts. A different positive `dead_volume_buffer`, in µL and less than the channel capacity,
suits a different tube or protocol.

!!! warning
    The reserved deck slot is always active, and `insert_blowouts` and `dead_volume_buffer` default
    to on and `20.0`. The blowout path has not yet been validated on instrument hardware. Two items
    remain open: `.hsl` support for the `Blowout` action on the instrument side, and a RunControl
    smoke test.

`write_instrument_files` for a `Configuration{Nimbus}` accepts a `batch_ordering` keyword that sets
how dispenses within a batch are sequenced:

- `:greedy` (default) uses a fast nearest-neighbor tour.
- `:exact` finds the ordering with the minimum total travel distance by brute-force search. It is
  tractable only for small batches. Batches larger than 8 items fall back to `:greedy` with a
  warning. The greedy packing step fixes which dispenses belong to a batch, and only the order
  within a batch is solved exactly.

```julia
pourfecto(directory, source_labware, target_labware, ["nimbus"]; batch_ordering=:exact)
```

tries the exact ordering. `compile(directory, pourcast; batch_ordering=:exact)` does the same for a
solved `Pourcast`, which allows `:greedy` and `:exact` to be compared on one design.

!!! note
    The `"max_tip_use"` setting in the settings of the Nimbus `Configuration` counts aspirate
    **batches**, not individual dispense shots. Because one aspirate typically feeds several
    dispenses, a given value forces a tip refresh less often, measured in shots or wall-clock time.
    A change of source always forces a tip change, whatever this setting is.

## Troubleshooting

### `labware type ... cannot be placed on a ... deck`

A piece of labware in the `Pourcast` cannot be placed on the deck of the configuration, because no
position accepts it, however many slots are open. Compare the labware kind with the admissible
labware of the deck positions in [Configurations](@ref pourfecto_configurations).

### `unsolvable packing arrangement`

`packing_greedy` raises this error when it cannot cover the remaining required pairs. Some set of
labware that must be co-slotted does not fit on the deck in any arrangement. Compare the total slot
count of the configuration with the number of pieces of labware that are required together at once.
A deck with too few slots for a mandatory group cannot be resolved by any `packing_method`.
