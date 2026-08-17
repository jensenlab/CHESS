
struct OccupancyError <: Exception
    msg::AbstractString
end

"""
    struct RunIndexError <: Exception

Thrown when a `PlateArray`'s `run_index` field is neither fully unassigned (`missing` everywhere) nor a
valid schedule (distinct positive integers over exactly the run wells, `missing` elsewhere). Note this
does *not* require the values to form a contiguous `1:N` range starting at 1 -- a plate holding one slice
of a larger, multi-plate experiment legitimately carries a non-1-starting range (e.g. `{7,8,9,10}`); see
[`assign_run_index`](@ref)'s `indices` keyword.
"""
struct RunIndexError <: Exception
    msg::AbstractString
end


"""
    struct PlateArray
        wells::BitMatrix
        positives::BitMatrix
        negatives::BitMatrix
        run_index::Matrix{Union{Missing,Int}}
    end

    A PlateArray object describes the layout of a microwell plate that includes the active experimental
    wells and controls, plus an optional schedule of distinct positive integer run indices over the
    non-control active ("run") wells (not necessarily a contiguous `1:N` range starting at 1 -- a plate
    holding one slice of a larger, multi-plate experiment carries whichever range that experiment assigned
    it). `run_index` is `missing` everywhere when unassigned -- see [`assign_run_index`](@ref) to
    populate it.
"""
struct PlateArray
    wells::BitMatrix # indicator for which wells are active on the plate
    positives::BitMatrix # indicator for positive control wells
    negatives::BitMatrix # indicator for negative control wells
    run_index::Matrix{Union{Missing,Int}} # 1:N schedule over run wells, or all missing if unassigned
    function PlateArray(wells,positives,negatives,run_index=fill(missing,size(wells)))
        allequal([size(wells),size(positives),size(negatives),size(run_index)]) ? nothing : throw(DimensionMismatch("All array sizes must be equal"))
        any(positives .&& negatives ) ? throw(OccupancyError("positive and negative controls cannot occupy the same well")) : nothing
        any(positives .&& .!wells) ? throw(OccupancyError("positive controls cannot occupy an inactive well")) : nothing
        any(negatives .&& .!wells) ? throw(OccupancyError("negative controls cannot occupy an inactive well")) : nothing

        run_mask = wells .&& .!positives .&& .!negatives
        assigned = .!ismissing.(run_index)
        if any(assigned)
            assigned == run_mask || throw(RunIndexError("run_index must be assigned at exactly the run wells (non-control active wells)"))
            vals = collect(skipmissing(run_index))
            all(v -> v >= 1, vals) || throw(RunIndexError("run_index values must be positive integers"))
            length(vals) == length(unique(vals)) || throw(RunIndexError("run_index values must be unique"))
        end

        return new(wells,positives,negatives,run_index)
    end
end

==(x::PlateArray,y::PlateArray) = x.wells == y.wells && x.positives==y.positives && x.negatives == y.negatives && isequal(x.run_index,y.run_index)



""" 
    size(p::PlateArray) 

Return the size (rows x colummns) of the BitMatrices that define the PlateArray 

"""
function size(p::PlateArray) 
    return size(p.wells) # wells, positives, and negatives should all be equal 
end 


"""
    struct Experiment
        runs::Int
        positive_controls::Int
        negative_controls::Int
    end 

    Collect the number of runs and controls in an experiment.
"""
struct Experiment
    runs::Int
    positive_controls::Int
    negative_controls::Int
    function Experiment(runs,positives,negatives)
        runs >= 0 ? nothing : throw(DomainError(runs,"runs must be a non-negative integer"))
        positives >= 0 ? nothing : throw(DomainError(positives,"positive_controls must be a non-negative integer"))
        negatives >= 0 ? nothing : throw(DomainError(negatives,"negative_controls must be a non-negative integer"))
        return new(runs,positives,negatives)
    end 
end 

const Expt=Experiment