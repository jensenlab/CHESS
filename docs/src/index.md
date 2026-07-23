# CHESS

CHESS is a data framework for recording, reconstructing, and planning the operations of a
laboratory -- automated or otherwise. Rather than storing the *state* of a lab (what's where,
what's in it, how full it is) at each point in time, CHESS records the *operations* that produced
that state -- movements, environmental changes, transfers, and reads -- as a permanent, append-only
ledger, and reconstructs any state on demand by simulating that history. The design is directly
inspired by how chess games are recorded: not as a sequence of board positions, but as a sequence
of moves, replayed by an engine that knows the rules.

This mirrors the shape of the CHESS package family itself:

- **[`CHESSCore`](api/core.md)** -- the "lab engine": `Location`/`Stock`/
  `Attribute`/`Read` types and the pure, in-memory operations that act on them (`move_into!`,
  `transfer!`, `set_attribute!`, `record_read!`).
- **[`CHESSDatabase`](api/database.md)** --  an append-only SQLite-backed history of every
  operation, plus the reconstruction algorithms that replay it into `CHESSCore` objects on demand.
- **[`CHESSLabConstants`](api/labconstants.md)** -- a starter set of registered lab constants (reagents, organisms,
  location kinds, instruments, standard stock recipes) built on `CHESSCore`'s registration macros, can serve as a template for defining your own lab's constants.
- **`CHESS`** -- packages everything into a single repository 


## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/.../CHESS") # or Pkg.develop(path="...") for local development
```

## Quickstart

```julia
using CHESS

room = GenericLocation(nothing, "Main Room", Room)
plate = build_location(WP96, "Plate 1")
move_into!(room, plate)

set_attribute!(room, Temperature(25u"°C"))
deposit!(plate["A1"], 100u"µL" * water, 0)

environment(plate["A1"])[:Temperature] # inherited from room -> plate -> well
```

## Where to go next

- The **Manual** works through CHESS's core concepts in the order they build on one another,
  starting with [Locations](manual/core-concepts.md).
- The **[`API Reference`](api/core.md)** is a generated listing of every documented function, macro, and type
  across the three packages.


