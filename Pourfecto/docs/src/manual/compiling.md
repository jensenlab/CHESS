# [Compiling Pourcasts](@id pourfecto_compiling)

```@meta
CurrentModule = Pourfecto
```

Once a [`Pourcast`](@ref pourfecto_pourcasts) has been solved, [`compile`](@ref) turns it into one or
more protocol folders on disk -- files an actual liquid handler can run. This page covers what
`compile` does, why slotting is part of that process, and what ends up in the output directory.

---

## Running `compile`

```julia
compile(directory, pc)
```

`compile` is also called automatically when you run `pourfecto` with a target directory:

```julia
pc = pourfecto(directory, source_labware, target_labware, configs)
```

so most users never call `compile` directly -- it's documented here for when you want to compile an
already-solved `Pourcast` again (e.g. with a different `packing_method`), or want to understand the
output layout.

```@docs
compile
```

---

## Why slotting is needed

A [`Configuration`](@ref)'s [`Deck`](@ref) has a fixed number of slots, and not every piece of labware
can sit in every slot -- see [Configurations](@ref pourfecto_configurations) for how deck positions and
their admissible labware are defined. Before a solved design can be written out as a protocol, every
piece of labware involved needs an actual `(DeckPosition, slot)` assignment that respects those
constraints. Finding that assignment is what the slotting functions in this page do.

---

## The pipeline, stage by stage

```
pourfecto(...) solves a Pourcast
  -> compile(directory, pourcast)
       -> per Configuration: slotting_requirements determines which source/target labware
          pairs must be co-slotted
       -> packing_method (default packing_greedy) produces one or more SlottingDict layouts
       -> for each layout: write_instrument_files(protocol_directory, design, sources, targets,
          config, slotting; kwargs...)
```

For each `Configuration` used in the `Pourcast`, `compile` first figures out which source/target
labware pairs actually need to be accessible on the deck at the same time -- a pair only matters if the
solved plan transfers a nonzero volume between them on that configuration. Not every pairing can
necessarily share a single deck layout (a deck only has so many slots), so `compile` calls a
`packing_method` -- [`packing_greedy`](@ref) by default -- to split the required pairings across one or
more layouts. Each layout becomes its own protocol folder.

This is the same pipeline documented from an instrument author's point of view in
["The compiler pipeline"](@ref pourfecto_new_instrument) on the
[Defining a New Instrument](@ref pourfecto_new_instrument) page -- read that page if you need to
override `write_instrument_files` or `packing_greedy` for a new instrument. This page instead covers
what happens with the built-in instruments and how to read the results.

---

## `SlottingDict` and inspecting a layout

Each layout is a [`SlottingDict`](@ref) -- a mapping from each piece of labware to the
`(DeckPosition, slot)` it was assigned. Layouts are produced by [`slotting_greedy`](@ref) (assigns one
set of labware to open slots) and [`packing_greedy`](@ref) (calls `slotting_greedy` repeatedly until
every required pairing is covered).

`slotting_greedy` assigns labware to slots first-come-first-served, in the order the labware was
given. It first collects every open `(position, slot)` pair on the deck, then deduplicates the labware
by name -- a plate used as both a source and a target only needs one slot. For each unique piece of
labware, it scans the open slots in order and claims the first one that admits it, removing that slot
from further consideration; if a piece of labware can't be placed on the deck at all, it raises an
error immediately, while labware that's placeable in principle but finds no open slot left is simply
set aside rather than erroring. Finally, any duplicate labware is mapped back onto whichever slot its
counterpart ended up in, so the same physical plate isn't assigned two different slots.

`packing_greedy` calls `slotting_greedy` as a subroutine, peeling off whichever pairings each layout
happens to satisfy until none are left. Starting from every `(source, target)` pairing that must be
co-slotted, it repeatedly runs `slotting_greedy` over the labware that's still unresolved, checks which
pairings that layout actually covers (both members ended up with a slot), and keeps that layout as one
protocol before continuing with only the leftover pairings. If a pass covers nothing new, it raises an
error rather than looping forever; otherwise it stops once every pairing has been covered by some
layout.

To inspect a layout as a table rather than a raw `Dict`, use `slottingdict_to_df`:

```julia
using DataFrames

df = slottingdict_to_df(slotting)
```

```@docs
slottingdict_to_df
```

---

## Output files

`compile` writes, once per call:

| File | Contents |
|---|---|
| `pourcast.json` | The compiled `Pourcast`, serialized (see [Serializing Pourcasts](@ref pourfecto_pourcasts)) |
| `target_plate_images/<name>.png` | A well heatmap for each target plate |

and, inside each `<config_type>/<protocol_name>/` folder (one per generated layout):

| File | Contents |
|---|---|
| instrument-specific protocol file(s) | Written by that instrument's `write_instrument_files` method (e.g. Cobra's SoftLinx XML, Mantis's `.dl.txt`); a generic `transfer_table.csv` if the instrument hasn't customized this |
| `loading_table.csv` | The layout's `SlottingDict`, as written by `slottingdict_to_df` |
| `loading_instructions.png` | A diagram of the deck with labware placed per the layout, from `plot_slotting` |

