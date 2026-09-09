using Pourfecto, CHESSCore, Unitful
# define an organism and a chemical reagent, scheduled together in the same problem, to confirm
# organism inoculation flows through the same volume-conservation LP as chemical transfers now
# that Organism <: StockComponent and CHESSCore exposes quantity/concentration for it.
organism = Organism("Genus","species","strain")
drug = string_to_component("drug",Solid)
water = string_to_component("water",Liquid)

culture_reservoir = build_location(location_kinds[:DeepReservoir])
drug_reservoir = build_location(location_kinds[:DeepReservoir])
target_plate = build_location(location_kinds[:WP96])

culture_stock = 5u"OD*mL" * organism + 100u"mL" * water
drug_stock = 100u"g" * drug + 100u"mL" * water

children(culture_reservoir)[1].stock = culture_stock
children(drug_reservoir)[1].stock = drug_stock

# checkerboard pattern: organism dose decreases across rows, drug dose decreases across columns
for row in 1:8
    for col in 1:8
        children(target_plate)[row,col].stock =
            (80 - 10*(row-1))u"µL" * culture_stock + (80 - 10*(col-1))u"µL" * drug_stock
    end
end

pc = pourfecto([culture_reservoir,drug_reservoir],[target_plate],
    ["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"])

@testset "Organism Scheduling" begin
    @test all_planned_approx_target(pc;rtol=1e-3) # organism biomass and drug mass both hit target within tolerance
    @test organism in all_components([culture_stock])
    @test CHESSCore.quantity(planned_stocks(pc)[1],organism) > 0u"mL*OD" # some biomass was actually scheduled, not silently dropped
end

test_pourcast_compilation("Organism Scheduling Compilation",pc)
