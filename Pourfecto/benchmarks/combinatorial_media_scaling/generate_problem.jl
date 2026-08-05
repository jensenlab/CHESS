# Builds a combinatorial-media scheduling problem sized for the Tempest: `n_plates` 384-well
# target plates, each well holding 80 uL of water plus a unique continuous dose of every one of
# 20 reagents. Sources are large bottles -- the only labware Tempest can aspirate from -- so this
# problem (unlike examples/combinatorial_media/combinatorial_media.jl) is restricted to a single
# instrument config, "tempest", which is also the only config that can dispense into a 384-well
# plate from a bottle source (see README.md).

using Pourfecto, CHESSCore, Unitful, Random

const N_REAGENTS = 20
const WELL_VOLUME = 80u"µL"
const REAGENT_DOSE_RANGE = (0.1u"µL", 1.0u"µL")  # unique per-well, per-reagent dose

"""
    build_problem(n_plates::Int; seed::Int=48207531)

Construct `n_plates` WP384 target plates (each well: 80 uL water + a unique continuous dose of
each of 20 reagents) and the Tempest-compatible bottle sources needed to fill them. Source bottles
are filled generously enough to cover the largest sweep point (30 plates), so the same sources can
be reused unchanged across the whole scaling sweep -- only target complexity varies.

Returns `(source_labware, target_plates, priority, reagents)`.
"""
function build_problem(n_plates::Int; seed::Int=48207531)
    rng = Random.MersenneTwister(seed)

    reagents = [string_to_reagent("R$i", Solid) for i in 1:N_REAGENTS]
    water = string_to_reagent("water", Liquid)

    # One concentrated "unit" solution per reagent. `*(::Unitful.Volume, ::Stock)` rescales this
    # to any target volume while preserving the reagent:water ratio, so the same definition is
    # used both to fill each source bottle and to dose each well (examples/checkerboard.jl idiom).
    reagent_stocks = [100u"g" * r + 100u"mL" * water for r in reagents]

    source_labware = Labware[]
    for r in eachindex(reagents)
        bottle = build_location(location_kinds[:Bottle1L])
        children(bottle)[1].stock = 900u"mL" * reagent_stocks[r]
        push!(source_labware, bottle)
    end

    water_bottle = build_location(location_kinds[:Bottle1L])
    children(water_bottle)[1].stock = 900u"mL" * water
    push!(source_labware, water_bottle)

    target_plates = Labware[]
    for p in 1:n_plates
        plt = build_location(location_kinds[:WP384])
        for well in children(plt)
            doses = [(REAGENT_DOSE_RANGE[1] + rand(rng) * (REAGENT_DOSE_RANGE[2] - REAGENT_DOSE_RANGE[1]))
                     for _ in 1:N_REAGENTS]
            water_vol = WELL_VOLUME - sum(doses)
            well.stock = water_vol * water
            for r in eachindex(reagents)
                well.stock += doses[r] * reagent_stocks[r]
            end
        end
        push!(target_plates, plt)
    end

    priority = PriorityDict("water" => typemax(UInt64))

    return (source_labware=source_labware, target_plates=target_plates, priority=priority, reagents=reagents)
end
