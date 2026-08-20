module CHESSExperiments

using Dates, DataFrames

include("exceptions.jl")
include("design/experiment.jl")
include("design/parameters.jl")
include("qc/qcmethod.jl")

"""
    schedule_layout(experiment, pa)

Schedule `experiment`'s design-matrix rows onto a solved plate layout, returning a new `Experiment`
with `:layout` metadata populated. Only available once `RunMaps` and `PlateMaps` are also loaded
(implemented in the `CHESSExperimentsRunMapsExt` package extension) -- neither `RunMaps` nor `PlateMaps`
has any dependency on `CHESSExperiments`.
"""
function schedule_layout end

export DuplicateRegistrationError
export Experiment, LAYOUT_COLUMNS
export ParameterKind, register_parameter!, get_parameter, with_parameter, parameter_registry, layout
export QCMethod, register_qc_method!, qc_method, qc_methods
export schedule_layout

end # module CHESSExperiments
