# Demonstrates the (opt-in, NOT YET physically validated -- see csv_generation_refactor_notes.md)
# dead-volume Blowout path: a single source forced into several re-aspirate batches under one tip,
# each pair of consecutive same-tip batches separated by a Blowout row that drains a fixed
# dead-volume buffer before the next aspirate. Prints each cycle's dispense-sum(+blowout) vs.
# aspirate-volume check so the exact-agreement invariant is directly eyeballable.
#
# waste_target below is a PLACEHOLDER -- LiquidWaste_0001's real deck Position ID has not been
# confirmed on the instrument side (see the notes' Bug 3 section). Do not treat this script's
# output as ready to run on the real Nimbus until that's confirmed and the parallel .hsl update
# lands.
#
# Usage: julia --project=Pourfecto Pourfecto/examples/nimbus_lab_testing/blowout_dead_volume.jl

include(joinpath(@__DIR__, "common.jl"))

source = build_location(location_kinds[:Conical50], "lab_test_blowout_source")
target = build_location(location_kinds[:DeepWP96], "lab_test_blowout_target")
R, C = size(target)

# 12 wells x 108 uL under one source: effective capacity (1000 - 20 = 980 uL) fits 9 wells in the
# first batch, forcing a 2nd (re-aspirate) batch under the same tip -- exactly the scenario a
# trailing blowout is for.
design = DataFrame(zeros(1, R * C), :auto)
for c in 1:12
    design[1, well_col(R, 1, c)] = 108.0
end

waste_target = ("LiquidWaste_0001", "1") # PLACEHOLDER -- see module comment above
dead_volume_buffer = 20.0

df = run_and_summarize("blowout_dead_volume", design, Labware[source], Labware[target];
    insert_blowouts=true, waste_target, dead_volume_buffer)

println("Per-cycle check: sum(dispenses in cycle) + (blowout, if present) == that cycle's aspirate volume")
aspirate_idx = findall(==("Aspirate"), df.Action)
n = nrow(df)
for (k, i) in enumerate(aspirate_idx)
    block_end = k < length(aspirate_idx) ? aspirate_idx[k+1] - 1 : n
    cycle_sum = sum(df[i+1:block_end, "Volume (uL)"])
    aspirate_volume = df[i, "Volume (uL)"]
    println("  cycle $k: aspirate=$aspirate_volume  sum(dispense+blowout)=$cycle_sum  match=$(cycle_sum == aspirate_volume)")
end
