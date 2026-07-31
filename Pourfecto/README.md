# Pourfecto.jl

[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://jensenlab.github.io/CHESS/pourfecto/dev/)


**Pourfecto.jl** is a Julia package for planning and scheduling automated liquid handling workflows.

Pourfecto turns source reagents, target formulations, labware, and instrument configurations into a solved **Pourcast**: a structured result object containing planned transfers, scheduled flows, model metadata, and solution-quality information.

Pourfecto is designed for workflows where scientists and engineers need to translate experimental goals into liquid-handler-compatible protocols.

---

## What Pourfecto does

Pourfecto separates liquid handling protocol design into two stages:

1. **Planning**  
   Determines how available source stocks should be combined to produce desired target stocks.

2. **Scheduling**  
   Determines how those planned transfers can be executed using available labware and liquid-handling instrument configurations.

Pourfecto reasons over many of the following questions as it creates protocols: 

- Which source stocks should be transferred into each target?
- What transfer volumes are required?
- Are the requested target compositions feasible?
- Which liquid-handler configuration should perform each operation?
- Which wells and labware are involved?
- What is the expected composition of each planned target?
- Can the resulting workflow be compiled for downstream execution?

Pourfecto's goal is to abstract all of the logistical details of converting designs into protocols. 

---


## Installation

Pourfecto is not published to a package registry — it lives in the [CHESS](https://github.com/jensenlab/CHESS) monorepo as a Julia `[workspace]` member alongside `CHESSCore`, `CHESSDatabase`, and `CHESSLabConstants`, resolving those dependencies via local paths. Pourfecto must be used from a local clone of CHESS:

```julia
# git clone https://github.com/jensenlab/CHESS && cd CHESS
using Pkg
Pkg.activate("Pourfecto")
Pkg.instantiate()
using Pourfecto
```

!!! note 
    Pourfecto's default optimizer, Gurobi, requires an active [Gurobi](https://www.gurobi.com) license (free for academic users as of the time of writing). See [Solver requirements](#solver-requirements) below for license-free alternatives.

---

Most workflows also utilize the [CHESSCore](https://jensenlab.github.io/CHESS/dev/), [Unitful](https://github.com/JuliaPhysics/Unitful.jl), and [DataFrames](https://github.com/JuliaData/DataFrames.jl) Julia packages.

```julia
using CHESSCore
using Unitful
using DataFrames
```

---

## Solver requirements

Pourfecto builds combinatorial optimization models with JuMP. By default it solves with Gurobi, but any JuMP-compatible solver can be used instead via the `optimizer` keyword — including the free, open-source `HiGHS` and `SCIP`, both already Pourfecto dependencies:

```julia
using HiGHS

pourfecto(sources, targets, configs; optimizer=HiGHS.Optimizer)
```

If using the default Gurobi optimizer, you will need a working Gurobi installation and license available to Julia. A minimal solver check:

```julia
using Gurobi
using JuMP

model = Model(Gurobi.Optimizer)
```

If this fails, configure Gurobi, or pass `optimizer=HiGHS.Optimizer` (or `SCIP.Optimizer`) to avoid the Gurobi dependency entirely.

---


## Citation

If you use Pourfecto in your work, please cite the associated preprint:


David BM and Jensen PA.

[**Planning and scheduling biological experiments across multiple liquid handling robots**](https://www.biorxiv.org/content/10.64898/2025.12.26.696584v1)

*bioRxiv*.2025; [doi:10.64898/2025.12.26.696584](https://www.biorxiv.org/content/10.64898/2025.12.26.696584v1)


---

## License

See [`LICENSE`](LICENSE) for license information.

---
