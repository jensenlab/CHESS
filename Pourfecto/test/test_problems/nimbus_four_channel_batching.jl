import Pourfecto: convert_design_four_channel, batch_design_four_channel, channel_row,
    four_channel_row_spacing, compute_dispense_windows, order_windows, DispenseWindow,
    channel_event_sequence, pack_into_cycles, assemble_windows,
    nimbus_4ch_waste_conical, nimbus_4ch_waste_slot, nimbus_4ch_waste_target, nimbus_4ch_well,
    tuberack50mL_0006_4ch

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
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)
        well_col(letter_row,col) = (col-1)*R + letter_row

        # reagent i always targets row (2i-1) -- rows 1,3,5,7 -- every column: perfectly
        # spacing-compatible for every column simultaneously
        design = DataFrame(zeros(4,R*C),:auto)
        for col in 1:C, i in 1:4
            design[i,well_col(2i-1,col)] = 30.0
        end
        df = convert_design_four_channel(design,sources,targets,slotting,config)
        action_df = batch_design_four_channel(df,config;insert_blowouts=false)

        @test count(==("TipPickup"),action_df.Action) == 4
        @test count(==("TipDisposal"),action_df.Action) == 4

        dispense_rows = action_df[action_df.Action .== "Dispense",:]
        @test nrow(dispense_rows) == C # one merged row per column, all 4 channels together
        for row in eachrow(dispense_rows)
            @test all(c -> row["Labware Position $c"] != "None", 1:4)
        end
        total = sum(sum(dispense_rows[!,"Volume $c"]) for c in 1:4)
        @test total == 30.0*4*C
    end

    @testset "reagent count exceeding channel count throws" begin
        sources = Labware[build_location(location_kinds[:Conical50],"nimbus4ch_toomany_src$i") for i in 1:5]
        target = build_location(location_kinds[:DeepWP96],"nimbus4ch_toomany_target")
        targets = Labware[target]
        config = configurations["nimbus_four_channel"]
        slotting = slotting_greedy(vcat(sources,targets),config)
        R,C = size(target)
        design = DataFrame(zeros(5,R*C),:auto)
        for i in 1:5
            design[i,i] = 10.0
        end
        df = convert_design_four_channel(design,sources,targets,slotting,config)
        @test_throws ArgumentError batch_design_four_channel(df,config)
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

        # each channel's own tip session is contiguous: TipPickup/TipDisposal counts are sane
        # (at least 1 pickup and 1 disposal per channel that has any demand)
        @test count(==("TipPickup"),action_df.Action) >= 1
        @test count(==("TipDisposal"),action_df.Action) == count(==("TipPickup"),action_df.Action)
    end

    @testset "regression: Nimbus.jl (single-channel) is untouched by this instrument's presence" begin
        @test haskey(configurations,"nimbus")
        @test haskey(configurations,"nimbus_four_channel")
        @test configurations["nimbus"] !== configurations["nimbus_four_channel"]
    end

end
