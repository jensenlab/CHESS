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
given:

```
open_slots = every (position, slot) pair on config's deck
dedupe labware by name (a plate used as both source and target only needs one slot)

for each unique piece of labware:
    if it can't be placed on this deck at all: error
    scan open_slots in order, take the first slot that admits this labware
    if a slot was found: remove it from open_slots
    else: add this labware to not_placed

map each duplicate labware back onto its counterpart's slot

return the labware -> (position, slot) mapping
```

`packing_greedy` calls `slotting_greedy` as a subroutine, peeling off whichever pairings each layout
happens to satisfy until none are left:

```
remaining = all (source, target) pairings that must be co-slotted
layouts = []

while remaining is not empty:
    layout = slotting_greedy(labware from remaining, config)
    covered = pairings in remaining where both source and target got a slot in layout
    if covered is empty: error, no progress possible
    layouts += layout
    remaining -= covered

return layouts
```

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
