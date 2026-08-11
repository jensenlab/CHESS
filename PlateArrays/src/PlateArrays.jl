module PlateArrays


using Random,
JuMP,
Gurobi,
Distributions,
Plots,
ColorBrewer,
DataFrames

import Plots: plot
import DataFrames: DataFrame 
import Base: == , size 
include("./types.jl")
include("./utils.jl")
include("./interface.jl")
include("./solvers/objectives.jl")
include("./solvers/exchange.jl")
include("./solvers/MILP.jl")
include("./controls/place_controls.jl")
include("./assign/partition.jl")
include("./assign/assign_plates.jl")
include("./visualization/visualize_plate.jl")
include("./arrayer/arrayer.jl")









#types.jl
export PlateArray,Experiment,Expt,OccupancyError
#utils.jl
export runs, random_platearray,active_indices
#place_controls.jl
export place_controls, solvers, objectives 
#arrayer.jl
export arrayer
#visualize_plate
export plot



end # module PlateArrays
