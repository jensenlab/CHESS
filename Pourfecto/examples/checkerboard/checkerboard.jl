# # Checkerboard Assay
#
# Pairwise reagent-synergy assays commonly use a "checkerboard" layout: the
# concentration of reagent A decreases linearly along each row of a microplate,
# and the concentration of reagent B decreases linearly along each column.
# Together the two gradients form a grid of unique A/B combinations — 64 of
# them on an 8x8 plate.
#
# This layout is also a nice test of Pourfecto's scheduling: an eight-channel
# pipette can dispense reagent A across an entire row in one motion (pipette
# oriented horizontally) and reagent B across an entire column in one motion
# (pipette oriented vertically). The optimal schedule needs only 16 active
# dispense operations — one per row for A, one per column for B. A
# single-channel pipette, by contrast, would need `2 * 64 = 128` operations,
# since it can only reach one well at a time. A 96-channel pipette can't be
# used at all here, since it dispenses to every well simultaneously and can't
# vary volume independently by row or column.
#
# We'll build this experiment in Pourfecto, let it choose from a set of
# available pipetting configurations, and see whether it converges on the
# 16-operation eight-channel solution.

using Pourfecto, CHESSCore, Unitful

# ## Defining reagents and source labware
#
# Reagents are created from names with [`string_to_reagent`](@ref). We need
# two solid reagents (A and B) and water to dissolve them.

A = string_to_reagent("A", Solid)
B = string_to_reagent("B", Solid)
water = string_to_reagent("water", Liquid)

# Each reagent's stock solution lives in its own deep reservoir.

A_reservoir = build_location(location_kinds[:DeepReservoir])
B_reservoir = build_location(location_kinds[:DeepReservoir])
target_plate = build_location(location_kinds[:WP96])

A_stock = 100u"g" * A + 100u"mL" * water
B_stock = 100u"g" * B + 100u"mL" * water

children(A_reservoir)[1].stock = A_stock
children(B_reservoir)[1].stock = B_stock

# ## Filling the target plate
#
# We fill the 8x8 block of the 96-well target plate so that the volume of
# `A_stock` decreases by 10 µL per row and the volume of `B_stock` decreases
# by 10 µL per column, starting from 80 µL of each.

drug_vol = 80
for row in 1:8
    for col in 1:8
        children(target_plate)[row, col].stock =
            (drug_vol - 10 * (row - 1))u"µL" * A_stock +
            (drug_vol - 10 * (col - 1))u"µL" * B_stock
    end
end

# A heatmap of the target plate shows the checkerboard pattern we just
# created — the combined A/B volume is highest in the top-left corner and
# decreases toward the bottom-right.

plot(target_plate; well_heatmap=true)

# ## Planning and scheduling
#
# We give Pourfecto four candidate configurations to choose from: a
# single-channel pipette, an eight-channel pipette (both orientations), and
# a plate-filling PlateMaster. We run the algorithm twice — once with the
# default `"min_cost_flow"` objective, and once asking Pourfecto to minimize
# the number of *active* flow operations directly.

configs = ["single_channel", "eight_channel_vertical", "eight_channel_horizontal", "plate_master"]

pc_default = pourfecto([A_reservoir, B_reservoir], [target_plate], configs)

pc_min_active = pourfecto(
    [A_reservoir, B_reservoir], [target_plate], configs;
    objective="min_active_flow",
)

# ## Comparing the two schedules
#
# Both objectives should transfer the same total volume of liquid — they're
# solving the same planning problem, just scheduling it differently.

total_flow_default = sum(flows(pc_default))
total_flow_min_active = sum(flows(pc_min_active))

# An "active" flow is any scheduled operation that actually moves liquid
# (as opposed to a zero-volume slot in the flow matrix).

active_default = sum(flows(pc_default) .> 1e-4)
active_min_active = sum(flows(pc_min_active) .> 1e-4)

# `min_active_flow` collapses the schedule toward the eight-channel strategy
# described above, using far fewer discrete operations to deliver the same
# total volume:

(total_flow_default=total_flow_default, total_flow_min_active=total_flow_min_active,
    active_default=active_default, active_min_active=active_min_active)

# With this configuration set, the minimum-active-flow schedule reaches the
# theoretical optimum of 16 operations (one eight-channel dispense per row
# for A, one per column for B).

# ## Checking the plan against the targets
#
# [`planned_stocks`](@ref) reconstructs the stock composition Pourfecto
# actually planned to deliver to each target well. Comparing it against
# [`target_stocks`](@ref) confirms the plan reproduces the requested
# checkerboard pattern.

planned = planned_stocks(pc_min_active)
requested = target_stocks(pc_min_active)

all(isapprox.(planned, requested; rtol=1e-3))

# Finally, [`plot_flows`](@ref) visualizes the scheduled transfers between
# source and target labware for the minimum-active-flow plan.

plot_flows(pc_min_active)
