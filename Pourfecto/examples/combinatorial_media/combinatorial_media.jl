# # Combinatorial Media Preparation
#
# This example reproduces a high-throughput microbial growth experiment: we
# need to prepare 480 unique 200 µL media wells — five 96-well target plates
# — each containing a random subset of up to 48 candidate reagents dissolved
# in water.
#
# The source stocks are spread across three different labware types:
#
# 1. A deep 96-well plate holding the 48 reagent stocks (plus a few spare
#    wells of water).
# 2. An SLAS-format reservoir of water.
# 3. A 1000 mL bottle of water.
#
# Pourfecto is allowed to use any combination of six liquid-handler
# configurations, but not every source labware is compatible with every
# instrument: multiwell-plate instruments can't hold a 1000 mL bottle on
# their deck, and plate-filling instruments like the Tempest can't accept
# multiwell plates as sources. Pourfecto has to satisfy these compatibility
# constraints while it searches for a schedule, which makes this a good test
# of how the choice of available source labware and scheduling objective
# affects the resulting plan.

using Pourfecto, CHESSCore, Unitful, Random, DataFrames, CSV

# We randomly generate the media compositions. For this reason alone, we include 
# a seed. 
Random.seed!(48207531) 

# ## Reagents and source labware

reagents = [string_to_reagent("R$i", Solid) for i in 1:48]
water = string_to_reagent("water", Liquid)

# The deep 96-well source plate holds each reagent stock twice, in different
# wells, so the scheduler has more flexibility in which physical well it
# draws from.

source_deep_well = build_location(location_kinds[:DeepWP96])

for r in eachindex(reagents)
    st = 2u"ml" * water + 1u"g" * reagents[r]
    children(source_deep_well)[r].stock = st
    children(source_deep_well)[r+length(reagents)].stock = st
end

water_deep_reservoir = build_location(location_kinds[:DeepReservoir])
children(water_deep_reservoir)[1].stock = 100u"mL" * water

water_bottle = build_location(location_kinds[:Bottle1L])
children(water_bottle)[1].stock = 1u"L" * water

# ## Randomized target plates
#
# Each of the five target plates gets 200 µL of water per well, plus a random
# 0.1 mg dose of each reagent (independently, with 50% probability per
# reagent per well).

n_plates = 5
target_plates = Labware[]

for p in 1:n_plates
    plt = build_location(location_kinds[:WP96])
    for well in children(plt)
        well.stock = 200u"µL" * water
        for r in reagents
            if rand() <= 0.5
                well.stock += 0.1u"mg" * r
            end
        end
    end
    push!(target_plates, plt)
end

# ## Priority and configurations
#
# Water is deprioritized relative to the 48 named reagents, so Pourfecto
# favors hitting the exact reagent composition over exactly matching the
# water volume — small deviations in total water volume are an acceptable
# tradeoff for getting the reagent doses right. This is a design decision
# that can change from experiment to experiment.

priority = PriorityDict("water" => typemax(UInt64))

source_labware_all = [source_deep_well, water_deep_reservoir, water_bottle]
source_labware_no_reservoir = [source_deep_well, water_bottle]
configs = ["single_channel", "eight_channel_vertical", "eight_channel_horizontal",
    "plate_master", "cobra", "nimbus", "tempest"]

# ## Comparing scheduling scenarios
#
# We run four scenarios that vary either the available source labware or the
# scheduling objective:
#
# 1. **All Sources** — every source labware available, default
#    `"min_cost_flow"` objective.
# 2. **No Reservoir** — the SLAS reservoir removed, forcing the scheduler to
#    route more water through the 1000 mL bottle (or fall back on
#    incompatible-instrument tradeoffs).
# 3. **Minimize Active Flows** — all sources available, but scheduling
#    minimizes the number of discrete dispense operations instead of cost.
# 4. **Minimize Configurations** — all sources available, scheduling
#    minimizes the number of distinct instrument configurations used.

pc1, time1 = @timed pourfecto(source_labware_all, target_plates, configs; priority=priority, solver_timelimit=45)

pc2, time2 = @timed pourfecto(source_labware_no_reservoir, target_plates, configs; priority=priority, solver_timelimit=45)

pc3, time3 = @timed pourfecto(source_labware_all, target_plates, configs; priority=priority, objective="min_active_flow", solver_timelimit=100)

pc4, time4 = @timed pourfecto(source_labware_all, target_plates, configs; priority=priority, objective="min_config", solver_timelimit=100)

# ## Reporting results
#
# For each scenario we tally the transfers performed by each instrument
# configuration, the total scheduled flow volume, the number of active
# (nonzero) flows, and the solve time.

pcs = [pc1, pc2, pc3, pc4]
tms = [time1, time2, time3, time4]
names = ["All Sources", "No Reservoir", "Minimize Active Flows", "Minimize Configurations"]

ts = transfers.(pcs)
fs = flows.(pcs)
as = map(x -> flows(x) .> 1e-4, pcs)
config_trfs = map(x -> sum.(transfers_by_config(x)), pcs)

df = DataFrame()
for i in eachindex(pcs)
    d = (
        name=names[i],
        single_channel=config_trfs[i][1],
        eight_channel=sum(config_trfs[i][2:3]),
        plate_master=config_trfs[i][4],
        cobra=config_trfs[i][5],
        nimbus=config_trfs[i][6],
        tempest=config_trfs[i][7],
        transfers=sum(ts[i]),
        flows=sum(fs[i]),
        active_flows=sum(as[i]),
        time=tms[i],
    )
    push!(df, d)
end

df

# A few things stand out in this table:
#
# - **No Reservoir** relies more heavily on the 1000 mL bottle and the
#   instruments that can reach it, since the SLAS reservoir is unavailable.
# - **Minimize Active Flows** tends to reduce the `active_flows` column
#   relative to the default objective, consolidating water dispenses into
#   fewer, larger operations where possible.
# - **Minimize Configurations** tends to concentrate transfers onto fewer
#   distinct instrument types, at the cost of solve time or total flow.
#
# Finally, we save the comparison table alongside the example for reference.

CSV.write(joinpath(@__DIR__, "combinatorial_media_results.csv"), df)
