using Pourfecto, CHESSCore, Unitful, Random
Random.seed!(48207531)

reagents = [string_to_reagent("R$i",Solid) for i in 1:48]
water = string_to_reagent("water",Liquid)


source_deep_well = build_location(location_kinds[:DeepWP96])



for r in eachindex(reagents)
    st = 2u"ml" * water  + 1u"g" * reagents[r] 
    well = children(source_deep_well)[r]
    well.stock = st
    well2 = children(source_deep_well)[r+length(reagents)]
    well2.stock =st 
end 

water_deep_reservoir = build_location(location_kinds[:DeepReservoir])

children(water_deep_reservoir)[1].stock = 100u"mL" * water 

water_bottle = build_location(location_kinds[:Bottle1L])
children(water_bottle)[1].stock = 1u"L" * water 


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
    push!(target_plates,plt)
end 


priority = PriorityDict("water" => typemax(UInt64))
source_labware = [source_deep_well,water_deep_reservoir,water_bottle]
source_labware2 = [source_deep_well,water_bottle]
configs = ["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"]


pc1 = pourfecto(source_labware,target_plates ,configs;priority=priority,solver_timelimit=45)


pc2 = pourfecto(source_labware2,target_plates,configs;priority=priority,solver_timelimit=45)

pc3 = pourfecto(source_labware,target_plates,configs;priority=priority,objective="min_active_flow",quiet=false,solver_timelimit=100)

a1 = flows(pc1) .> 1e-4
a2 = flows(pc2) .> 1e-4
a3= flows(pc3) .> 1e-4 


@testset "Combinatorial Media" begin 

    @test all_planned_approx_target(pc1;rtol=1e-3) 
    @test all_planned_approx_target(pc2;rtol=1e-3)
    @test all_planned_approx_target(pc3;rtol=1e-3)
    @test sum(flows(pc1)) <= sum(flows(pc2))
    @test sum(a3) <= sum(a1) 

end 

pcs = [pc1,pc2,pc3]

@testset "Combinatorial Media Compilation" begin 
    for n in 1:3 
        test_pourcast_compilation("Combinatorial Media Compilation $n",pcs[n])
    end 
end 









        