module CHESSExperiments

using Dates, DataFrames, CHESSCore, Unitful, CSV

include("exceptions.jl")
include("design/experiment.jl")
include("design/parameters.jl")
include("qc/qcmethod.jl")
include("design/factors.jl")
include("design/columnmap.jl")
include("design/resolve.jl")
include("design/parse.jl")
include("design/blocking.jl")

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

export Factor, CategoricalFactor, ContinuousFactor
export is_blocking, destination, factor_levels, factor_registry, register_factor!, get_factor
export RESERVED_DESIGN_COLUMNS
export DesignColumnMap
export is_registered_reagent, factor_destination, classify_columns, resolve_stock, resolve_conditions
export populate_well_conditions
export parse_design
export control_role, expand_control_templates
export partition_by_blocking, schedule_blocked_layout

end # module CHESSExperiments
