# Single-channel vs 4-channel Nimbus operation counts, with ablations of the 4-channel's
# optimizations (see README.md).
#
# Usage (from the CHESS repo root):
#   julia --project=Pourfecto Pourfecto/benchmarks/nimbus_four_channel_head_to_head/run_benchmark.jl [results_csv]
#
# No solver: each synthetic design (generate_instances.jl) is compiled directly through the
# compile-stage functions -- convert_design/batch_design for single-channel, and
# place_labware/convert_design_four_channel/batch_design_four_channel for 4-channel.

using Pourfecto, CHESSCore, CSV, DataFrames, Random
import Pourfecto: convert_design, batch_design, convert_design_four_channel, batch_design_four_channel, place_labware

include(joinpath(@__DIR__, "generate_instances.jl"))

const NIMBUS = configurations["nimbus"]
const NIMBUS_4CH = configurations["nimbus_four_channel"]
const REAGENT_COUNTS = [1, 2, 4, 8, 12, 16, 20, 24]
const SEEDS = [1, 2, 3]

function single_channel_counts(design, sources, targets)
    slotting = slotting_greedy(vcat(sources, targets), NIMBUS)
    a = batch_design(convert_design(design, sources, targets, slotting, NIMBUS), NIMBUS)
    # the first tip pickup is implicit (Change Tip Before is 0 on the first aspirate); every tip
    # picked up is disposed once
    tips = 1 + sum(a[!, "Change Tip Before"])
    aspirates = count(==("Aspirate"), a.Action)
    return (tips_used=tips, tip_pickups=tips, tip_disposals=tips, aspirates=aspirates, aspirate_motions=aspirates,
        dispenses=count(==("Dispense"), a.Action), blowouts=count(==("Blowout"), a.Action),
        dispensed_uL=sum(a[a.Action .== "Dispense", "Volume (uL)"]))
end

function four_channel_counts(design, sources, targets, slotting; synchronize_reloads::Bool=true)
    a = batch_design_four_channel(convert_design_four_channel(design, sources, targets, slotting, NIMBUS_4CH), NIMBUS_4CH;
        synchronize_reloads)
    rows(action) = a[a.Action .== action, :]
    active(r) = [r["Labware Position $c"] for c in 1:4 if r["Labware Position $c"] != "None"]
    # channels in different rack columns can't aspirate in one motion, even when the Nimbus runs
    # them from one row
    aspirate_motions = sum((length(unique(p[2:end] for p in active(r))) for r in eachrow(rows("Aspirate"))); init=0)
    return (tips_used=sum((length(active(r)) for r in eachrow(rows("TipPickup"))); init=0),
        tip_pickups=nrow(rows("TipPickup")), tip_disposals=nrow(rows("TipDisposal")),
        aspirates=nrow(rows("Aspirate")), aspirate_motions=aspirate_motions,
        dispenses=nrow(rows("Dispense")), blowouts=nrow(rows("Blowout")),
        dispensed_uL=sum(sum(rows("Dispense")[!, "Volume $c"]) for c in 1:4))
end

function run_instance(scheme::Symbol, n::Int, seed::Int)
    design = generate_design(scheme, n, seed)
    sources, targets = build_labware("$(scheme)_n$(n)_s$(seed)", n)
    expected_uL = sum(Matrix(design))

    greedy = slotting_greedy(vcat(sources, targets), NIMBUS_4CH)
    placed = place_labware(greedy, design, sources, targets, NIMBUS_4CH)
    variants = [
        "single_channel" => single_channel_counts(design, sources, targets),
        "four_channel" => four_channel_counts(design, sources, targets, placed),
        "no_placement" => four_channel_counts(design, sources, targets, greedy),
        "no_sync_reloads" => four_channel_counts(design, sources, targets, placed; synchronize_reloads=false),
    ]

    out = NamedTuple[]
    for (variant, c) in variants
        isapprox(c.dispensed_uL, expected_uL; atol=1e-6) ||
            error("$variant dispensed $(c.dispensed_uL) uL, design needs $expected_uL uL ($scheme, n=$n, seed=$seed)")
        push!(out, (scheme=scheme, n_reagents=n, seed=seed, variant=variant,
            transfers=count(!=(0), Matrix(design)), total_volume_uL=expected_uL,
            tips_used=c.tips_used, tip_pickups=c.tip_pickups, tip_disposals=c.tip_disposals,
            aspirates=c.aspirates, aspirate_motions=c.aspirate_motions, dispenses=c.dispenses, blowouts=c.blowouts,
            total_operations=c.tip_pickups + c.tip_disposals + c.aspirates + c.dispenses + c.blowouts))
    end
    return out
end

function main()
    out_csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "results", "operation_counts.csv")
    mkpath(dirname(out_csv))

    rows = NamedTuple[]
    for scheme in SCHEMES, n in REAGENT_COUNTS, seed in SEEDS
        t = @elapsed instance = run_instance(scheme, n, seed)
        totals = join(["$(r.variant)=$(r.total_operations)" for r in instance], " ")
        println("scheme=$scheme n=$n seed=$seed ($(round(t, digits=1)) s): $totals")
        append!(rows, instance)
    end

    CSV.write(out_csv, DataFrame(rows))
    println("wrote $out_csv")
end

main()
