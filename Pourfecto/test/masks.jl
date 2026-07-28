const all_labware_kinds = [:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96,:Bottle1L,:Bottle500mL,:Bottle250mL,:Conical50,:Conical15]
all_labware = build_location.(getindex.(Ref(location_kinds),all_labware_kinds))

function well_index_matrix(r::Integer,c::Integer) 
    return reshape(1:prod((r,c)),r,c)
end 

function slider(instrument::Union{BitVector,Vector{Bool}},framesize=12)
    l = length(instrument)
    counts = zeros(Int64,framesize) 
    N = max(framesize -l + 1,0) 
    for i in 1:N 
        for j in eachindex(instrument)
            counts[i+j-1] += instrument[j] 
        end 
    end 
    return counts 
end  

@testset "Masks" begin 


    @testset "single channel masks" begin 

        single_channels = filter(x-> x isa Configuration{SingleChannel},collect(values(configurations)))
            for sc in single_channels
            for lw in all_labware 
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(sc),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(sc))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == fill(1,r,c) # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(sc))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == fill(1,r,c)
            end 
        end 
    end 


    @testset "eight channel vertical masks" begin 
                vertical_eights = [
            "p1000_8_vertical",
            "p100_8_vertical",
            "p10_8_vertical"
        ]
        eight_channels = map(x->configurations[x],vertical_eights)
        visits =Dict(
            :WP96 => fill(1,8,12),
            :WP384 => fill(1,16,24),
            :DeepWP96 => fill(1,8,12) ,
            :DeepReservoir => fill(8,1,1), 
            :DeepWellColumn => fill(8,1,12),
            :DeepWellRow => fill(1,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(1,8,12)
        )
        for ec in eight_channels
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(ec),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == visits[lw_type]
            end
        end

    end

    @testset "eight channel horizontal masks" begin
                horizontal_eights = [
            "p1000_8_horizontal",
            "p100_8_horizontal",
            "p10_8_horizontal"
        ]
        eight_channels = map(x->configurations[x],horizontal_eights)
        visits =Dict(
            :WP96 => vcat(fill(permutedims(slider(trues(8),12)),8)...),
            :WP384 => vcat(fill(permutedims(slider(repeat([true,false],8)[1:15],24)),16)...),
            :DeepWP96 => vcat(fill(permutedims(slider(trues(8),12)),8)...) ,
            :DeepReservoir => fill(8,1,1), 
            :DeepWellColumn => permutedims(slider(trues(8),12)),
            :DeepWellRow => fill(8,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => vcat(fill(permutedims(slider(trues(8),12)),8)...)
        )
        for ec in eight_channels
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(ec),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == visits[lw_type]
            end
        end

    end


    @testset "plate master masks" begin

        pm = configurations["plate_master"]
        visits =Dict(
            :WP96 => fill(1,8,12),
            :WP384 => fill(1,16,24),
            :DeepWP96 => fill(1,8,12) ,
            :DeepReservoir => fill(96,1,1), 
            :DeepWellColumn => fill(8,1,12),
            :DeepWellRow => fill(12,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(1,8,12)
        )

            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(pm),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(pm))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(pm))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == visits[lw_type]
            end

    end 


    @testset "cobra masks" begin 

        # We don't include the proper mask answers for the DeepReservoir, DeepWellColumn, and DeepWell Row labware because we don't have cobra definitions for those labware, so the "correct" answer is that they cannot visit. 
        asp_visits =Dict(
            :WP96 => hcat(fill(slider(trues(4),8),12)...),
            :WP384 => hcat(fill(slider(repeat([true,false],4)[1:7],16),24)...),
            :DeepWP96 => hcat(fill(slider(trues(4),8),12)...),
            #:DeepReservoir => fill(4,1,1), 
            #:DeepWellColumn => fill(4,1,12),
            #:DeepWellRow => slider(trues(4),8), 
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1),
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(0,8,12)
        )

        disp_visits =Dict(
            :WP96 => fill(4,8,12),
            :WP384 => fill(4,16,24),
            :DeepWP96 => fill(4,8,12),
            #:DeepReservoir => fill(4,1,1), 
            #:DeepWellColumn => fill(4,1,12),
            #:DeepWellRow => fill(4,8,1), 
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(0,8,12)
        )
        for ec in [configurations["cobra"]]
            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(asp_visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(ec),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == asp_visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(ec))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == disp_visits[lw_type]
            end
        end 

    end 


    @testset "mantis masks" begin 

        conf = configurations["mantis"]
        asp_visits =Dict(
            :WP96 => fill(0,8,12),
            :WP384 => fill(0,16,24),
            :DeepWP96 => fill(0,8,12) ,
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1), 
            :Bottle => fill(1,1,1),
            :Conical => fill(1,1,1),
            :brPCR96 => fill(0,8,12)
        )
        disp_visits =Dict(
            :WP96 => fill(1,8,12),
            :WP384 => fill(1,16,24),
            :DeepWP96 => fill(0,8,12) ,
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(1,8,12)
        )


            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(asp_visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(conf),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(conf))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == asp_visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(conf))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == disp_visits[lw_type]
            end

    end


        @testset "tempest masks" begin

        conf = configurations["tempest"]
        asp_visits =Dict(
            :WP96 => fill(0,8,12),
            :WP384 => fill(0,16,24),
            :DeepWP96 => fill(0,8,12) ,
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1),
            :Bottle => fill(1,1,1), # only 1 aspirate channel exists physically -- the previous value of 8 was an artifact of the aspirate/dispense channel-count conflation this Head redesign fixes
            :Conical => fill(1,1,1),
            :brPCR96 => fill(0,8,12)
        )
        disp_visits =Dict(
            :WP96 => fill(1,8,12),
            :WP384 => fill(1,16,24),
            :DeepWP96 => fill(0,8,12) ,
            :DeepReservoir => fill(0,1,1), 
            :DeepWellColumn => fill(0,1,12),
            :DeepWellRow => fill(0,8,1), 
            :Bottle => fill(0,1,1),
            :Conical => fill(0,1,1),
            :brPCR96 => fill(0,8,12)
        )


            for lw in all_labware
                lw_type = labware_key(lw,collect(keys(asp_visits)))
                r,c= CHESSCore.shape(lw)
                W = well_index_matrix(r,c)
                mask = Mask(head(conf),lw)
                P = prod(asp_positions(mask))
                C_asp = prod(size(aspirate_channels(head(conf))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_asp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->asp(mask)(x,y...),PC)),W) == asp_visits[lw_type] # each well should be visited just once in all mask possibilities
                P = prod(disp_positions(mask))
                C_disp = prod(size(dispense_channels(head(conf))))
                PC = Tuple.(collect.(Iterators.product(1:P,1:C_disp)))
                if length(PC) == 0
                    PC = [(0,0)]
                end
                @test map(x->sum(map(y->disp(mask)(x,y...),PC)),W) == disp_visits[lw_type]
            end

    end

end