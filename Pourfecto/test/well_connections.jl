# testing the well connections function that determines which wells are connected to a given aspirate or dispense node

# Matches the old JLIMS-era `isa(l,SLASLabware) || isa(l,brPCR96)` category check: true for any
# well-plate-kind labware (WP96/WP384/DeepWP96/DeepReservoir/DeepWellColumn/DeepWellRow, all tagged
# :WellPlate in CHESSLabConstants) or brPCR96 specifically (its own category, not :WellPlate).
is_wellplate_or_brpcr96(l::Labware) = :WellPlate in kind(l).categories || kind(l).name == :brPCR96

@testset "Well Connections" begin


    for con in collect(keys(configurations))
        for lw in all_labware_kinds




            @testset "Aspirate Well Connections ($con , $lw)" begin

                l = build_location(location_kinds[lw])

                asp_nodes = compute_flow_nodes(AspNode,[configurations[con]],[l])

                for node in asp_nodes
                    p = node.piston
                    connected_channels = sum(aspirate_mask(head(node.mask))[p,:])

                    ch_size = size(aspirate_channels(head(node.mask)))
                    if typeof(ch_size) == Tuple{Int64}
                        ch_size = (ch_size[1],1)
                    end
                    lw_size = CHESSCore.shape(l)
                    if !is_wellplate_or_brpcr96(l) && ch_size != (1,1)
                        @test length(well_connections(node)) == 0
                    else
                        @test length(well_connections(node)) == connected_channels
                    end
                end

            end

            @testset "Dispense Well Connections ($con , $lw)" begin

                l = build_location(location_kinds[lw])

                disp_nodes = compute_flow_nodes(DispNode,[configurations[con]],[l])

                for node in disp_nodes
                    p = node.piston
                    connected_channels = sum(dispense_mask(head(node.mask))[p,:])
                    ch_size = size(dispense_channels(head(node.mask)))
                    if typeof(ch_size) == Tuple{Int64}
                        ch_size = (ch_size[1],1)
                    end
                    if con != "cobra"
                        if !is_wellplate_or_brpcr96(l) && ch_size != (1,1)
                            @test length(well_connections(node)) == 0
                        else
                            @test length(well_connections(node)) == connected_channels
                        end
                    else
                        if !is_wellplate_or_brpcr96(l) && ch_size != (1,1)
                            @test length(well_connections(node)) == 0
                        else
                            @test length(well_connections(node)) <= connected_channels
                        end
                    end

                end

            end
        end
    end

end