```@docs
plot_slotting
```

---

## Nimbus: one-to-many aspirate/dispense batching

Unlike the generic one-transfer-per-row fallback, the Nimbus's `write_instrument_files` batches
multiple dispenses under a single aspirate whenever they fit within the channel's capacity,
rather than aspirating once per destination well. Its protocol CSV uses a unified action-row
schema:

| Column | Meaning |
|---|---|
| `Labware ID`, `Labware Position ID` | The labware/position acted on by this row |
| `Volume (uL)` | The volume aspirated, dispensed, or blown out by this row, rounded to `volume_precision` decimal places (default 1) |
| `Action` | `"Aspirate"`, `"Dispense"`, or `"Blowout"` |
| `Change Tip Before` | `1` on an aspirate row that should be preceded by a tip change; always `0` for `Dispense`/`Blowout` rows |

An aspirate row is always immediately followed by the rows it feeds -- its dispenses, and (see
below) a trailing blowout when one applies -- whose volumes sum to the aspirate's volume
*exactly* at the rounded precision, not merely approximately: the last value in each cycle absorbs
whatever rounding remainder is needed, rather than every value being rounded independently, which
can otherwise leave a hairline float residual (e.g. `-1.42e-14`) that a strict downstream
`available >= requested` check on the instrument side rejects. Which destinations get grouped into
the same aspirate is decided by a distance-aware greedy bin-packing pass -- spatially nearby
destinations on the target plate are preferred, subject to the channel's capacity -- and a
transfer larger than capacity is split across multiple aspirates, with any remainder free to share
a batch with other destinations.

### Dead-volume Blowout (opt-in, not yet physically validated)

Draining a tip to exactly its computed zero is fragile against real pipetting tolerances, since
tips in a protocol are frequently reused across several re-aspirate cycles without a tip change.
Passing `insert_blowouts=true` inserts a `Blowout` row -- draining a fixed `dead_volume_buffer` to
a `waste_target` -- immediately after any batch that's followed by a re-aspirate under the same
tip (no batch immediately followed by an actual tip change, and never the very last batch, gets
one). That batch's own aspirate volume is then sized to cover its dispenses *plus* the buffer
(the blowout is the last value in its cycle, so it absorbs the rounding remainder) -- batch
formation reserves `capacity - dead_volume_buffer` of headroom for every batch in this mode to
keep that sum within the channel's true capacity.

```julia
write_instrument_files(directory, design, source, target, configurations["nimbus"];
    insert_blowouts=true, waste_target=("LiquidWaste_0001", "1"), dead_volume_buffer=20.0)
```

`waste_target` (a `(labware id, position)` tuple) and a positive `dead_volume_buffer` (in µL, less
than the channel's capacity) are required when `insert_blowouts=true` -- there's no built-in
default, since real values are lab/deck-specific.

!!! warning
    This path is opt-in and defaults to `false`: it changes no existing behavior unless
    explicitly enabled. It has not yet been validated end-to-end against real instrument hardware
    -- see `csv_generation_refactor_notes.md`'s Bug 3 section for the open items (confirming the
    waste labware's real deck position, the corresponding instrument-side `.hsl` support, and a
    RunControl smoke test).

`write_instrument_files(..., config::Configuration{Nimbus}, ...)` accepts a `batch_ordering`
keyword controlling how dispenses *within* a batch are sequenced:

- `:greedy` (default) -- a fast nearest-neighbor tour.
- `:exact` -- the minimum-total-travel-distance ordering, found by brute-force search. Only
  tractable for small batches (capped at 8 items; larger batches fall back to `:greedy` with a
  warning), since batch *membership* is fixed by the greedy packing step -- only the ordering
  within an already-formed batch is solved exactly.

```julia
pourfecto(directory, source_labware, target_labware, ["nimbus"]; batch_ordering=:exact)
```

is enough to try the exact ordering; `compile(directory, pourcast; batch_ordering=:exact)` works
the same way against an already-solved `Pourcast`, letting you compare `:greedy` against `:exact`
on the same design before deciding which to use by default.

!!! note
    `"max_tip_use"` in the Nimbus `Configuration`'s settings now counts aspirate **batches**, not
    individual dispense shots -- since one aspirate now typically feeds several dispenses, the
    same numeric setting forces a tip refresh less often in wall-clock/shot terms than it used to.
    Tip changes are still always forced on a source change, regardless of this setting.

---

## Troubleshooting

### `labware type ... cannot be placed on a ... deck`

This means a piece of labware in the `Pourcast` can't be placed on the given configuration's deck at
all -- no position accepts it, regardless of open slots. Check that piece's labware kind against the
deck positions' admissible labware in [Configurations](@ref pourfecto_configurations).

### `unsolvable packing arrangement`

`packing_greedy` raises this when it can't make progress covering the remaining required pairings --
some set of labware that must be co-slotted doesn't fit together on the deck no matter how it's
arranged. Check the configuration's total slot count against how many pieces of labware are ever
required together at once; a deck with too few slots for a mandatory group of labware can't be
resolved by any `packing_method`.

---
