module CHESSProcessing

using Dates, Statistics, DataFrames
using CHESSExperiments, RunMaps, PlateMaps, CHESSParsers

import Base: merge
import CHESSExperiments: Experiment
import RunMaps: RunMap
import PlateMaps: PlateMap

include("records.jl")
include("values.jl")
include("aggregate.jl")
include("normalize.jl")
include("flag.jl")
include("resolve.jl")
include("correct.jl")
include("plotting.jl")
include("merge.jl")

function __init__()
    __register_parameters__()
end

# records.jl
export ProcessingRecord, processing_log, append_record
# values.jl
export combine_group
# aggregate.jl
export aggregate
# normalize.jl
export normalize, subtract_and_normalize
# flag.jl
export flag, cv_threshold
# resolve.jl
export resolve
# correct.jl
export CorrectionMethod, apply_correction, correct, GPCorrection
# plotting.jl
export plot_plate_data, plot_control_data
# merge.jl
export merge

end # module CHESSProcessing
