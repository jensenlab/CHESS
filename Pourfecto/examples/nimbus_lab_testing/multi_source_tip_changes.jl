# Demonstrates Change Tip Before: it fires (a) whenever the source well changes, and (b)
# periodically within a long run of aspirates from the same source, per the "max_tip_use"
# instrument setting -- reinterpreted as a count of aspirate batches, not individual dispense
# shots. Temporarily lowers max_tip_use to 3 (from the shipped default of 10) so the periodic
# behavior is visible without needing 10+ batches from one source.
#
# Usage: julia --project=Pourfecto Pourfecto/examples/nimbus_lab_testing/multi_source_tip_changes.jl

include(joinpath(@__DIR__, "common.jl"))

source1 = build_location(location_kinds[:Conical50], "lab_test_tipchange_source1")
source2 = build_location(location_kinds[:Conical50], "lab_test_tipchange_source2")
target = build_location(location_kinds[:DeepWP96], "lab_test_tipchange_target")
R, C = size(target)

design = DataFrame(zeros(2, R * C), :auto)
# source1: 30 destinations at 100 uL each (3000 uL total) -> 3 aspirate batches from one source,
# enough for the max_tip_use=3 window below to force a periodic change even without a source change
for i in 1:30
    design[1, i] = 100.0
end
# source2: a few more destinations -> a 4th batch, from a different source (always forces a change)
for i in 31:33
    design[2, i] = 100.0
end

config = configurations["nimbus"]
settings(config)["max_tip_use"] = 3 # lowered just for this demonstration; affects this process only

df = run_and_summarize("multi_source_tip_changes", design, Labware[source1, source2], Labware[target])
println("Change Tip Before, per aspirate row, in emission order:")
aspirates = df[df.Aspirate .== 1, :]
show(aspirates[:, ["Labware ID", "Labware Position ID", "Volume (uL)", "Change Tip Before"]], allrows=true)
println()
