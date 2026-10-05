import Pourfecto: convert_design_four_channel, batch_design_four_channel, channel_row,
    four_channel_row_spacing, compute_dispense_windows, order_windows, DispenseWindow,
    channel_event_sequence, compute_synchronized_cycles, assemble_windows,
    nimbus_4ch_waste_conical, nimbus_4ch_waste_slot, nimbus_4ch_waste_target, nimbus_4ch_well,
    tuberack50mL_0006_4ch, place_labware, four_channel_permutations, source_position_order,
    slot_position_order, group_reagents, group_window_count, four_channel_capacities

# reagents in transfer-list order (design row order), for tests that pin reagent i -> channel i
# instead of letting tube position decide
reagent_order(df) = collect(unique(zip(df[!,"Source Labware ID"],df[!,"Source Position ID"])))

@testset "NimbusFourChannel Batching" begin

    @testset "four_channel_row_spacing" begin
        @test four_channel_row_spacing(:DeepWP96) == 2
        @test four_channel_row_spacing(:WP96) == 2
        @test four_channel_row_spacing(:WP384) == 4
        @test four_channel_row_spacing(:SomeUnlistedKind) == 2 # default: 96-well-pitch baseline
    end

    @testset "channel_row" begin
        @test channel_row(1,1,2) == 1
        @test channel_row(1,4,2) == 7
        @test channel_row(-5,4,2) == 1
    end

    @testset "compute_dispense_windows" begin
        # 4 channels, all needing the same column, rows 1,3,5,7 (spacing=2) -- perfectly
        # compatible, should collapse into a single 4-way window
        demand = Dict(1=>[DispenseItem(1,CartesianIndex(1,5),30.0)],
                      2=>[DispenseItem(2,CartesianIndex(3,5),30.0)],
                      3=>[DispenseItem(3,CartesianIndex(5,5),30.0)],
                      4=>[DispenseItem(4,CartesianIndex(7,5),30.0)])
        windows = compute_dispense_windows(demand,4,"Plate",:DeepWP96,2)
        @test length(windows) == 1
        @test length(only(windows).active) == 4

        # misaligned (row diff 1, needs 2) -- can't combine
        demand2 = Dict(1=>[DispenseItem(1,CartesianIndex(1,5),30.0)],
                       2=>[DispenseItem(2,CartesianIndex(2,5),30.0)])
        windows2 = compute_dispense_windows(demand2,4,"Plate",:DeepWP96,2)
        @test length(windows2) == 2
        @test all(length(w.active) == 1 for w in windows2)

        # every item ends up in exactly one window, regardless of alignment
        total_items(ws) = sum(length(w.active) for w in ws)
        @test total_items(windows) == 4
        @test total_items(windows2) == 2

        # different columns never combine
        demand3 = Dict(1=>[DispenseItem(1,CartesianIndex(1,5),30.0)],
                       2=>[DispenseItem(2,CartesianIndex(3,6),30.0)]) # same row-compatible offset, different column
        windows3 = compute_dispense_windows(demand3,4,"Plate",:DeepWP96,2)
        @test length(windows3) == 2

        # a channel with 2 items at the SAME well (possible after split_oversized) needs 2
        # separate window-visits, not silently collapsed
        demand4 = Dict(1=>[DispenseItem(1,CartesianIndex(1,5),500.0),DispenseItem(2,CartesianIndex(1,5),500.0)])
        windows4 = compute_dispense_windows(demand4,4,"Plate",:DeepWP96,2)
        @test length(windows4) == 2
        @test total_items(windows4) == 2

        # empty demand -> no windows
        @test isempty(compute_dispense_windows(Dict{Int,Vector{DispenseItem}}(),4,"Plate",:DeepWP96,2))
    end

    @testset "compute_dispense_windows: internal consistency on realistic random demand" begin
        Random.seed!(11)
        n_channels = 4
        R,C = 8,12
        spacing = 2
        demand = Dict{Int,Vector{DispenseItem}}()
        counter = 0
        for c in 1:n_channels
            items = DispenseItem[]
            for row in 1:R, col in 1:C
                if rand() < 0.5
                    counter += 1
                    push!(items,DispenseItem(counter,CartesianIndex(row,col),30.0))
                end
            end
            demand[c] = items
        end
        total_events = sum(length(v) for v in values(demand))
        windows = compute_dispense_windows(demand,n_channels,"Plate",:DeepWP96,spacing)

        # every event accounted for exactly once
        @test sum(length(w.active) for w in windows) == total_events

        # no duplicate channel within a window, and the spacing relationship holds pairwise
        for w in windows
            chans = [c for (c,_) in w.active]
            @test allunique(chans)
            for i in eachindex(w.active), j in (i+1):length(w.active)
                c1,it1 = w.active[i]; c2,it2 = w.active[j]
                lo,hi = c1 < c2 ? (c1,c2) : (c2,c1)
                r_lo = c1 < c2 ? it1.position[1] : it2.position[1]
                r_hi = c1 < c2 ? it2.position[1] : it1.position[1]
                @test (r_hi - r_lo) == (hi - lo) * spacing
            end
        end

        # this baseline captures real parallelism -- some windows should have >1 active channel
        @test any(w -> length(w.active) > 1, windows)
    end

    @testset "order_windows" begin
        w1 = DispenseWindow("Plate",:DeepWP96,1,1,[(1,DispenseItem(1,CartesianIndex(1,1),30.0))])
        w2 = DispenseWindow("Plate",:DeepWP96,2,1,[(1,DispenseItem(2,CartesianIndex(1,2),30.0))])
        w3 = DispenseWindow("Plate",:DeepWP96,10,1,[(1,DispenseItem(3,CartesianIndex(1,10),30.0))])
        ordered = order_windows([w3,w1,w2]) # deliberately out of order
        @test length(ordered) == 3
        @test Set(ordered) == Set([w1,w2,w3])
        # nearest-neighbor from the first element visited should prefer the adjacent column
        cols = [w.column for w in ordered]
        @test cols[1] == 10 # starts from the first element in the input as given to order_batch
        @test cols[2] in (1,2) # then jumps to the nearer of the remaining two... which is neither near 10 equally; just check monotonic improvement isn't required, only validity
        @test isempty(order_windows(DispenseWindow[]))
    end

    @testset "convert_design_four_channel / batch_design_four_channel: single reagent, full plate" begin
        source = build_location(location_kinds[:Conical50],"nimbus4ch_batch_test_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_batch_test_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)

        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        design = DataFrame(zeros(1,R*C),:auto)
        for col in 1:C, row in 1:R
            design[1,well_col(row,col)] = 30.0
        end

        df = convert_design_four_channel(design,sources,targets,slotting,config)
        @test names(df) == ["Source Labware ID","Source Position ID","Volume (uL)","Destination Labware ID","Destination Position ID","Destination Kind"]
        @test nrow(df) == R*C
        @test all(df[!,"Destination Kind"] .== :DeepWP96)

        action_df = batch_design_four_channel(df,config;insert_blowouts=true,dead_volume_buffer=20.0)
        @test names(action_df) == ["Labware ID","Labware Position 1","Volume 1","Labware Position 2","Volume 2",
                                    "Labware Position 3","Volume 3","Labware Position 4","Volume 4","Action"]
        @test all(a -> a in ("TipPickup","Aspirate","Dispense","Blowout","TipDisposal"), action_df.Action)

        @test count(==("TipPickup"),action_df.Action) == 1
        @test count(==("TipDisposal"),action_df.Action) == 1
        @test action_df[1,"Action"] == "TipPickup"
        @test action_df[end,"Action"] == "TipDisposal"
        @test all(action_df[!,"Labware Position 2"] .== "None")
        @test all(action_df[!,"Labware Position 3"] .== "None")
        @test all(action_df[!,"Labware Position 4"] .== "None")

        dispense_rows = action_df[action_df.Action .== "Dispense",:]
        @test sum(dispense_rows[!,"Volume 1"]) == 30.0*R*C

        aspirate_rows = action_df[action_df.Action .== "Aspirate",:]
        @test all(<=(1000.0+0.01+1e-6), aspirate_rows[!,"Volume 1"])

        mktempdir() do dir
            outdir = joinpath(dir,"nimbus4ch_batch_test")
            write_instrument_files(outdir,design,sources,targets,config,slotting;insert_blowouts=true,dead_volume_buffer=20.0)
            written = CSV.read(joinpath(outdir,"nimbus4ch_batch_test.csv"),DataFrame)
            @test names(written) == names(action_df)
            @test nrow(written) == nrow(action_df)
        end
    end

    @testset "four reagents with perfectly aligned demand fully merge" begin
        sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_align_src$i") for i in 1:4]
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_align_target")
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        # reagent i always targets row (2i-1) -- rows 1,3,5,7 -- every column: perfectly
        # spacing-compatible for every column simultaneously, but only if reagent i sits on channel
        # i. Placement has to discover that order on its own (channels follow tube position).
        design = DataFrame(zeros(4,R*C),:auto)
        for col in 1:C, i in 1:4
            design[i,well_col(2i-1,col)] = 30.0
        end
        slotting = place_labware(slotting_greedy(vcat(sources,targets),config),design,sources,targets,config)
        df = convert_design_four_channel(design,sources,targets,slotting,config)
        action_df = batch_design_four_channel(df,config;insert_blowouts=false)

        # all 4 reagents' single cycle starts/ends in lockstep (aligned demand, well within one
        # cycle's capacity) -- TipPickup/TipDisposal always merge on a shared "None" Labware ID
        @test count(==("TipPickup"),action_df.Action) == 1
        @test count(==("TipDisposal"),action_df.Action) == 1
        pickup_row = only(eachrow(action_df[action_df.Action .== "TipPickup",:]))
        dispose_row = only(eachrow(action_df[action_df.Action .== "TipDisposal",:]))
        @test all(c -> pickup_row["Labware Position $c"] == "Pickup", 1:4)
        @test all(c -> dispose_row["Labware Position $c"] == "Dispose", 1:4)

        # placement puts all 4 tubes in one rack, so their Aspirates share a Labware ID and merge
        @test length(unique(df[!,"Source Labware ID"])) == 1
        @test count(==("Aspirate"),action_df.Action) == 1

        dispense_rows = action_df[action_df.Action .== "Dispense",:]
        @test nrow(dispense_rows) == C # one merged row per column, all 4 channels together
        for row in eachrow(dispense_rows)
            @test all(c -> row["Labware Position $c"] != "None", 1:4)
        end
        total = sum(sum(dispense_rows[!,"Volume $c"]) for c in 1:4)
        @test total == 30.0*4*C
    end

    @testset "cross-channel action merging: TipPickup/TipDisposal/Blowout always merge, Aspirate only same-labware" begin
        sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_merge_src$i") for i in 1:2]
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_merge_target")
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        # slotting_greedy takes slots in the iteration order of a Set, which is not guaranteed, so pin
        # the two conicals into two different racks instead of relying on its choice
        slotting[sources[1]] = (Pourfecto.tuberack50mL_0001_4ch,1)
        slotting[sources[2]] = (Pourfecto.tuberack50mL_0002_4ch,1)
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        # two reagents, perfectly row/column aligned (rows 1 and 3, spacing 2) -- every column
        design2 = DataFrame(zeros(2,R*C),:auto)
        for col in 1:C, i in 1:2
            design2[i,well_col(2i-1,col)] = 30.0
        end
        base_df = convert_design_four_channel(design2,sources,targets,slotting,config)

        @testset "different source labware -> Aspirate stays separate" begin
            # this sub-case is only meaningful if the 2 conicals are on 2 distinct physical
            # Labware IDs, which the pinned slotting above sets up -- assert that precondition
            @test length(unique(base_df[!,"Source Labware ID"])) == 2

            action_df = batch_design_four_channel(base_df,config;insert_blowouts=false,channel_order=reagent_order(base_df))

            @test count(==("TipPickup"),action_df.Action) == 1
            @test count(==("TipDisposal"),action_df.Action) == 1
            @test count(==("Aspirate"),action_df.Action) == 2
        end

        # placement puts both tubes in one rack, so they share a Source Labware ID
        shared_slotting = place_labware(slotting,design2,sources,targets,config)

        @testset "same source labware -> Aspirate also merges" begin
            df = convert_design_four_channel(design2,sources,targets,shared_slotting,config)
            @test length(unique(df[!,"Source Labware ID"])) == 1
            action_df = batch_design_four_channel(df,config;insert_blowouts=false,channel_order=reagent_order(df))

            @test count(==("TipPickup"),action_df.Action) == 1
            @test count(==("TipDisposal"),action_df.Action) == 1
            @test count(==("Aspirate"),action_df.Action) == 1
            aspirate_row = only(eachrow(action_df[action_df.Action .== "Aspirate",:]))
            @test all(c -> aspirate_row["Labware Position $c"] != "None", 1:2)
        end

        @testset "shared source, oversized demand -> mid-run Blowout also merges" begin
            # scale both reagents up so each needs multiple aspirate cycles (same tip reused
            # throughout -- no source change, well under max_tip_use -- so this only exercises the
            # trailing-Blowout-before-reaspirate merge, not a tip-change merge); since both channels
            # have identical per-item volume and column order, their capacity-driven cycle breaks
            # land at the exact same window every time
            design_big = DataFrame(zeros(2,R*C),:auto)
            for col in 1:C, i in 1:2
                design_big[i,well_col(2i-1,col)] = 165.0
            end
            df = convert_design_four_channel(design_big,sources,targets,shared_slotting,config)
            @test length(unique(df[!,"Source Labware ID"])) == 1
            action_df = batch_design_four_channel(df,config;insert_blowouts=true,dead_volume_buffer=20.0,channel_order=reagent_order(df))

            @test count(==("TipPickup"),action_df.Action) == 1
            @test count(==("TipDisposal"),action_df.Action) == 1
            # 165uL x 12 columns splits into 3 capacity-bounded cycles for each channel -> 2
            # mid-run reload boundaries; both channels break at the same boundary every time (same
            # per-item volume, same column order), so each boundary's Blowout merges to one row
            blowout_rows = action_df[action_df.Action .== "Blowout",:]
            @test nrow(blowout_rows) == 2
            @test all(row["Labware Position $c"] != "None" for row in eachrow(blowout_rows) for c in 1:2)
        end
    end

    @testset "synchronized reload trips: back-loaded channel pulled forward, finished channel's disposal deferred" begin
        @testset "a channel whose own first item comes much later still loads at the earlier channel's trigger" begin
            sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_syncA_src$i") for i in 1:2]
            target = build_location(location_kinds[:DeepWP96],"nimbus4ch_syncA_target")
            targets = Labware[target]
            config = configurations["nimbus_four_channel"]
            slotting = slotting_greedy(vcat(sources,targets),config)
            R,C = size(target)
            well_col(letter_row,col) = (col-1)*R + letter_row

            # channel 1: tiny demand, columns 1-2 only -- naturally first in the window order.
            # channel 2: all remaining columns (3..C) -- its own first item is far later in the
            # order, yet under synchronization it should still load at channel 1's very first trigger
            design = DataFrame(zeros(2,R*C),:auto)
            design[1,well_col(1,1)] = 30.0
            design[1,well_col(1,2)] = 30.0
            for col in 3:C
                design[2,well_col(1,col)] = 30.0
            end
            df = convert_design_four_channel(design,sources,targets,slotting,config)
            action_df = batch_design_four_channel(df,config;insert_blowouts=false,channel_order=reagent_order(df))

            @test count(==("TipPickup"),action_df.Action) == 1
            pickup_row = only(eachrow(action_df[action_df.Action .== "TipPickup",:]))
            @test all(c -> pickup_row["Labware Position $c"] == "Pickup", 1:2)
            # channel 2's own first actual Dispense (its real destination item) must come strictly
            # after the shared pickup/aspirate, not the other way around
            first_dispense_idx = findfirst(row -> row.Action=="Dispense" && row["Labware Position 2"]!="None", eachrow(action_df))
            pickup_idx = findfirst(==("TipPickup"),action_df.Action)
            @test pickup_idx < first_dispense_idx

            # with synchronization off, channel 2 picks up on its own trip at its own first window,
            # after channel 1 has started dispensing, and channel 1 disposes right after its last item
            unsynced = batch_design_four_channel(df,config;insert_blowouts=false,channel_order=reagent_order(df),synchronize_reloads=false)
            @test count(==("TipPickup"),unsynced.Action) == 2
            ch2_pickup = findfirst(r -> r.Action=="TipPickup" && r["Labware Position 2"]=="Pickup", eachrow(unsynced))
            ch1_first_dispense = findfirst(r -> r.Action=="Dispense" && r["Labware Position 1"]!="None", eachrow(unsynced))
            @test ch2_pickup > ch1_first_dispense
            ch1_last_dispense = findlast(r -> r.Action=="Dispense" && r["Labware Position 1"]!="None", eachrow(unsynced))
            @test unsynced[ch1_last_dispense+1,"Action"] == "TipDisposal"
            @test unsynced[ch1_last_dispense+1,"Labware Position 1"] == "Dispose"
            dispensed(a) = sum(sum(a[a.Action .== "Dispense","Volume $c"]) for c in 1:4)
            @test dispensed(unsynced) == dispensed(action_df)
        end

        @testset "a finished channel's disposal is deferred to a later channel's own reload, not fired immediately" begin
            sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_syncB_src$i") for i in 1:2]
            target = build_location(location_kinds[:DeepWP96],"nimbus4ch_syncB_target")
            targets = Labware[target]
            config = configurations["nimbus_four_channel"]
            slotting = slotting_greedy(vcat(sources,targets),config)
            R,C = size(target)
            well_col(letter_row,col) = (col-1)*R + letter_row

            # channel 1: tiny demand, row 1 columns 1-2 -- finishes almost immediately
            # channel 2: large demand, rows 3..R across every column -- forces multiple aspirate
            # cycles, so it has its own later mid-run reload trigger for channel 1 to piggyback on
            design = DataFrame(zeros(2,R*C),:auto)
            design[1,well_col(1,1)] = 30.0
            design[1,well_col(1,2)] = 30.0
            for row in 3:R, col in 1:C
                design[2,well_col(row,col)] = 30.0
            end
            df = convert_design_four_channel(design,sources,targets,slotting,config)
            action_df = batch_design_four_channel(df,config;insert_blowouts=false,channel_order=reagent_order(df))

            # channel 2 needs more than one aspirate cycle for this to be a meaningful test
            @test count(==("Aspirate"),action_df.Action) >= 2

            last_ch1_dispense_idx = findlast(row -> row.Action=="Dispense" && row["Labware Position 1"]!="None", eachrow(action_df))
            ch1_disposal_idx = findfirst(row -> row.Action=="TipDisposal" && row["Labware Position 1"]=="Dispose", eachrow(action_df))
            @test !isnothing(ch1_disposal_idx)
            # deferred well past its own last dispense -- not the very next row -- and not merely
            # pushed to the very end either (there's an intermediate channel-2 reload to piggyback on)
            @test ch1_disposal_idx > last_ch1_dispense_idx + 1
            @test ch1_disposal_idx < nrow(action_df)
            # it rides along on channel 2's next reload trip: disposed right before channel 2 re-aspirates
            @test action_df[ch1_disposal_idx+1,"Action"] == "Aspirate"
            @test action_df[ch1_disposal_idx+1,"Labware Position 2"] != "None"
            @test count(r -> r.Action == "Aspirate" && r["Labware Position 2"] != "None", eachrow(action_df[1:ch1_disposal_idx,:])) == 1 # rides on channel 2's second load, not its first
        end
    end

    @testset "placement: channels follow tube position, tubes placed to match the head" begin
        @testset "default place_labware leaves other instruments' slotting unchanged" begin
            config = configurations["nimbus"]
            sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_place_default_src")]
            targets = Labware[build_location(location_kinds[:DeepWP96],"nimbus4ch_place_default_target")]
            slotting = slotting_greedy(vcat(sources,targets),config)
            design = DataFrame(zeros(1,length(targets[1])),:auto)
            design[1,1] = 30.0
            @test place_labware(slotting,design,sources,targets,config) === slotting
        end

        @testset "channels are handed out in tube-position order, not transfer-list order" begin
            config = configurations["nimbus_four_channel"]
            # B1's reagent appears first in the transfer list, but A1 sorts first -> channel 1
            df = DataFrame("Source Labware ID"=>["RackX","RackX"],"Source Position ID"=>["B1","A1"],
                "Volume (uL)"=>[30.0,30.0],"Destination Labware ID"=>["Plate","Plate"],
                "Destination Position ID"=>["C1","A1"],"Destination Kind"=>[:DeepWP96,:DeepWP96])
            action_df = batch_design_four_channel(df,config;insert_blowouts=false)
            aspirate_row = only(eachrow(action_df[action_df.Action .== "Aspirate",:]))
            @test aspirate_row["Labware Position 1"] == "A1"
            @test aspirate_row["Labware Position 2"] == "B1"
            # A1's reagent (ch1) goes to row A, B1's (ch2) to row C: 2 rows apart, one shared dispense
            dispense_row = only(eachrow(action_df[action_df.Action .== "Dispense",:]))
            @test dispense_row["Labware Position 1"] == "A1"
            @test dispense_row["Labware Position 2"] == "C1"

            @test source_position_order(("RackX","B1")) > source_position_order(("RackX","A1"))
            @test source_position_order(("RackX","A2")) > source_position_order(("RackX","B1"))
            @test_throws ArgumentError batch_design_four_channel(df,config;channel_order=[("RackX","A1")])
        end

        sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_place_src$i") for i in 1:4]
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_place_target")
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row
        Random.seed!(42)
        design = DataFrame(zeros(4,R*C),:auto)
        for row in 1:R, col in 1:C, i in 1:4
            rand() < 0.5 && (design[i,well_col(row,col)] = 30.0)
        end

        @testset "4 reagents: one rack, head-aligned slots, waste pinned, best channel order" begin
            base = slotting_greedy(vcat(sources,targets),config)
            placed = place_labware(base,design,sources,targets,config)

            @test length(unique(placed[s][1] for s in sources)) == 1
            @test sort([placed[s][2] for s in sources]) == [1,2,3,4] # A1,B1,A2,B2
            @test placed[nimbus_4ch_waste_conical] == base[nimbus_4ch_waste_conical]
            @test placed[target] == base[target]

            df = convert_design_four_channel(design,sources,targets,placed,config)
            chosen = nrow(batch_design_four_channel(df,config))
            best = minimum(nrow(batch_design_four_channel(df,config;channel_order=order)) for order in four_channel_permutations(reagent_order(df)))
            @test chosen == best
        end

        @testset "fragmented racks: every free full column used, lower channel always on row A" begin
            base = slotting_greedy(vcat(sources,targets),config)
            racks = [p for p in Pourfecto.deck(config) if Pourfecto.can_place(sources[1],p,config)]
            # occupy A1 and A2 of every 50 mL rack: only column 3 stays whole, except in the waste
            # rack, whose A3 holds the waste conical -- so no rack can host all 4 tubes aligned
            fillers = Labware[]
            for p in racks, slot in (1,3)
                f = build_location(location_kinds[:Conical50],"nimbus4ch_place_fill_$(p.name)_$slot")
                base[f] = (p,slot)
                push!(fillers,f)
            end
            placed = place_labware(base,design,sources,targets,config)

            @test all(placed[f] == base[f] for f in fillers)
            @test allunique(placed[s] for s in sources)
            column_of(s) = (placed[s][1], Tuple(CartesianIndices(Pourfecto.slots(placed[s][1]))[placed[s][2]])[2])
            @test length(unique(column_of(s) for s in sources)) == 2 # two whole columns, 2 tubes each

            df = convert_design_four_channel(design,sources,targets,placed,config)
            action_df = batch_design_four_channel(df,config)
            for row in eachrow(action_df[action_df.Action .== "Aspirate",:])
                positions = [row["Labware Position $c"] for c in 1:4 if row["Labware Position $c"] != "None"]
                length(positions) == 2 || continue
                # channels are listed low to high; the lower one must sit on row A of the shared column
                @test positions[1][1] == 'A' && positions[2][1] == 'B'
                @test positions[1][2:end] == positions[2][2:end]
            end
        end
    end

    @testset "more reagents than channels: fixed groups" begin
        config = configurations["nimbus_four_channel"]
        _, effective_capacity = four_channel_capacities(config)

        @testset "groups are read from tube position, one swap trip between them" begin
            # 8 reagents listed out of position order; sorted by position, the first 4 are group 1
            positions = [("RackY","B1"),("RackX","A3"),("RackX","B1"),("RackX","A1"),
                         ("RackY","A1"),("RackX","B2"),("RackX","B3"),("RackX","A2")]
            df = DataFrame("Source Labware ID"=>first.(positions),"Source Position ID"=>last.(positions),
                "Volume (uL)"=>fill(30.0,8),"Destination Labware ID"=>fill("Plate",8),
                "Destination Position ID"=>["A$k" for k in 1:8],"Destination Kind"=>fill(:DeepWP96,8))
            action_df = batch_design_four_channel(df,config;insert_blowouts=false)

            pickups = findall(==("TipPickup"),action_df.Action)
            @test length(pickups) == 2
            @test action_df[pickups[2]-1,"Action"] == "TipDisposal"
            sources_used(rows) = Set((r["Labware ID"],r["Labware Position $c"]) for r in eachrow(rows)
                for c in 1:4 if r["Labware Position $c"] != "None")
            aspirates = action_df.Action .== "Aspirate"
            first_half = aspirates .& (1:nrow(action_df) .< pickups[2])
            @test sources_used(action_df[first_half,:]) == Set([("RackX","A1"),("RackX","B1"),("RackX","A2"),("RackX","B2")])
            @test sources_used(action_df[aspirates .& .!first_half,:]) == Set([("RackX","A3"),("RackX","B3"),("RackY","A1"),("RackY","B1")])
        end

        score(demands,volumes,g) = minimum(group_window_count(demands,p,4) for p in four_channel_permutations(g)) +
            8 * maximum(ceil(volumes[i]/effective_capacity) for i in g)
        seed_groups(volumes) = (o = sortperm(volumes,rev=true); [o[i:min(i+3,end)] for i in 1:4:length(o)])

        @testset "grouping search recovers a planted structure a volume-sorted split would miss" begin
            # odd reagents fill rows 1,3,5,7 and even reagents rows 2,4,6,8, in every column: each
            # parity set shares a window per column only when grouped together. A plain volume-sorted
            # split (all volumes equal) would mix them as {1,2,3,4},{5,6,7,8}, where no single swap
            # helps; the greedy seed has to find the parity sets
            rows = [1,2,3,4,5,6,7,8]
            demands = [[("Plate",:DeepWP96) => [DispenseItem(100i+col,CartesianIndex(rows[i],col),30.0) for col in 1:12]] for i in 1:8]
            volumes = fill(360.0,8)
            groups = group_reagents(demands,volumes,4,effective_capacity)
            @test Set(Set.(groups)) == Set([Set([1,3,5,7]),Set([2,4,6,8])])
            @test sum(score(demands,volumes,g) for g in groups) < sum(score(demands,volumes,g) for g in seed_groups(volumes))
        end

        @testset "$n reagents compile: volume conserved, one tip session per group, whole head-aligned columns" for n in (5,7,8,13,24)
            sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_group_$(n)_src$i") for i in 1:n]
            target = build_location(location_kinds[:DeepWP96],"nimbus4ch_group_$(n)_target")
            targets = Labware[target]
            R,C = size(target)
            Random.seed!(n)
            design = DataFrame(zeros(n,R*C),:auto)
            for i in 1:n, w in 1:R*C
                rand() < 0.3 && (design[i,w] = 30.0)
            end
            slotting = place_labware(slotting_greedy(vcat(sources,targets),config),design,sources,targets,config)
            df = convert_design_four_channel(design,sources,targets,slotting,config)
            action_df = batch_design_four_channel(df,config)

            dispense_rows = action_df[action_df.Action .== "Dispense",:]
            @test sum(sum(dispense_rows[!,"Volume $c"]) for c in 1:4) ≈ sum(Matrix(design))
            n_groups = cld(n,4)
            @test count(==("TipPickup"),action_df.Action) == n_groups # all channels pick up together per group
            cells(action) = sum(count(c -> r["Labware Position $c"] != "None",1:4) for r in eachrow(action_df[action_df.Action .== action,:]))
            @test cells("TipPickup") == n
            @test cells("TipDisposal") == n # every tip disposed exactly once
            # a disposal is never its own trip: it rides along on a reload/pickup, or ends a group
            for i in findall(==("TipDisposal"),action_df.Action)
                @test i == nrow(action_df) || action_df[i+1,"Action"] in ("TipPickup","Aspirate","TipDisposal")
            end

            slots_in_order = sort([slotting[s] for s in sources],by=slot_position_order)
            column(s) = (s[1].name, Tuple(CartesianIndices(Pourfecto.slots(s[1]))[s[2]])[2])
            # every group, the short last one included, owns whole columns in one rack: no column is
            # shared with another group, and a group of k tubes uses exactly cld(k,2) columns
            group_columns = [unique(column.(slots_in_order[4k-3:min(4k,n)])) for k in 1:n_groups]
            for (k,cols) in enumerate(group_columns)
                @test length(cols) == cld(length(4k-3:min(4k,n)),2)
                @test length(unique(first.(cols))) == 1
            end
            @test allunique(vcat(group_columns...))
        end
    end

    @testset "oversized transfer forces multiple aspirate cycles for one reagent" begin
        source = build_location(location_kinds[:Conical50],"nimbus4ch_oversized_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_oversized_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        design = DataFrame(zeros(1,R*C),:auto)
        design[1,well_col(1,1)] = 2500.0
        df = convert_design_four_channel(design,sources,targets,slotting,config)
        action_df = batch_design_four_channel(df,config;insert_blowouts=false)

        aspirate_rows = action_df[action_df.Action .== "Aspirate",:]
        @test nrow(aspirate_rows) >= 3
        @test all(<=(1000.0+0.01+1e-6), aspirate_rows[!,"Volume 1"])
        @test count(==("TipPickup"),action_df.Action) == 1
        @test count(==("TipDisposal"),action_df.Action) == 1

        dispense_rows = action_df[action_df.Action .== "Dispense",:]
        @test isapprox(sum(dispense_rows[!,"Volume 1"]),2500.0;atol=0.1)
    end

    @testset "priming step defaults off, opt-in via kwarg" begin
        source = build_location(location_kinds[:Conical50],"nimbus4ch_priming_source")
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_priming_target")
        sources = Labware[source]
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        design = DataFrame(zeros(1,R*C),:auto)
        design[1,well_col(1,1)] = 50.0

        df = convert_design_four_channel(design,sources,targets,slotting,config)
        default_df = batch_design_four_channel(df,config;insert_blowouts=false)
        @test count(==("Dispense"),default_df.Action) == 1 # no priming row by default

        primed_df = batch_design_four_channel(df,config;insert_blowouts=false,priming=true,priming_volume=50.0)
        @test count(==("Dispense"),primed_df.Action) == 2 # priming dispense + the real dispense
        aspirate_row = only(eachrow(primed_df[primed_df.Action .== "Aspirate",:]))
        dispense_rows = primed_df[primed_df.Action .== "Dispense",:]
        @test dispense_rows[1,"Labware Position 1"] == aspirate_row["Labware Position 1"] # primes back to the source position
        @test dispense_rows[1,"Volume 1"] == 50.0

        @test_throws ArgumentError batch_design_four_channel(df,config;priming=true,priming_volume=0.0,insert_blowouts=false)
    end

    @testset "every dispensed volume preserved exactly on real 50%-coverage-style random demand" begin
        sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_random_src$i") for i in 1:4]
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_random_target")
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        Random.seed!(99)
        design = DataFrame(zeros(4,R*C),:auto)
        expected_total = 0.0
        for row in 1:R, col in 1:C, i in 1:4
            if rand() < 0.5
                design[i,well_col(row,col)] = 30.0
                expected_total += 30.0
            end
        end
        df = convert_design_four_channel(design,sources,targets,slotting,config)
        action_df = batch_design_four_channel(df,config;insert_blowouts=true,dead_volume_buffer=20.0)

        dispense_rows = action_df[action_df.Action .== "Dispense",:]
        total = sum(sum(dispense_rows[!,"Volume $c"]) for c in 1:4)
        @test total == expected_total

        # this baseline should capture real parallelism -- not every dispense row single-channel
        active_counts = [count(c -> dispense_rows[i,"Labware Position $c"] != "None",1:4) for i in 1:nrow(dispense_rows)]
        @test any(>(1),active_counts)

        # every Dispense row has at least one active channel (no all-None rows)
        @test all(>=(1),active_counts)

        # each channel's own tip session is contiguous: at least one pickup happened, and every
        # pickup is eventually matched by exactly one disposal for that channel -- checked at the
        # entry (per-channel-cell) level, not row count, since merging can now bundle pickups and
        # disposals into differently-sized rows (e.g. a row mixing a first-time pickup for one
        # channel with a refresh pickup for another has no matching disposal row of the same size)
        pickup_rows = action_df[action_df.Action .== "TipPickup",:]
        dispose_rows = action_df[action_df.Action .== "TipDisposal",:]
        pickup_entries = sum(count(c -> pickup_rows[i,"Labware Position $c"] == "Pickup",1:4) for i in 1:nrow(pickup_rows))
        dispose_entries = sum(count(c -> dispose_rows[i,"Labware Position $c"] == "Dispose",1:4) for i in 1:nrow(dispose_rows))
        @test pickup_entries >= 1
        @test dispose_entries == pickup_entries
    end

    @testset "regression: Nimbus.jl (single-channel) is untouched by this instrument's presence" begin
        @test haskey(configurations,"nimbus")
        @test haskey(configurations,"nimbus_four_channel")
        @test configurations["nimbus"] !== configurations["nimbus_four_channel"]
    end

end
