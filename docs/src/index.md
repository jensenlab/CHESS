# CHESS

```@meta
DocTestSetup = :(using CHESS)
```

CHESS is a data framework for recording, reconstructing, and planning the operations of a
laboratory, whether automated or not. CHESS does not store the state of a lab (what is where, what
is in it, how full it is) at each point in time. It records the operations that produced that
state, which are movements, environmental changes, transfers, and reads, in a permanent, append-only
[ledger](manual/ledger.md). Any state is reconstructed on demand by simulating that history. The
design follows the way chess games are recorded: as a sequence of moves, not a sequence of board
states, replayed by an engine that knows the rules.

The repository holds a family of packages, grouped by role.

**The CHESS engine**, documented on this site:

- **[`CHESSCore`](api/core.md)** is the lab engine. It defines the `Location`, `Stock`,
  `Attribute`, and `Read` types and the in-memory operations on them: `move_into!`, `transfer!`,
  `set_attribute!`, and `record_read!`.
- **[`CHESSDatabase`](api/database.md)** keeps an append-only SQLite history of every operation. Its
  reconstruction algorithms replay the history into `CHESSCore` objects on demand.
- **[`CHESSLabConstants`](api/labconstants.md)** is a starter set of registered lab constants:
  reagents, organisms, location kinds, instruments, and standard stock recipes. It is built with the
  registration macros of `CHESSCore` and can serve as a template for the constants of another lab.
- **`CHESS`** is the umbrella package. It re-exports `CHESSCore`, `CHESSDatabase`,
  `CHESSLabConstants`, and `Unitful`, so loading `CHESS` loads all of them.
- **[`CHESSParsers`](api/parsers.md)** parses instrument export files into a `DataFrame`, `CHESSCore`
  reads, or JSON. `CHESS` does not re-export it, so it is loaded separately.

**Schedulers**, which plan lab operations against the CHESS data model:

- **[`Pourfecto`](https://jensenlab.github.io/CHESS/pourfecto/dev/)** plans and schedules automated
  liquid-handling workflows.
- **[`PlateMaps`](https://jensenlab.github.io/CHESS/platemaps/dev/)** schedules physical plate
  layouts.
- **[`RunMaps`](manual/runmaps.md)** represents and schedules linked runs, controls, and
  duplicates.

**Experiments, data processing, and plotting:**

- **[`CHESSExperiments`](manual/experiments.md)** describes experimental designs: factors, design
  matrices, and blocking.
- **[`CHESSProcessing`](manual/processing.md)** provides composable processing operations on
  recorded experiment data.
- **[`LabwarePlotting`](https://jensenlab.github.io/CHESS/labwareplotting/dev/)** provides shared
  plate and grid plotting functions.

## Installation

CHESS requires **Julia 1.12 or later**. The repository is a Julia workspace, a feature of the
package manager that was introduced in 1.12, and its packages find each other through local paths.
None of the packages is published to a registry. CHESS must therefore be used from a local clone.
Adding it to another project from its URL does not work, because the package manager does not carry
the local paths of a workspace over to a project that depends on it.

Clone the repository and instantiate its environment:

```bash
git clone https://github.com/jensenlab/CHESS
cd CHESS
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Instantiating installs every package in the workspace from its local path, together with their
dependencies. To start a session, run `julia --project=.` in the clone. To work with a package
other than CHESS, such as Pourfecto, set `--project` to the directory of that package instead.

## Where to go next

- The **[Quick Start](quickstart.md)** builds a small lab and reads an inherited temperature.
- The **[Tutorial](tutorial.md)** follows one experiment from setup to reconstruction and uses each
  part of CHESS once.
- The **Manual** describes the core concepts of CHESS in the order that they build on each other,
  starting with [Locations](manual/core-concepts.md).
- The **[API Reference](api/core.md)** lists every documented function, macro, and type of
  `CHESSCore`, `CHESSDatabase`, `CHESSLabConstants`, and `CHESSParsers`.


