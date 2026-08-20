module CHESSQC

using CHESSExperiments, DataFrames, CategoricalArrays, GaussianProcesses, Plots, Statistics, StatsBase, Random

include("utils.jl")
include("correction/plateerrorGP.jl")
include("correction/correction.jl")

include("plotting/plotting.jl")
include("reports/control_report.jl")

"""
    to_plate_matrix(labware, layout::DataFrame, read_kind::Symbol)

Convert a `CHESSCore.Labware` plus a `CHESSExperiments.Experiment`'s `:layout` metadata DataFrame into the
`Matrix` `data_correction` operates on. Only available once `CHESSCore` is also loaded (implemented in
the `CHESSQCCoreExt` package extension) -- `CHESSQC` itself has no dependency on `CHESSCore`.
"""
function to_plate_matrix end

"""
    record_qc_reads!(labware, corrected, layout::DataFrame, read_kind::Symbol, method)

Write `corrected` (the output of [`data_correction`](@ref)) back onto `labware` as new
`CHESSCore.Read`s, and attach QC provenance (`method`) onto each matching `layout` row's `metadata`.
Only available once `CHESSCore` is also loaded (implemented in the `CHESSQCCoreExt` package extension).
"""
function record_qc_reads! end

export data_correction
export plot_control_data, plot_plate_data
export control_summary
export GPCorrection, SubtractNormalize
export to_plate_matrix, record_qc_reads!

function __init__()
    __register_qc_methods__()
end

end # module CHESSQC
