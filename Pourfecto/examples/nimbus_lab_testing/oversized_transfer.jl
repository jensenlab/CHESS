# A single destination needs more than the channel's capacity (2500 uL > 1000 uL), forcing a split
# across multiple aspirates -- whose remainder is free to combine with other, smaller destinations
# in the same aspirate rather than getting a dedicated one.
#
# Usage: julia --project=Pourfecto Pourfecto/examples/nimbus_lab_testing/oversized_transfer.jl

include(joinpath(@__DIR__, "common.jl"))

source = build_location(location_kinds[:Conical50], "lab_test_oversized_source")
target = build_location(location_kinds[:DeepWP96], "lab_test_oversized_target")
R, C = size(target)

design = DataFrame(zeros(1, R * C), :auto)
design[1, well_col(R, 1, 1)] = 2500.0 # oversized: splits into 1000 + 1000 + 500
design[1, well_col(R, 1, 2)] = 200.0
design[1, well_col(R, 1, 3)] = 200.0
design[1, well_col(R, 1, 4)] = 200.0

df = run_and_summarize("oversized_transfer", design, Labware[source], Labware[target])
println("Expect the 500 uL remainder from well A1 to share a batch with one or more of A2/A3/A4 (each 200 uL) rather than getting its own aspirate:")
show(df, allrows=true)
println()
