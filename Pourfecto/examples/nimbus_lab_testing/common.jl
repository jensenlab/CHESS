# Shared setup for the Nimbus lab-testing scripts in this folder. These are standalone scripts for
# a lab technician to run directly and inspect the resulting protocol CSV -- not docs examples (not
# wired into docs/make.jl) and not CI tests (not wired into test/runtests.jl). Each script hand-builds
# a `design::DataFrame` directly, bypassing the solver entirely, so no Gurobi/SCIP/HiGHS license is
# needed to run them.

using Pourfecto, CHESSCore, Unitful, DataFrames, CSV
import Pourfecto: well_to_cartesian, cartesian_to_well

const OUTPUT_ROOT = joinpath(@__DIR__, "..", "..", "data", "nimbus_lab_testing")
mkpath(OUTPUT_ROOT) # write_instrument_files uses mkdir (not mkpath), so the parent must already exist

"""
    well_col(R, r, c) -> Int

Column index into a `design` DataFrame (S x T, one column per destination well) for grid position
`(r,c)` on an `R`-row target plate, matching the column-major well ordering `convert_design` uses
via `CartesianIndices(children(target))`.
"""
well_col(R::Int, r::Int, c::Int) = (c - 1) * R + r

"""
    run_and_summarize(name, design, sources, targets; batch_ordering=:greedy, volume_precision=1,
                       insert_blowouts=false, waste_target=nothing, dead_volume_buffer=0.0) -> DataFrame

Slot `sources`/`targets` onto the Nimbus deck, compile `design` via `write_instrument_files` to
`data/nimbus_lab_testing/<name>/`, then print a short summary (aspirate-batch count, dispense
count, blowout count, tip-change count, total volume) and return the written CSV as a DataFrame
for further inspection.
"""
function run_and_summarize(name::AbstractString, design::DataFrame, sources::Vector{<:Labware}, targets::Vector{<:Labware};
    batch_ordering::Symbol=:greedy, volume_precision::Int=1, insert_blowouts::Bool=false,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    dead_volume_buffer::Real=0.0)
    config = configurations["nimbus"]
    slotting = slotting_greedy(vcat(sources, targets), config)
    outdir = joinpath(OUTPUT_ROOT, name)
    write_instrument_files(outdir, design, sources, targets, config, slotting;
        batch_ordering, volume_precision, insert_blowouts, waste_target, dead_volume_buffer)

    df = CSV.read(joinpath(outdir, basename(outdir) * ".csv"), DataFrame)
    n_aspirates = count(==("Aspirate"), df.Action)
    n_dispenses = count(==("Dispense"), df.Action)
    n_blowouts = count(==("Blowout"), df.Action)
    n_tip_changes = count(==(1), df[!, "Change Tip Before"])
    total_volume = sum(df[df.Action .== "Dispense", "Volume (uL)"])

    println("== $name (batch_ordering=$batch_ordering, insert_blowouts=$insert_blowouts) ==")
    println("  wrote:             $(joinpath(outdir, basename(outdir) * ".csv"))")
    println("  aspirate batches:  $n_aspirates")
    println("  dispenses:         $n_dispenses")
    println("  blowouts:          $n_blowouts")
    println("  tip changes:       $n_tip_changes")
    println("  total dispensed:   $(total_volume) uL")
    println()
    return df
end
