
"""
    arrayer(wells::BitMatrix,experiments::Vararg{Experiment};kwargs...)

Array Experiment objects onto plates in three steps: 
1. assign all experiments to as few plates as possible
2. partition plates that contain multiple experiments and select wells to hold each run. Use central wells first. 
3. place a full complement of controls on each plate that has a given experiment

# Arguments 
- `wells`: A BitMatrix of active wells on each plate (block any inactive wells by setting them to false)
- `experiments`: Array a variable number of `Experiment` objects

Returns a Matrix of PlateArray objects with dimensions E x P, where E is the number of experimens and P the number of plates.
"""
function arrayer(wells::BitMatrix,experiments::Vararg{Experiment};kwargs...)

    assignments=assign_plates(wells,experiments...;kwargs...)

    N,P=size(assignments)
    r,c=size(wells)
    plate_arrays=[PlateArray(falses(r,c),falses(r,c),falses(r,c)) for n in 1:N,p in 1:P]

    for p in 1:P 
        well_partitions=partition(wells,assignments[:,p]...) 
        for n in 1:N 
            if assignments[n,p]==0 
                continue 
            else 
                plate_arrays[n,p]=place_controls(well_partitions[n],experiments[n].positive_controls,experiments[n].negative_controls;kwargs...)
            end
        end 
    end 
    return plate_arrays

end 
