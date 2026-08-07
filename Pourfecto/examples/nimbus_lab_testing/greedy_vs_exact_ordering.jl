# Compiles the same scenario twice, once with batch_ordering=:greedy (the default) and once with
# :exact, writing both to sibling output folders so the two dispense sequences can be compared
# directly -- e.g. loaded onto the deck side by side, or diffed by eye. Uses 8 scattered
# destinations (order_exact's tractable size cap) so the greedy nearest-neighbor tour has room to
# be visibly suboptimal.
#
# Usage: julia --project=Pourfecto Pourfecto/examples/nimbus_lab_testing/greedy_vs_exact_ordering.jl

include(joinpath(@__DIR__, "common.jl"))

source = build_location(location_kinds[:Conical50], "lab_test_ordering_source")
target = build_location(location_kinds[:DeepWP96], "lab_test_ordering_target")
R, C = size(target)

scattered = [(1,1), (8,12), (1,12), (8,1), (4,6), (5,7), (2,3), (7,10)]
design = DataFrame(zeros(1, R * C), :auto)
for (r,c) in scattered
    design[1, well_col(R, r, c)] = 100.0 # 800 uL total, one batch, all 8 destinations together
end

greedy_df = run_and_summarize("greedy_vs_exact_ordering_greedy", design, Labware[source], Labware[target]; batch_ordering=:greedy)
exact_df = run_and_summarize("greedy_vs_exact_ordering_exact", design, Labware[source], Labware[target]; batch_ordering=:exact)

function tour_distance(df::DataFrame)
    dispenses = df[df.Dispense .== 1, "Labware Position ID"]
    positions = well_to_cartesian.(dispenses)
    return sum(grid_distance(positions[i], positions[i+1]) for i in 1:length(positions)-1)
end

println("greedy dispense order: ", greedy_df[greedy_df.Dispense .== 1, "Labware Position ID"])
println("exact dispense order:  ", exact_df[exact_df.Dispense .== 1, "Labware Position ID"])
println("greedy total intra-batch travel distance: ", round(tour_distance(greedy_df), digits=2))
println("exact total intra-batch travel distance:  ", round(tour_distance(exact_df), digits=2))
