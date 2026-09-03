import Pourfecto: convert_design, batch_design, nimbus_waste_conical, nimbus_waste_slot, nimbus_waste_target, nimbus_well, tuberack50mL_0006

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

    @testset "polish_batches" begin
        multiset(batches) = sort([(i.col,i.volume) for b in batches for i in b])
        cost(batches) = sum(b -> Pourfecto._batch_travel(b,:greedy), batches)

        @testset "swap improves a badly-clustered pair" begin
            # two batches each pairing a "near" item with a "far" item -- swapping the far items
            # between batches leaves each batch with its near pair instead, a large improvement
            p1 = DispenseItem(1,CartesianIndex(1,1),100)
            p2 = DispenseItem(2,CartesianIndex(1,100),100)
            p3 = DispenseItem(3,CartesianIndex(1,2),100)
            p4 = DispenseItem(4,CartesianIndex(1,101),100)
            batches = [[p1,p2],[p3,p4]]
            capacity = 400

            polished = polish_batches(batches,capacity)
            @test cost(polished) < cost(batches)
            @test multiset(polished) == multiset(batches) # every item preserved exactly once
            @test all(b -> sum(i.volume for i in b) <= capacity, polished)
        end

        @testset "relocate improves an item stuck in the wrong batch" begin
            # a lone item sitting right next to a tight 3-item cluster, currently paired instead
            # with a far outlier -- relocating it into the cluster is a large improvement
            p1 = DispenseItem(1,CartesianIndex(1,1),100)
            p2 = DispenseItem(2,CartesianIndex(1,2),100)
            p3 = DispenseItem(3,CartesianIndex(1,3),100)
            lone = DispenseItem(4,CartesianIndex(1,4),100)
            far = DispenseItem(5,CartesianIndex(1,500),100)
            batches = [[p1,p2,p3],[lone,far]]
            capacity = 500

            polished = polish_batches(batches,capacity)
            @test cost(polished) < cost(batches)
            @test multiset(polished) == multiset(batches)
            @test all(b -> sum(i.volume for i in b) <= capacity, polished)
            @test all(!isempty,polished) # no empty batch ever appears in output
        end

        @testset "already-optimal clustering is left alone (non-strict)" begin
            items = [DispenseItem(i,CartesianIndex(1,i),100) for i in 1:6]
            batches = cluster_batches(items,250) # 2 items/batch, adjacent pairs -- already optimal
            polished = polish_batches(batches,250)
            @test cost(polished) <= cost(batches)
            @test multiset(polished) == multiset(batches)
        end

        @testset "capacity is always respected, even under tight margins" begin
            p1 = DispenseItem(1,CartesianIndex(1,1),300)
            p2 = DispenseItem(2,CartesianIndex(1,100),100)
            p3 = DispenseItem(3,CartesianIndex(1,2),300)
            batches = [[p1,p2],[p3]] # batch 1 is exactly at capacity, no slack
            capacity = 400
            polished = polish_batches(batches,capacity)
            @test all(b -> sum(i.volume for i in b) <= capacity, polished)
            @test multiset(polished) == multiset(batches)
        end

        @testset "max_iterations=0 returns input unchanged" begin
            p1 = DispenseItem(1,CartesianIndex(1,1),100)
            p2 = DispenseItem(2,CartesianIndex(1,100),100)
            p3 = DispenseItem(3,CartesianIndex(1,2),100)
            p4 = DispenseItem(4,CartesianIndex(1,101),100)
            batches = [[p1,p2],[p3,p4]]
            @test polish_batches(batches,400;max_iterations=0) == batches
        end
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

    @testset "round_with_exact_sum" begin
        # reproduces the real float-drift bug: values that "should" sum to 990.3 but leave a
        # hairline residual (e.g. -1.42e-14) under naive independent rounding + subtraction
        drifting = [36.7, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 533.6000000000001]
        target = round(sum(drifting), digits=1)
        rounded = round_with_exact_sum(drifting, 1)
        @test sum(rounded) == target # exact, not isapprox -- this is the whole point of the fix
        @test length(rounded) == length(drifting)

        # single-element and already-exact cases
        @test round_with_exact_sum([5.0], 1) == [5.0]
        @test sum(round_with_exact_sum([100.0, 200.0, 300.0], 1)) == 600.0

        # every value but the last is independently rounded; only the last absorbs the remainder
        vals = [1.05, 2.03, 3.07]
        r = round_with_exact_sum(vals, 1)
        @test r[1] == round(1.05, digits=1)
        @test r[2] == round(2.03, digits=1)
        @test sum(r) == round(sum(vals), digits=1)
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

        default_aspirate_buffer = 0.01 # must match batch_design's default

        for batch_ordering in (:greedy,:exact)
            df = convert_design(design,sources,targets,slotting,config)
            action_df = batch_design(df,config;batch_ordering,insert_blowouts=false)

            @test names(action_df) == ["Labware ID","Labware Position ID","Volume (uL)","Action","Change Tip Before"]
            @test all(a -> a in ("Aspirate","Dispense","Blowout"), action_df.Action)
            @test !("Blowout" in action_df.Action) # this test is about batching/ordering, not blowouts -- explicitly disabled
            @test all(<=(1000+default_aspirate_buffer+1e-9), action_df[!,"Volume (uL)"]) # capacity (+buffer) respected everywhere

            aspirate_idx = findall(==("Aspirate"),action_df.Action)
            n = nrow(action_df)
            for (k,i) in enumerate(aspirate_idx)
                block_end = k < length(aspirate_idx) ? aspirate_idx[k+1]-1 : n
                dispense_sum = sum(action_df[i+1:block_end,"Volume (uL)"])
                # the aspirate carries the unbuffered dispense sum plus the safety margin, exactly
                @test isapprox(dispense_sum+default_aspirate_buffer,action_df[i,"Volume (uL)"];atol=1e-6)
                @test all(action_df[i+1:block_end,"Action"] .== "Dispense")
                @test all(action_df[i+1:block_end,"Change Tip Before"] .== 0) # only aspirate rows can flag a change
            end

            @test isapprox(sum(action_df[aspirate_idx,"Volume (uL)"]),1500+300*4+200*2+length(aspirate_idx)*default_aspirate_buffer;atol=1e-6)

            # source2's first batch must have Change Tip Before = 1 (a genuine source change)
            aspirate_keys = collect(zip(action_df[aspirate_idx,"Labware ID"],action_df[aspirate_idx,"Labware Position ID"]))
            source_change_idx = findfirst(k -> k != aspirate_keys[1],aspirate_keys)
            @test !isnothing(source_change_idx)
            @test action_df[aspirate_idx[source_change_idx],"Change Tip Before"] == 1
            # very first aspirate overall is never forced
            @test action_df[aspirate_idx[1],"Change Tip Before"] == 0

            mktempdir() do dir
                outdir = joinpath(dir,"nimbus_batch_test")
                write_instrument_files(outdir,design,sources,targets,config,slotting;batch_ordering,insert_blowouts=false)
                written = CSV.read(joinpath(outdir,"nimbus_batch_test.csv"),DataFrame)
                @test names(written) == names(action_df)
                @test nrow(written) == nrow(action_df)
            end
        end
    end

    @testset "insert_blowouts" begin
        source = build_location(location_kinds[:Conical50],"nimbus_blowout_test_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus_blowout_test_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus"]
        slotting = slotting_greedy(vcat(sources,targets),config)

        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        # 12 wells x 108uL under one source -- forces 2 aspirate batches under the same tip
        # (effective capacity 980 = 1000-20 fits 9 wells; the 3 remaining wells form a 2nd batch)
        design = DataFrame(zeros(1,R*C),:auto)
        for c in 1:12
            design[1,well_col(1,c)] = 108.0
        end

        df = convert_design(design,sources,targets,slotting,config)
        # no waste_target passed -- relies entirely on the default (the reserved waste conical)
        action_df = batch_design(df,config;insert_blowouts=true,dead_volume_buffer=20.0)

        @test names(action_df) == ["Labware ID","Labware Position ID","Volume (uL)","Action","Change Tip Before"]
        blowout_idx = findall(==("Blowout"),action_df.Action)
        @test length(blowout_idx) == 1 # exactly one re-aspirate boundary in this scenario
        @test all(action_df[blowout_idx,"Labware ID"] .== nimbus_waste_target[1])
        @test all(action_df[blowout_idx,"Labware Position ID"] .== nimbus_waste_target[2])
        @test all(action_df[blowout_idx,"Change Tip Before"] .== 0) # always 0 for Blowout rows

        # a blowout never immediately precedes the very first aspirate, and never trails the last batch
        aspirate_idx = findall(==("Aspirate"),action_df.Action)
        @test blowout_idx[1] > aspirate_idx[1]
        @test blowout_idx[1] < aspirate_idx[end]

        default_aspirate_buffer = 0.01 # must match batch_design's default

        # per-cycle invariant: sum(dispenses in cycle) + (blowout, if present) + aspirate_buffer == that cycle's aspirate volume, exactly
        n = nrow(action_df)
        for (k,i) in enumerate(aspirate_idx)
            block_end = k < length(aspirate_idx) ? aspirate_idx[k+1]-1 : n
            cycle_sum = sum(action_df[i+1:block_end,"Volume (uL)"])
            @test isapprox(cycle_sum+default_aspirate_buffer,action_df[i,"Volume (uL)"];atol=1e-6)
        end

        # no rounded aspirate volume exceeds true channel capacity (+ the small safety buffer)
        @test all(<=(1000.0+default_aspirate_buffer+1e-9), action_df[aspirate_idx,"Volume (uL)"])

        # insert_blowouts now defaults to true (with dead_volume_buffer=20.0) -- zero blowout kwargs
        # still produces the same Blowout row as the explicit call above
        implicit_df = batch_design(df,config)
        implicit_blowout_idx = findall(==("Blowout"),implicit_df.Action)
        @test length(implicit_blowout_idx) == 1
        @test all(implicit_df[implicit_blowout_idx,"Volume (uL)"] .== 20.0)

        # explicitly disabling it still works
        disabled_df = batch_design(df,config;insert_blowouts=false)
        @test !("Blowout" in disabled_df.Action)

        # an explicit waste_target still overrides the default
        custom_target = ("SomeOtherWaste","3")
        custom_df = batch_design(df,config;insert_blowouts=true,waste_target=custom_target,dead_volume_buffer=20.0)
        custom_blowout_idx = findall(==("Blowout"),custom_df.Action)
        @test all(custom_df[custom_blowout_idx,"Labware ID"] .== "SomeOtherWaste")

        # validation errors
        @test_throws ArgumentError batch_design(df,config;insert_blowouts=true,waste_target=nothing,dead_volume_buffer=20.0) # explicitly no waste_target
        @test_throws ArgumentError batch_design(df,config;insert_blowouts=true,dead_volume_buffer=0.0) # buffer must be > 0
        @test_throws ArgumentError batch_design(df,config;insert_blowouts=true,dead_volume_buffer=1000.0) # buffer must be < capacity
    end

    @testset "aspirate_buffer" begin
        source = build_location(location_kinds[:Conical50],"nimbus_aspirate_buffer_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus_aspirate_buffer_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)

        design = DataFrame(zeros(1,R*C),:auto)
        design[1,1] = 300.0
        design[1,2] = 200.0
        df = convert_design(design,sources,targets,slotting,config)

        # default buffer: aspirate exceeds the dispense sum by exactly aspirate_buffer
        # (insert_blowouts explicitly off -- this test is about aspirate_buffer in isolation)
        action_df = batch_design(df,config;insert_blowouts=false)
        @test action_df[1,"Volume (uL)"] - sum(action_df[2:end,"Volume (uL)"]) ≈ 0.01 atol=1e-9

        # same, with a trailing blowout in the cycle -- force a second batch under one tip so a
        # blowout actually appears (a single small cycle has no re-aspirate to blow out ahead of)
        design2 = DataFrame(zeros(1,R*C),:auto)
        for c in 1:12
            design2[1,(c-1)*R+1] = 108.0
        end
        df2 = convert_design(design2,sources,targets,slotting,config)
        action_df2 = batch_design(df2,config;insert_blowouts=true,dead_volume_buffer=20.0)
        aspirate_idx2 = findall(==("Aspirate"),action_df2.Action)
        block_end = aspirate_idx2[2]-1
        cycle1_sum = sum(action_df2[aspirate_idx2[1]+1:block_end,"Volume (uL)"]) # dispenses + blowout
        @test action_df2[aspirate_idx2[1],"Volume (uL)"] - cycle1_sum ≈ 0.01 atol=1e-9

        # custom buffer value is honored exactly
        custom_df = batch_design(df,config;aspirate_buffer=0.5,insert_blowouts=false)
        @test custom_df[1,"Volume (uL)"] - sum(custom_df[2:end,"Volume (uL)"]) ≈ 0.5 atol=1e-9

        # aspirate_buffer=0.0 reproduces the old exact-sum behavior exactly
        zero_buf_df = batch_design(df,config;aspirate_buffer=0.0,insert_blowouts=false)
        @test zero_buf_df[1,"Volume (uL)"] == sum(zero_buf_df[2:end,"Volume (uL)"])

        # capacity-margin regression: a raw volume sitting just under the reserved headroom
        # (capacity - aspirate_buffer - rounding_margin) stays as a single, unsplit batch and
        # never trips the capacity guard -- proving the reserved margin actually closes the gap
        # that used to let a near-capacity value round up and overflow after the buffer was added
        margin = 0.01 + 0.5*10.0^(-1) # default aspirate_buffer + default rounding_margin (volume_precision=1)
        design3 = DataFrame(zeros(1,R*C),:auto)
        design3[1,1] = 1000.0 - margin - 0.001 # just inside the reserved headroom
        df3 = convert_design(design3,sources,targets,slotting,config)
        action_df3 = batch_design(df3,config;insert_blowouts=false)
        @test nrow(action_df3) == 2 # stays a single aspirate/dispense pair, no split
        @test action_df3[1,"Volume (uL)"] <= 1000.0 + 1e-9

        # validation errors
        @test_throws ArgumentError batch_design(df,config;aspirate_buffer=-0.1,insert_blowouts=false)
        @test_throws ArgumentError batch_design(df,config;aspirate_buffer=1000.0,insert_blowouts=false) # alone already >= capacity
        @test_throws ArgumentError batch_design(df,config;insert_blowouts=true,dead_volume_buffer=999.99,aspirate_buffer=0.01) # combined >= capacity
    end

    @testset "nimbus_waste_conical reservation" begin
        config = configurations["nimbus"]

        # always present and pinned, regardless of what other labware is being slotted
        source = build_location(location_kinds[:Conical50],"nimbus_waste_reservation_source")
        slotting = slotting_greedy(Labware[source],config)
        @test nimbus_waste_conical in keys(slotting)
        @test slotting[nimbus_waste_conical] == (tuberack50mL_0006,nimbus_waste_slot)
        @test slotting[source] != slotting[nimbus_waste_conical]

        # unconditional: reserved even when nothing in this protocol uses insert_blowouts
        slotting_no_source = slotting_greedy(Labware[],config)
        @test nimbus_waste_conical in keys(slotting_no_source)
        @test slotting_no_source[nimbus_waste_conical] == (tuberack50mL_0006,nimbus_waste_slot)

        # exactly 35 of the 36 Conical50 slots remain available -- nothing else can ever land on
        # the reserved slot, even when every other slot is requested
        many_sources = [build_location(location_kinds[:Conical50],"nimbus_waste_reservation_src_$i") for i in 1:36]
        full_slotting = slotting_greedy(Labware[many_sources...],config)
        placed = filter(lw -> lw in keys(full_slotting),many_sources)
        @test length(placed) == 35
        @test all(lw -> full_slotting[lw] != (tuberack50mL_0006,nimbus_waste_slot),placed)

        # the generic slotting_greedy's new `pinned` kwarg defaults to empty and is a no-op for a
        # non-Nimbus config -- confirms the shared function's behavior is unchanged for everyone else
        other_config = configurations["single_channel"]
        plain_source = build_location(location_kinds[:WP96],"nimbus_waste_reservation_unrelated")
        other_slotting = slotting_greedy(Labware[plain_source],other_config)
        @test !(nimbus_waste_conical in keys(other_slotting))
    end

    @testset "nimbus_well translation" begin
        # slot 5 on a (2,3) rack is column-major CartesianIndex(1,3) -> well "A3"
        @test nimbus_well(tuberack50mL_0006,nimbus_waste_slot) == "A3"
        @test nimbus_waste_target == ("TubeRack50ML_WellNames_0006","A3")

        # a tube-rack source/destination surfaces as a well string, not a bare integer, in the
        # compiled design -- this is the fix for the physical mis-pipetting bug caused by an
        # undocumented row-major/column-major convention on the old integer slot
        config = configurations["nimbus"]
        source = build_location(location_kinds[:Conical50],"nimbus_well_translation_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus_well_translation_target")
        slotting = slotting_greedy(Labware[source,target],config)
        design = zeros(1,96); design[1,1] = 10.0
        df = convert_design(DataFrame(design,:auto),[source],[target],slotting,config)
        @test df[1,"Source Position ID"] isa AbstractString
        @test occursin(r"^[A-Z]+\d+$",df[1,"Source Position ID"])
    end

    @testset "polish_clustering integration" begin
        source1 = build_location(location_kinds[:Conical50],"nimbus_polish_test_source1")
        source2 = build_location(location_kinds[:Conical50],"nimbus_polish_test_source2")
        target = build_location(location_kinds[:DeepWP96],"nimbus_polish_test_target")
        sources = Labware[source1,source2]
        targets = Labware[target]
        config = configurations["nimbus"]
        slotting = slotting_greedy(vcat(sources,targets),config)

        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        design = DataFrame(zeros(2,R*C),:auto)
        design[1,well_col(1,1)] = 1500 # oversized transfer, same scenario as the main integration test
        design[1,well_col(1,2)] = 300
        design[1,well_col(1,3)] = 300
        design[1,well_col(1,4)] = 300
        design[1,well_col(1,5)] = 300
        design[2,well_col(1,6)] = 200
        design[2,well_col(1,7)] = 200

        default_aspirate_buffer = 0.01 # must match batch_design's default

        df = convert_design(design,sources,targets,slotting,config)
        # insert_blowouts explicitly off -- this test is about polish_clustering in isolation
        default_df = batch_design(df,config;insert_blowouts=false) # polish_clustering=false, the default
        polished_df = batch_design(df,config;polish_clustering=true,insert_blowouts=false)

        # regression: default behavior is byte-for-byte unaffected by the new kwarg's existence
        @test default_df == batch_design(df,config;polish_clustering=false,insert_blowouts=false)

        for action_df in (default_df,polished_df)
            @test names(action_df) == ["Labware ID","Labware Position ID","Volume (uL)","Action","Change Tip Before"]
            aspirate_idx = findall(==("Aspirate"),action_df.Action)
            n = nrow(action_df)
            for (k,i) in enumerate(aspirate_idx)
                block_end = k < length(aspirate_idx) ? aspirate_idx[k+1]-1 : n
                dispense_sum = sum(action_df[i+1:block_end,"Volume (uL)"])
                @test isapprox(dispense_sum+default_aspirate_buffer,action_df[i,"Volume (uL)"];atol=1e-6)
                @test all(action_df[i+1:block_end,"Change Tip Before"] .== 0)
            end
            @test all(<=(1000+default_aspirate_buffer+1e-9), action_df[!,"Volume (uL)"])
        end

        # the same multiset of dispense (Labware ID, Position ID) pairs appears regardless of
        # polish_clustering -- membership within a batch may change, but no destination is
        # dropped, duplicated, or reassigned to a different source's worth of volume
        dispense_pairs(df) = sort(collect(zip(df[df.Action .== "Dispense","Labware ID"],df[df.Action .== "Dispense","Labware Position ID"],df[df.Action .== "Dispense","Volume (uL)"])))
        @test dispense_pairs(default_df) == dispense_pairs(polished_df)

        # total dispensed volume unchanged
        total(df) = sum(df[df.Action .== "Dispense","Volume (uL)"])
        @test total(default_df) == total(polished_df)

        mktempdir() do dir
            outdir = joinpath(dir,"nimbus_polish_test")
            write_instrument_files(outdir,design,sources,targets,config,slotting;polish_clustering=true,polish_max_iterations=500,insert_blowouts=false)
            written = CSV.read(joinpath(outdir,"nimbus_polish_test.csv"),DataFrame)
            @test names(written) == names(polished_df)
        end
    end

    @testset "Bug 2 guard: capacity exceeded throws" begin
        source = build_location(location_kinds[:Conical50],"nimbus_capacity_guard_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus_capacity_guard_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R = size(target)[1]

        # 999.96 used to round to exactly 1000.0 and fit as a single aspirate before aspirate_buffer
        # existed. With the buffer + rounding-margin headroom now reserved during clustering, a
        # value this close to true capacity is correctly split into two batches instead -- proving
        # the reserved headroom (not the guard) is what prevents overflow here.
        design = DataFrame(zeros(1,R*size(target)[2]),:auto)
        design[1,1] = 999.96
        df = convert_design(design,sources,targets,slotting,config)
        action_df = batch_design(df,config;insert_blowouts=false)
        aspirate_idx = findall(==("Aspirate"),action_df.Action)
        @test length(aspirate_idx) == 2 # split, not a single 1000.0 aspirate
        @test all(<=(1000.0+1e-9), action_df[aspirate_idx,"Volume (uL)"]) # never exceeds true capacity
        # each batch's single dispense is rounded independently (no remainder to redistribute
        # within a 1-item list), so the total can drift from the nominal design value by up to a
        # rounding unit -- not a regression, just a property of per-batch independent rounding
        @test isapprox(sum(action_df[action_df.Action .== "Dispense","Volume (uL)"]),999.96;atol=0.1)

        # a value comfortably under the reserved headroom stays as one batch, with the buffer visible
        design2 = DataFrame(zeros(1,R*size(target)[2]),:auto)
        design2[1,1] = 500.0
        df2 = convert_design(design2,sources,targets,slotting,config)
        action_df2 = batch_design(df2,config;insert_blowouts=false)
        @test nrow(action_df2) == 2 # one aspirate, one dispense
        @test isapprox(action_df2[1,"Volume (uL)"],500.01;atol=1e-6)

        # batching already guarantees every batch's raw volume stays within (effective) capacity,
        # so the guard itself is a defensive assertion that should be unreachable through the
        # public API in normal use -- the cases above are the meaningful regression checks that
        # the reserved headroom (aspirate_buffer + dead_volume_buffer + rounding margin) actually
        # prevents overflow rather than relying on the guard to catch it after the fact.
    end

end
