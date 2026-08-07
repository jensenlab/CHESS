import Pourfecto: convert_design, batch_design

@testset "Nimbus Batching" begin

    @testset "grid_distance" begin
        @test grid_distance(CartesianIndex(1,1),CartesianIndex(1,1)) == 0.0
        @test grid_distance(CartesianIndex(1,1),CartesianIndex(4,5)) == 5.0 # 3-4-5 triangle
        @test grid_distance(CartesianIndex(2,3),CartesianIndex(2,7)) == 4.0
    end

    @testset "split_oversized" begin
        items = [DispenseItem(1,CartesianIndex(1,1),2500), DispenseItem(2,CartesianIndex(1,2),600)]
        out = split_oversized(items,1000)
        @test sum(i.volume for i in out) == 3100
        @test count(i -> i.col == 1, out) == 3
        @test [i.volume for i in out if i.col == 1] == [1000,1000,500]
        @test count(i -> i.col == 2, out) == 1
        @test all(i.volume <= 1000 for i in out)
    end

    @testset "cluster_batches" begin
        # a tight 3x3 cluster of small-volume items, plus two far-away singletons
        cluster = [DispenseItem(i,CartesianIndex(1+((i-1)÷3),1+((i-1)%3)),100) for i in 1:9]
        far1 = DispenseItem(10,CartesianIndex(20,20),100)
        far2 = DispenseItem(11,CartesianIndex(1,20),100)
        items = vcat(cluster,[far1,far2])

        batches = cluster_batches(items,300) # 3 items/batch max by volume
        @test sum(length(b) for b in batches) == length(items)
        @test allunique(vcat([[i.col for i in b] for b in batches]...)) # every item assigned exactly once
        @test all(sum(i.volume for i in b) <= 300 for b in batches) # capacity respected

        # distance-aware packing should always prefer a cluster item's tight cluster-neighbors
        # over the much-farther-away singletons -- no batch should ever mix a cluster item with
        # a far singleton, since a nearer same-cluster candidate is always available first
        far_cols = Set([far1.col,far2.col])
        cluster_cols = Set(i.col for i in cluster)
        @test all(b -> isempty(Set(i.col for i in b) ∩ far_cols) || isempty(Set(i.col for i in b) ∩ cluster_cols), batches)

        # naive first-fit-by-index would freely mix cluster items with far items; distance-aware
        # packing should keep the tight cluster's items grouped together more than that baseline
        same_batch_pairs = sum(count(i -> i.col in cluster_cols, b) > 1 ? 1 : 0 for b in batches)
        @test same_batch_pairs >= 1
    end

    @testset "order_greedy vs order_exact" begin
        # 4 points on a line: optimal tour visits them in line order regardless of start
        line = [DispenseItem(1,CartesianIndex(1,1),0),DispenseItem(2,CartesianIndex(1,2),0),
                DispenseItem(3,CartesianIndex(1,3),0),DispenseItem(4,CartesianIndex(1,4),0)]
        tour_len(t) = sum(grid_distance(t[i].position,t[i+1].position) for i in 1:length(t)-1)

        greedy = order_greedy(line)
        exact = order_exact(line)
        @test tour_len(exact) <= tour_len(greedy)
        @test tour_len(exact) == 3.0 # optimal: straight line, total length 3
        @test Set(i.col for i in exact) == Set(i.col for i in line) # same items, just reordered

        # a case where nearest-neighbor greedy is provably suboptimal: points at 0, 1, 10, 11 on a
        # line, starting at 0 -- greedy goes 0->1->10->11 (length 1+9+1=11), which happens to be
        # optimal here too, so use an asymmetric layout instead where greedy's local choice traps it
        trap = [DispenseItem(1,CartesianIndex(1,1),0),DispenseItem(2,CartesianIndex(1,10),0),
                DispenseItem(3,CartesianIndex(1,12),0),DispenseItem(4,CartesianIndex(1,21),0)]
        # starting from item 1 (col=1,pos=1): nearest is col=10 (dist 9) before col=12 or col=21,
        # so greedy visits 1,10,12,21 in that order here too -- instead force suboptimality by
        # starting the tour where the nearest neighbor isn't part of the globally shortest path
        maze = [DispenseItem(1,CartesianIndex(1,1),0),DispenseItem(2,CartesianIndex(1,2),0),
                DispenseItem(3,CartesianIndex(1,100),0),DispenseItem(4,CartesianIndex(1,3),0)]
        @test tour_len(order_exact(maze)) <= tour_len(order_greedy(maze))
    end

    @testset "tip_change_flags" begin
        sources = [:A,:A,:B,:B,:B,:B,:B,:B,:B,:B,:B,:C]
        flags = tip_change_flags(sources,3)
        @test flags[1] == 0 # never forced on the very first aspirate
        @test flags[3] == 1 # source change A -> B
        @test flags[12] == 1 # source change B -> C
        @test flags[2] == 0 # no change, no window trigger yet
        # somewhere within the long B run, the windowsize=3 heuristic should force a change even
        # without a source change
        @test any(flags[4:11] .== 1)
    end

    @testset "convert_design / batch_design / write_instrument_files integration" begin
        source1 = build_location(location_kinds[:Conical50],"nimbus_batch_test_source1")
        source2 = build_location(location_kinds[:Conical50],"nimbus_batch_test_source2")
        target = build_location(location_kinds[:DeepWP96],"nimbus_batch_test_target")
        sources = Labware[source1,source2]
        targets = Labware[target]
        config = configurations["nimbus"]
        slotting = slotting_greedy(vcat(sources,targets),config)

        R,C = size(target) # 8 rows x 12 cols, column-major linear index
        well_col(letter_row,col) = (col-1)*R + letter_row

        design = DataFrame(zeros(2,R*C),:auto)
        # source1: one oversized transfer (A1, 1500uL) plus several small ones (A2-A5, 300uL each)
        design[1,well_col(1,1)] = 1500
        design[1,well_col(1,2)] = 300
        design[1,well_col(1,3)] = 300
        design[1,well_col(1,4)] = 300
        design[1,well_col(1,5)] = 300
        # source2: a couple of small transfers, well within a single batch
        design[2,well_col(1,6)] = 200
        design[2,well_col(1,7)] = 200

        for batch_ordering in (:greedy,:exact)
            df = convert_design(design,sources,targets,slotting,config)
            action_df,aspirate_idx,batch_sources = batch_design(df,config;batch_ordering)
            action_df[aspirate_idx,"Change Tip Before"] .= tip_change_flags(batch_sources,settings(config)["max_tip_use"])

            @test names(action_df) == ["Labware ID","Labware Position ID","Volume (uL)","Aspirate","Dispense","Change Tip Before"]
            @test all(row -> (row.Aspirate == 1) != (row.Dispense == 1), eachrow(action_df)) # exactly one of the two set
            @test all(<=(1000), action_df[!,"Volume (uL)"]) # capacity respected everywhere

            n = nrow(action_df)
            for (k,i) in enumerate(aspirate_idx)
                block_end = k < length(aspirate_idx) ? aspirate_idx[k+1]-1 : n
                dispense_sum = sum(action_df[i+1:block_end,"Volume (uL)"])
                @test isapprox(dispense_sum,action_df[i,"Volume (uL)"];atol=1e-6)
                @test all(action_df[i+1:block_end,"Dispense"] .== 1)
                @test all(action_df[i+1:block_end,"Change Tip Before"] .== 0) # only aspirate rows can flag a change
            end

            @test sum(action_df[aspirate_idx,"Volume (uL)"]) == 1500+300*4+200*2

            # source2's first batch must have Change Tip Before = 1 (a genuine source change)
            source2_first_aspirate = aspirate_idx[findfirst(s -> s == batch_sources[end],batch_sources)]
            @test action_df[source2_first_aspirate,"Change Tip Before"] == 1
            # very first aspirate overall is never forced
            @test action_df[aspirate_idx[1],"Change Tip Before"] == 0

            mktempdir() do dir
                outdir = joinpath(dir,"nimbus_batch_test")
                write_instrument_files(outdir,design,sources,targets,config,slotting;batch_ordering)
                written = CSV.read(joinpath(outdir,"nimbus_batch_test.csv"),DataFrame)
                @test names(written) == names(action_df)
                @test nrow(written) == nrow(action_df)
            end
        end
    end

end
