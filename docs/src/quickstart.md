# Quick Start

```@meta
DocTestSetup = :(using CHESS)
```

This page builds a small lab, sets its temperature, fills a well, and reads the temperature that the
well inherits. It assumes that CHESS is installed, as described under
[Installation](index.md#Installation). The [Tutorial](tutorial.md) describes a full experiment.

## Build a lab

[`build_location`](@ref) creates a location from a registered kind and a name. CHESS already
includes the kinds `Room` and `WP96`, a 96-well plate. [`move_into!`](@ref) places the plate in the
room:

```jldoctest quickstart
julia> using CHESS

julia> room = build_location(loc"Room", "Main Room");

julia> plate = build_location(loc"WP96", "Plate 1");

julia> move_into!(room, plate)
```

## Set the environment and fill a well

[`set_attribute!`](@ref) sets the temperature of the room. [`deposit!`](@ref) adds 100 µL of water
to well A1 of the plate:

```jldoctest quickstart
julia> set_attribute!(room, attr"Temperature"(25u"°C"))

julia> deposit!(plate["A1"], 100u"µL" * rgt"water")
```

## Read the inherited environment

A location inherits the attributes of its parent, so the well has the temperature of the room:

```jldoctest quickstart
julia> environment(plate["A1"])[:Temperature]
25.0 °C
```

[Locations](manual/core-concepts.md) describes the objects used here, and
[Environmental Attributes & Inheritance](manual/attributes.md) describes inheritance.
