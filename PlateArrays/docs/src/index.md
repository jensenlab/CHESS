# PlateArrays.jl

*Arraying software for microwell plates* 

A julia package for scheduling microplate layouts. PlateArrays.jl is useful for:

* Optimally placing control wells for any size plate. 
* Blocking wells from being used
* Minimizing labware usage by slotting runs from multiple experiments onto as few plates as possible.
* Exporting visualizing plate layouts

## Installation 

PlateArrays is available in the [`Jensen Lab Registry`](https://github.com/jensenlab/JensenLabRegistry). Follow the instructions to add the registry before continuing.

Once the registry has been added, run the following command: 

```julia 
# once JensenLabRegistry has been added
using Pkg
Pkg.add(url= "https://github.com/jensenlab/PlateArrays")
```

Then, load the pckage: 

```julia 
using PlateArrays
```






