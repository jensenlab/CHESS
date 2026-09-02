# CHESS.jl

[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://jensenlab.github.io/CHESS/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/dev)
[![CI](https://github.com/jensenlab/CHESS/actions/workflows/CI.yml/badge.svg)](https://github.com/jensenlab/CHESS/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

CHESS.jl is a data framework for recording, reconstructing, and planning the operations of a
laboratory -- automated or otherwise. Rather than storing the *state* of a lab (what's where,
what's in it, how full it is) at each point in time, CHESS records the *operations* that produced
that state -- movements, environmental changes, transfers, and reads -- as a permanent, append-only
ledger, and reconstructs any state on demand by simulating that history. The design is directly
inspired by how chess games are recorded: not as a sequence of board positions, but as a sequence
of moves, replayed by an engine that knows the rules.

This repository is organized into a few functional categories of packages:

### CHESS

The core engine: recording, reconstructing, and looking up lab state.

| Package | Description | Docs |
|---|---|---|
| [`CHESSCore`](CHESSCore) | The "lab engine": `Location`/`Stock`/`Attribute`/`Read` types and the pure, in-memory operations that act on them (`move_into!`, `transfer!`, `set_attribute!`, `record_read!`). | [stable](https://jensenlab.github.io/CHESS/stable/api/core/) / [dev](https://jensenlab.github.io/CHESS/dev/api/core/) |
| [`CHESSDatabase`](CHESSDatabase) | An append-only SQLite-backed history of every operation, plus the reconstruction algorithms that replay it into `CHESSCore` objects on demand. | [stable](https://jensenlab.github.io/CHESS/stable/api/database/) / [dev](https://jensenlab.github.io/CHESS/dev/api/database/) |
| [`CHESSLabConstants`](CHESSLabConstants) | A starter set of registered lab constants (reagents, organisms, location kinds, instruments, standard stock recipes) built on `CHESSCore`'s registration macros -- a template for defining your own lab's constants. | [stable](https://jensenlab.github.io/CHESS/stable/api/labconstants/) / [dev](https://jensenlab.github.io/CHESS/dev/api/labconstants/) |
| `CHESS` | The umbrella package: `@reexport`s `CHESSCore`, `CHESSDatabase`, and `CHESSLabConstants`, plus `Unitful`, so `using CHESS` alone is enough to get everything except packages from the other categories below. | [stable](https://jensenlab.github.io/CHESS/stable) / [dev](https://jensenlab.github.io/CHESS/dev) |
| [`CHESSExperiments`](CHESSExperiments) | The experimental-design layer: `Experiment`/`Factor`/design-matrix types, parsing a design into populated well conditions, and blocking -- independent of `RunMaps`/`PlateMaps`, with `schedule_layout` onto them provided by a package extension. | -- |

### Schedulers

Packages that plan and schedule lab operations against the CHESS engine's data model.

| Package | Description | Docs |
|---|---|---|
| [`Pourfecto`](Pourfecto) | Plans and schedules automated liquid-handling workflows -- turns source stocks, target compositions, labware, and instrument configurations into an executable protocol. See [`Pourfecto/README.md`](Pourfecto/README.md) for its own install/quickstart notes (it has extra solver-license setup CHESS itself doesn't need). | [dev](https://jensenlab.github.io/CHESS/pourfecto/dev/) |
| [`RunMaps`](RunMaps) | Represents and schedules run-graphs -- linked runs, control/duplicate scheduling (greedy and MILP), and JSON round-trip -- pairs naturally with `PlateMaps` for the plate-layout side. | -- |
| [`PlateMaps`](PlateMaps) | Schedules physical plate layouts (which node occupies which well, across one or more plates) from an edge-linked relationship structure -- pairs naturally with `RunMaps` for the run/control side. | [dev](https://jensenlab.github.io/CHESS/platemaps/dev/) |

### Data Processing

Packages for processing and analyzing data recorded through CHESS (e.g. reads and measurements).

| Package | Description | Docs |
|---|---|---|
| [`CHESSParsers`](CHESSParsers) | Parses instrument-exported data files (starting with BioTek plate readers/incubators: Epoch2, Synergy, Cytation, BioSpa) into a `DataFrame`, `CHESSCore.Read`s, or JSON, through a generic, pluggable per-instrument-format interface. | -- |
| [`CHESSProcessing`](CHESSProcessing) | A standard library of composable `Experiment`-processing operations -- `resolve`/`aggregate`/`normalize`/`correct`/`flag`/`merge` -- each appending a `ProcessingRecord` to the experiment's append-only processing log for provenance, so any subset or order can be composed rather than following a fixed pipeline. | -- |

### Visualization

Shared plotting utilities consumed by packages across the other categories.

| Package | Description | Docs |
|---|---|---|
| [`LabwarePlotting`](LabwarePlotting) | Shared grid/plate plotting primitives -- gridlines, lettered rows, shape markers, heatmap overlays, and role-based coloring -- used by `CHESSCore`, `PlateMaps`, `Pourfecto`, and `CHESSProcessing`. | [dev](https://jensenlab.github.io/CHESS/labwareplotting/dev/) |

## Installation

CHESS requires **Julia 1.12 or later** -- the repository ties its packages together as a Julia
`[workspace]`, a Pkg feature introduced in 1.12. The workspace members (`CHESSCore`,
`CHESSDatabase`, `CHESSLabConstants`, `Pourfecto`) resolve each other via local paths, not a
package registry, so **CHESS must be used from a local clone** -- `Pkg.add(url="...")` from another
project will not work (Pkg does not carry a workspace's local path resolution to consumers that
merely add it as a dependency), and none of these packages are published to a registry.

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
