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

src_labware = [A_reservoir,B_reservoir,AB_reservoir]
tgt_labware = [target_plate]

pc1 = pourfecto(src_labware,tgt_labware,["single_channel","eight_channel_vertical"])



pc1_json  = pourcast_to_json(pc1)

pc2 = json_to_pourcast(pc1_json)

pc2_json = pourcast_to_json(pc2) 


function write_read_json_roundtrip(pc::Pourcast; basename::AbstractString="pourcast.json")
    mktempdir() do dir
        path = joinpath(dir, basename)
        open(path, "w") do io
            write(io, pourcast_to_json(pc))
        end
        pc2 = json_to_pourcast(read(path, String))
        @testset "Pourcast JSON file round-trip" begin

    # ---- Act: write to temp dir and read back ---

    # ---- Assert: file exists and essential structure matches ----
    @test isfile(path)
    @test typeof(pc2) == typeof(pc)
        end
    end
end


write_read_json_roundtrip(pc1)

@testset "Configuration.kind links Layer 2 to a real Layer 1 LocationKind" begin
    @test configurations["nimbus"].kind === CHESSCore.location_kinds[:Nimbus]
    @test configurations["mantis"].kind === CHESSCore.location_kinds[:Mantis]
    @test configurations["tempest"].kind === CHESSCore.location_kinds[:Tempest]
    @test configurations["cobra"].kind === CHESSCore.location_kinds[:Cobra]
    @test configurations["plate_master"].kind === CHESSCore.location_kinds[:Gilson] # Gilson's catalog is "PlateMaster"
    @test isnothing(configurations["single_channel"].kind) # handheld pipette -- no physical LocationKind
    @test CHESSCore.name(configurations["nimbus"]) == "Nimbus"
    @test CHESSCore.name(configurations["single_channel"]) == string(SingleChannel)

    # kind round-trips through config_to_json/json_to_config -- pc1's own configs (single_channel,
    # eight_channel_vertical) only exercise the `kind === nothing` case above, so check a kind-bearing
    # config directly too.
    cfg = configurations["nimbus"]
    cfg2 = Pourfecto.json_to_config(Pourfecto.config_to_json(cfg))
    @test cfg2.kind === cfg.kind

    cfg_nothing = configurations["single_channel"]
    cfg_nothing2 = Pourfecto.json_to_config(Pourfecto.config_to_json(cfg_nothing))
    @test isnothing(cfg_nothing2.kind)
end