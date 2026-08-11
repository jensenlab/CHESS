# Pourfecto.jl

```@meta
CurrentModule = Pourfecto
```

[Pourfecto.jl](https://github.com/jensenlab/Pourfecto) is a julia package for generating automated liquid-handling workflows by turning experimental goals into executable liquid-handling protocols. It separates protocol design into two stages: planning, which determines how available reagents should be combined to produce the desired target solutions, and scheduling, which decides how those transfers should be carried out on specific liquid-handling instruments. Pourfecto accounts for reagent availability, stock quantities, target compositions, labware constraints, instrument capabilities, deck space, and allowable transfer volumes to produce optimized workflows.

Pourfecto builds directly on [CHESSCore](https://jensenlab.github.io/CHESS/dev/)'s reagent, stock, and labware/location model — see the [CHESS documentation](https://jensenlab.github.io/CHESS/dev/) for the underlying data model this package plans and schedules over.

!!! note "Prerequisite reading"
    Pourfecto's manual assumes familiarity with CHESSCore's
    [Locations](https://jensenlab.github.io/CHESS/dev/manual/core-concepts/),
    [Movement & Occupancy](https://jensenlab.github.io/CHESS/dev/manual/movement/),
    [Reagents & Chemicals](https://jensenlab.github.io/CHESS/dev/manual/reagents-chemicals/), and
    [Stocks](https://jensenlab.github.io/CHESS/dev/manual/stocks/) chapters. The ledger/database
    chapters (Committing & Uploading, The Ledger, Caching & Repair, and so on) aren't needed to use
    Pourfecto.

## Installation

Pourfecto is not published to a package registry -- it lives in the [CHESS](https://github.com/jensenlab/CHESS) monorepo as a Julia `[workspace]` member alongside `CHESSCore`, `CHESSDatabase`, and `CHESSLabConstants`, resolving those dependencies via local paths. Pourfecto must be used from a local clone of CHESS:

```julia
# git clone https://github.com/jensenlab/CHESS && cd CHESS
using Pkg
Pkg.activate("Pourfecto")
Pkg.instantiate()
using Pourfecto
```

!!! note 
    By default, Pourfecto's planning and scheduling algorithms use [Gurobi](https://www.gurobi.com) (licenses are free for academic users as of the time of writing), but a Gurobi license isn't required — any JuMP-compatible optimizer can be used instead via the `optimizer` keyword. See [Choosing a solver](@ref pourfecto_choosing_a_solver) for the free alternatives Pourfecto is tested against and their tradeoffs.

---




