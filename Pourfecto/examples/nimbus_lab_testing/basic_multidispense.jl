# Basic one-to-many aspirate/dispense: one source feeds a full plate row, split into as few
# capacity-bounded aspirates as fit -- the core case this feature exists for.
#
# Usage: julia --project=Pourfecto Pourfecto/examples/nimbus_lab_testing/basic_multidispense.jl

include(joinpath(@__DIR__, "common.jl"))

source = build_location(location_kinds[:Conical50], "lab_test_basic_source")
target = build_location(location_kinds[:DeepWP96], "lab_test_basic_target")
R, C = size(target)

design = DataFrame(zeros(1, R * C), :auto)
for c in 1:C
    design[1, well_col(R, 1, c)] = 300.0 # row A, all 12 columns, 300 uL each -> forces multiple aspirates (3600 uL total / 1000 uL capacity)
end

run_and_summarize("basic_multidispense", design, Labware[source], Labware[target])
