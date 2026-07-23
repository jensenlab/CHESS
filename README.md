# CHESS

[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://jensenlab.github.io/CHESS/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/dev)
[![CI](https://github.com/jensenlab/CHESS/actions/workflows/CI.yml/badge.svg)](https://github.com/jensenlab/CHESS/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

CHESS is a data framework for recording, reconstructing, and planning the operations of a
laboratory -- automated or otherwise. Rather than storing the *state* of a lab (what's where,
what's in it, how full it is) at each point in time, CHESS records the *operations* that produced
that state -- movements, environmental changes, transfers, and reads -- as a permanent, append-only
ledger, and reconstructs any state on demand by simulating that history. The design is directly
inspired by how chess games are recorded: not as a sequence of board positions, but as a sequence
of moves, replayed by an engine that knows the rules.

This mirrors the shape of the CHESS package family itself:

- **[`CHESSCore`](https://jensenlab.github.io/CHESS/stable/api/core/)** -- the "lab engine":
  `Location`/`Stock`/`Attribute`/`Read` types and the pure, in-memory operations that act on them
  (`move_into!`, `transfer!`, `set_attribute!`, `record_read!`).
- **[`CHESSDatabase`](https://jensenlab.github.io/CHESS/stable/api/database/)** -- an append-only
  SQLite-backed history of every operation, plus the reconstruction algorithms that replay it into
  `CHESSCore` objects on demand.
- **[`CHESSLabConstants`](https://jensenlab.github.io/CHESS/stable/api/labconstants/)** -- a
  starter set of registered lab constants (reagents, organisms, location kinds, instruments,
  standard stock recipes) built on `CHESSCore`'s registration macros -- a template for defining
  your own lab's constants.
- **`CHESS`** -- the umbrella package: `@reexport`s all three, plus `Unitful`, so `using CHESS`
  alone is enough to get everything.

## Installation

CHESS requires **Julia 1.12 or later** -- the repository ties its four packages together as a
Julia `[workspace]`, a Pkg feature introduced in 1.12.

To use CHESS as a dependency:
```julia
using Pkg
Pkg.add(url="https://github.com/jensenlab/CHESS")
```

For local development:
```julia
# git clone https://github.com/jensenlab/CHESS && cd CHESS
using Pkg
Pkg.instantiate()
```

## Quickstart

```julia
using CHESS

room = GenericLocation(nothing, "Main Room", Room)
plate = build_location(WP96, "Plate 1")
move_into!(room, plate)

set_attribute!(room, Temperature(25u"°C"))
deposit!(plate["A1"], 100u"µL" * water)

environment(plate["A1"])[:Temperature] # inherited from room -> plate -> well
```

## Documentation

The full manual and API reference are published at
**[http://jensenlab.net/CHESS](https://jensenlab.net/CHESS)**. The manual works through
CHESS's core concepts in the order they build on one another, starting with
[Locations](https://jensenlab.github.io/CHESS/stable/manual/core-concepts/).

## License

CHESS is licensed under the [MIT License](LICENSE).
