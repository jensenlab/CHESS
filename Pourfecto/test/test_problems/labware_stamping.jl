using Pourfecto, CHESSCore, Unitful, JuMP
# define three reagents for the problem 
A = string_to_reagent("A",Solid)
B = string_to_reagent("B",Solid) 
water = string_to_reagent("water",Liquid) 
# generate source and target labware
A_reservoir = build_location(location_kinds[:DeepWP96])
B_reservoir = build_location(location_kinds[:DeepWP96])
AB_reservoir = build_location(location_kinds[:DeepWP96])

target_plate = build_location(location_kinds[:WP96])

# fill source reservoirs with liquid 
A_stock=2u"g" * A + 2u"mL" * water 
B_stock =2u"g" * B + 2u"mL" * water

for row in 1:8 
children(A_reservoir)[row,1].stock = A_stock
children(B_reservoir)[row,1].stock = B_stock
end 

children(AB_reservoir)[1,1].stock =A_stock 
children(AB_reservoir)[2,1].stock =B_stock 


for row in 1:8 
    children(target_plate)[row,1].stock = 200u"µL" * A_stock 
    children(target_plate)[row,2].stock = 200u"µL" *B_stock 
end 

configs_lw_stamp = ["single_channel","eight_channel_vertical"]
src_labware = [A_reservoir,B_reservoir,AB_reservoir]
tgt_labware = [target_plate]

pc1 = pourfecto(src_labware,tgt_labware,configs_lw_stamp)
pc2 =  pourfecto(src_labware,tgt_labware,configs_lw_stamp;objective = "min_active_flow") # should be equivalent to min_flow 
pc3 = pourfecto(src_labware,tgt_labware,configs_lw_stamp;objective = "min_sources")
pc4 = pourfecto(src_labware,tgt_labware,configs_lw_stamp;objective = "min_labware")
pc5 = pourfecto(src_labware,tgt_labware,configs_lw_stamp;objective = "min_config")

lim = 1e-4 


@testset "Eight Channel Stamping" begin 
    @test sum(flows(pc1)) <= 400 # best case using the eight channel 
    @test sum(flows(pc1)) <= sum(flows(pc2)) # with a cost weight of 1, min_cost_flow solutions are strictly better than min active flow when comparing sum flow. 
    @test sum(flows(pc2) .>= lim ) == 2 # the schedule can be completed with two active flows 
    @test scheduling_objective_value(pc3) ≈ 2 # min sources:  all of the transfers **could** be made with just two source wells, one for reagent A and one for B 
    @test scheduling_objective_value(pc4) ≈ 1 # min_labware: the schedule could be completed by just using the AB_reservoir  
    @test scheduling_objective_value(pc5) ≈ 1 # min_config:  either the single channel or the eight channel could be used, but we do not need both. 

end 

pcs = [pc1,pc2,pc3,pc4,pc5]

@testset "Eight Channel Stamping Compilation" begin 
    for n in eachindex(pcs)
        test_pourcast_compilation("Eight Channel Stamping Compilation $n",pcs[n])
    end 
end 
