# Pourfecto.jl

```@meta
CurrentModule = Pourfecto
```

[Pourfecto.jl](https://github.com/jensenlab/Pourfecto) is a julia package for generating automated liquid-handling workflows by turning experimental goals into executable liquid-handling protocols. It separates protocol design into two stages: planning, which determines how available reagents should be combined to produce the desired target solutions, and scheduling, which decides how those transfers should be carried out on specific liquid-handling instruments. Pourfecto accounts for reagent availability, stock quantities, target compositions, labware constraints, instrument capabilities, deck space, and allowable transfer volumes to produce optimized workflows. 


## Installation

Pourfecto can be installed from the [`Jensen Lab Registry`](https://github.com/jensenlab/JensenLabRegistry). Follow instructions to add the registry before continuing 

Once the registry has been installed, add Pourfecto with the following command:

```julia
# after installing JensenLabRegistry
using Pkg
Pkg.add("Pourfecto")
```

Then load the package:

```julia
using Pourfecto
```

!!! note 
    Pourfecto requires an active [Gurobi](https://www.gurobi.com) license to run its planning and scheduling algorithms. Licenses are free for academic users as of the time of writing. 

---




