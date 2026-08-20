"""
    abstract type QCMethod <: CHESSExperiments.QCMethod

Common supertype for `CHESSQC`'s registered correction methods (see [`GPCorrection`](@ref),
[`SubtractNormalize`](@ref)), registered into `CHESSExperiments`' global QC method registry via
[`CHESSExperiments.register_qc_method!`](@ref) so other packages can resolve them by name without
depending on `CHESSQC` directly.
"""
struct GPCorrection <: CHESSExperiments.QCMethod end
struct SubtractNormalize <: CHESSExperiments.QCMethod end

# Registered in __init__, not here at top level: CHESSExperiments.qc_method_registry is a separately
# precompiled module's global Dict, and mutations performed at CHESSQC's own precompile time don't
# reliably survive into a fresh runtime session -- __init__ runs every time CHESSQC is loaded, which does.
function __register_qc_methods__()
    haskey(CHESSExperiments.qc_method_registry, :gp_correction) || CHESSExperiments.register_qc_method!(:gp_correction, GPCorrection)
    haskey(CHESSExperiments.qc_method_registry, :subtract_and_normalize) || CHESSExperiments.register_qc_method!(:subtract_and_normalize, SubtractNormalize)
end

function gp_correction(data::Matrix{T}, layout::DataFrame; kwargs...) where T <: Real
    negatives = control_bitmatrix(layout, :negative)
    positives = control_bitmatrix(layout, :positive)

    neg_corrected = plateerrorGP(data, negatives, absolute; kwargs...)
    pos_corrected = plateerrorGP(neg_corrected, positives, relative; kwargs...)

    return pos_corrected
end

function subtract_and_normalize(data::Matrix{T}, layout::DataFrame; kwargs...) where T <: Real
    negatives = control_bitmatrix(layout, :negative)
    positives = control_bitmatrix(layout, :positive)

    neg = mean(data[findall(x -> x == true, negatives)])
    pos = mean(data[findall(x -> x == true, positives)])

    return (data .- neg) ./ (pos - neg)
end

"""
    data_correction(data::Matrix{T}, layout::DataFrame, method::CHESSExperiments.QCMethod; kwargs...) where T <: Real

Apply a correction method to `data` that have been mapped to a `layout` (a `CHESSExperiments.Experiment`'s
`:layout` metadata DataFrame, or anything sharing its `row`/`col`/`positive`/`negative` columns)
indicating which wells are negative and positive controls.
"""
function data_correction(data::Matrix{T}, layout::DataFrame, ::GPCorrection; kwargs...) where T <: Real
    size_data_plate_check(data, layout)
    return gp_correction(data, layout; kwargs...)
end

function data_correction(data::Matrix{T}, layout::DataFrame, ::SubtractNormalize; kwargs...) where T <: Real
    size_data_plate_check(data, layout)
    return subtract_and_normalize(data, layout; kwargs...)
end

"""
    data_correction(data::Matrix{T}, layout::DataFrame, method::Symbol; kwargs...) where T <: Real

Convenience form resolving `method` through `CHESSExperiments`' QC method registry (e.g. as stored in
an `Experiment.metadata[:qc_methods]`) before dispatching on the concrete `QCMethod` instance.
"""
function data_correction(data::Matrix{T}, layout::DataFrame, method::Symbol; kwargs...) where T <: Real
    return data_correction(data, layout, CHESSExperiments.qc_method(method)(); kwargs...)
end
