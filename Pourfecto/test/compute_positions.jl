const all_labware_kinds = [:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96,:Bottle1L,:Bottle500mL,:Bottle250mL,:FilterBottle1L,:Conical50,:Conical15]
all_labware = build_location.(getindex.(Ref(location_kinds),all_labware_kinds))

# A labware matches a `lw_sizes`/`*_spacing_dict` key either by its exact LocationKind name (for
# kinds tested individually, e.g. :WP96) or by category (for :Bottle/:Conical, which group several
# specific kinds under one expected value, mirroring the old JLIMS-era Bottle/Conical supertypes).
function labware_key(lw::Labware, keys)
    n = kind(lw).name
    n in keys && return n
    c = findfirst(x -> x in kind(lw).categories, keys)
    return keys[c]
end

@testset "Compute Positions" begin


    @testset "single channel positions" begin
        single_channels = filter(x-> x isa Configuration{SingleChannel},collect(values(configurations)))
        for sc in single_channels
            for lw in all_labware
                @test compute_positions(head(sc),lw,:aspirate) == CHESSCore.shape(lw)
            end
        end
    end

    @testset "eight channel vertical positions" begin
        vertical_eights = [
            "p1000_8_vertical",
            "p100_8_vertical",
            "p10_8_vertical"
        ]
        eight_channels = map(x->configurations[x],vertical_eights)
        lw_sizes =Dict(
            :WP96 => (1,12),
            :WP384 => (2,24),
            :DeepWP96 => (1,12) ,
            :DeepReservoir => (1,1),
            :DeepWellColumn => (1,12),
            :DeepWellRow => (1,1),
            :Bottle => (0,1),
            :Conical => (0,1),
            :brPCR96 => (1,12)
        )
        v_spacing_dict=Dict(
            :WP96=> 1 ,
            :WP384=> 2,
            :DeepWP96 => 1,
            :DeepReservoir => 1,
            :DeepWellColumn => 1,
            :DeepWellRow => 1,
            :Bottle => 1 ,
            :Conical => 1,
            :brPCR96 => 1
        )
        for ec in eight_channels
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(lw_sizes)))
                @test compute_positions(head(ec),lw,:aspirate;v_spacing= v_spacing_dict[lw_type] ) == lw_sizes[lw_type]
            end
        end
    end

    @testset "eight channel horizontal positions" begin
        horizontal_eights = [
            "p1000_8_horizontal",
            "p100_8_horizontal",
            "p10_8_horizontal"
        ]
        eight_channels = map(x->configurations[x],horizontal_eights)
        lw_sizes =Dict(
            :WP96 => (8,5),
            :WP384 => (16,10),
            :DeepWP96 => (8,5) ,
            :DeepReservoir => (1,1),
            :DeepWellColumn => (1,5),
            :DeepWellRow => (8,1),
            :Bottle => (1,0),
            :Conical => (1,0) ,
            :brPCR96 => (8,5)
        )
        h_spacing_dict=Dict(
            :WP96=> 1 ,
            :WP384=> 2,
            :DeepWP96 => 1,
            :DeepReservoir => 1,
            :DeepWellColumn => 1,
            :DeepWellRow => 1,
            :Bottle => 1 ,
            :Conical => 1,
            :brPCR96 => 1
        )
        for ec in eight_channels
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(lw_sizes)))
                @test compute_positions(head(ec),lw,:aspirate;h_spacing= h_spacing_dict[lw_type] ) == lw_sizes[lw_type]
            end
        end
    end


    @testset "plate master positions" begin

        pm = configurations["plate_master"]
        lw_sizes =Dict(
            :WP96 => (1,1),
            :WP384 => (2,2),
            :DeepWP96 => (1,1) ,
            :DeepReservoir => (1,1),
            :DeepWellColumn => (1,1),
            :DeepWellRow => (1,1),
            :Bottle => (0,0),
            :Conical => (0,0),
            :brPCR96 => (1,1)
        )
        v_spacing_dict=Dict(
            :WP96=> 1 ,
            :WP384=> 2,
            :DeepWP96 => 1,
            :DeepReservoir => 1,
            :DeepWellColumn => 1,
            :DeepWellRow => 1,
            :Bottle => 1 ,
            :Conical => 1,
            :brPCR96 => 1
        )
            h_spacing_dict=Dict(
            :WP96=> 1 ,
            :WP384=> 2,
            :DeepWP96 => 1,
            :DeepReservoir => 1,
            :DeepWellColumn => 1,
            :DeepWellRow => 1,
            :Bottle => 1 ,
            :Conical => 1,
            :brPCR96 => 1
        )
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(lw_sizes)))
                @test compute_positions(head(pm),lw,:aspirate;v_spacing= v_spacing_dict[lw_type],h_spacing=h_spacing_dict[lw_type] ) == lw_sizes[lw_type]
            end
    end

end


