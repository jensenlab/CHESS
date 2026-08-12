# Demonstrates the opt-in dead-volume Blowout path: a single source forced into several
# re-aspirate batches under one tip, each pair of consecutive same-tip batches separated by a
# Blowout row that drains a fixed dead-volume buffer before the next aspirate. Prints each cycle's
# dispense-sum(+blowout) vs. aspirate-volume check so the (buffer-aware) exact-agreement invariant
# is directly eyeballable -- every aspirate carries a small, unconditional safety margin
# (aspirate_buffer, default 0.01 uL) beyond what its cycle actually needs, so real-world pipetting
# inaccuracy on the last action in a cycle (e.g. the blowout itself) doesn't leave the tip short.
#
# waste_target is left unspecified below, so it uses the default: the permanently-reserved waste
# conical at TubeRack50ML_0006, slot 5 (nearest the tip rack), excluded from ordinary
# source/target slotting on every Nimbus compile -- see Pourfecto.nimbus_waste_target and
# slotting_greedy's Configuration{Nimbus} override. The Blowout path itself is still opt-in and
# not yet validated end-to-end against real instrument hardware (the instrument-side .hsl support
# and a RunControl smoke test remain open -- see csv_generation_refactor_notes.md's Bug 3 section).
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

dead_volume_buffer = 20.0

df = run_and_summarize("blowout_dead_volume", design, Labware[source], Labware[target];
    insert_blowouts=true, dead_volume_buffer)

println("Per-cycle check: sum(dispenses in cycle) + (blowout, if present) + aspirate_buffer == that cycle's aspirate volume")
aspirate_idx = findall(==("Aspirate"), df.Action)
n = nrow(df)
aspirate_buffer = 0.01 # must match the default passed (implicitly) to run_and_summarize below
for (k, i) in enumerate(aspirate_idx)
    block_end = k < length(aspirate_idx) ? aspirate_idx[k+1] - 1 : n
    cycle_sum = sum(df[i+1:block_end, "Volume (uL)"])
    aspirate_volume = df[i, "Volume (uL)"]
    margin = aspirate_volume - cycle_sum
    println("  cycle $k: aspirate=$aspirate_volume  sum(dispense+blowout)=$cycle_sum  margin=$margin  match=$(isapprox(margin,aspirate_buffer;atol=1e-6))")
end
