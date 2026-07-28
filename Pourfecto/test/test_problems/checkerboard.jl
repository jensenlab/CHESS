using Pourfecto, CHESSCore, Unitful
# define three reagents for the problem 
A = string_to_reagent("A",Solid)
B = string_to_reagent("B",Solid) 
water = string_to_reagent("water",Liquid) 
# generate source and target labware
A_reservoir = build_location(location_kinds[:DeepReservoir])
B_reservoir = build_location(location_kinds[:DeepReservoir])
target_plate = build_location(location_kinds[:WP96])

# fill source reservoirs with liquid 
A_stock=100u"g" * A + 100u"mL" * water 
B_stock =100u"g" * B + 100u"mL" * water

children(A_reservoir)[1].stock = 100u"g" * A + 100u"mL" * water 
children(B_reservoir)[1].stock = 100u"g" * B + 100u"mL" * water 

# fill target plate in a checkerboard pattern 
drug_vol = 80
for row in 1:8 
    for col in 1:8 
        children(target_plate)[row,col].stock = (drug_vol - 10*(row-1))u"µL" * A_stock + (drug_vol-10*(col-1))u"µL" * B_stock 
    end 
end 


pc1 = pourfecto([A_reservoir,B_reservoir],[target_plate],["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"])
pc2 = pourfecto([A_reservoir,B_reservoir],[target_plate],["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"];
objective="min_active_flow")








f1 = flows(pc1)
f2 = flows(pc2)


a1 = flows(pc1) .> 1e-4
a2 = flows(pc2) .> 1e-4


ps1 = planned_stocks(pc1) 
ps2 = planned_stocks(pc2)




@testset "Checkerboard Assay" begin 
    @test isapprox(sum(f1),sum(f2);rtol=1e-3) # The minimum flow solution the same as the minimum active flow solution 
    @test sum(a2) <= sum(a1) # the min active flow solution should have at most as many active flows as the min flow solution. 
    @test all_planned_approx_target(pc1;rtol=1e-3) # ensure the targets are hit within a tolerance of 0.01% 
    @test all_planned_approx_target(pc2;rtol=1e-3) # ensure the targets are all hit within a tolerance of 0.01% 
    @test sum(a2) == 16 # in this case, we know that the optimal schedule contains 16 operations 
end 

test_pourcast_compilation("Checkerboard Compilation 1",pc1)
test_pourcast_compilation("Checkerboard Compilation 2",pc2)











