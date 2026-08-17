
"""
    arrayer(wells::BitMatrix,experiments::Vararg{Experiment};run_order::String="ordered",rng::AbstractRNG=Random.default_rng(),kwargs...)

Array Experiment objects onto plates in three steps:
1. assign all experiments to as few plates as possible
2. partition plates that contain multiple experiments and select wells to hold each run. Use central wells first.
3. place a full complement of controls on each plate that has a given experiment

# Arguments
- `wells`: A BitMatrix of active wells on each plate (block any inactive wells by setting them to false)
- `experiments`: Array a variable number of `Experiment` objects

# Keyword Arguments
- `run_order`: how each experiment's runs are numbered via `run_index`, coordinated across every plate
  that experiment is split onto (not independently per plate -- an experiment spanning multiple plates
  gets one continuous `1:total_runs` schedule, not a fresh `1:N` restarting on each plate). `"ordered"`
  (default) or `"random"`. See [`assign_run_index`](@ref).
- `rng`: the random number generator used by the solver and by `run_order="random"`.

Returns a Matrix of PlateArray objects with dimensions E x P, where E is the number of experimens and P the number of plates.
"""
function arrayer(wells::BitMatrix,experiments::Vararg{Experiment};run_order::String="ordered",rng::AbstractRNG=Random.default_rng(),kwargs...)
    run_order in ("ordered","random") || throw(ArgumentError("run_order must be \"ordered\" or \"random\""))

    assignments=assign_plates(wells,experiments...;rng=rng,kwargs...)

    N,P=size(assignments)
    r,c=size(wells)
    plate_arrays=[PlateArray(falses(r,c),falses(r,c),falses(r,c)) for n in 1:N,p in 1:P]

    for p in 1:P
        well_partitions=partition(wells,assignments[:,p]...)
        for n in 1:N
            if assignments[n,p]==0
                continue
            else
                plate_arrays[n,p]=place_controls(well_partitions[n],experiments[n].positive_controls,experiments[n].negative_controls;rng=rng,kwargs...)
            end
        end
    end

    # Coordinate run_index across every plate a given experiment spans -- place_controls has no notion
    # of a multi-plate experiment, so it numbers each plate 1:N_plate independently; overwrite each
    # experiment's plates here with its correct slice of a single 1:total_runs schedule.
    for n in 1:N
        pool = run_order == "random" ? shuffle(rng,1:experiments[n].runs) : collect(1:experiments[n].runs)
        offset = 0
        for p in 1:P
            assignments[n,p]==0 && continue
            nruns = sum(runs(plate_arrays[n,p]))
            chunk = pool[offset+1:offset+nruns]
            plate_arrays[n,p] = assign_run_index(plate_arrays[n,p];indices=chunk)
            offset += nruns
        end
    end

    return plate_arrays

end
