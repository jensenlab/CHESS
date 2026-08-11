
struct OccupancyError <: Exception 
    msg::AbstractString
end 


""" 
    struct PlateArray
        wells::BitMatrix
        positives::BitMatrix 
        negatives::BitMatrix
    end
    
    A PlateArray object describes the layout of a microwell plate that includes the active experimental wells and controls. 
"""
struct PlateArray
    wells::BitMatrix # indicator for which wells are active on the plate
    positives::BitMatrix # indicator for positive control wells
    negatives::BitMatrix # indicator for negative control wells
    function PlateArray(wells,positives,negatives)
        allequal([size(wells),size(positives),size(negatives)]) ? nothing : throw(DimensionMismatch("All array sizes must be equal"))
        any(positives .&& negatives ) ? throw(OccupancyError("positive and negative controls cannot occupy the same well")) : nothing 
        any(positives .&& .!wells) ? throw(OccupancyError("positive controls cannot occupy an inactive well")) : nothing 
        any(negatives .&& .!wells) ? throw(OccupancyError("negative controls cannot occupy an inactive well")) : nothing 
        return new(wells,positives,negatives)
    end 
end 

==(x::PlateArray,y::PlateArray) = x.wells == y.wells && x.positives==y.positives && x.negatives == y.negatives



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