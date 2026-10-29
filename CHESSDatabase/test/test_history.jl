# reconstruct_history (src/reconstruction/reconstruct_history.jl): the rows at which a facet of a location changed.
# The property that matters (the value at every slot equals the matching reconstruct_*) is also checked on random
# ledgers in test/equivalence/test_equivalence.jl; here a planted ledger with known answers.
# Every location is new (prefixed `hx_`) and runs against the shared database set up in build_test_database.jl.

hx_plan(sql,params=()) = [String(d) for d in query_db("EXPLAIN QUERY PLAN " * sql,params).detail]
hx_time(lid) = CHESSDatabase.julia_time(query_db("SELECT Time FROM Ledger WHERE ID = ?",(lid,)).Time[1])
hx_tick() = sleep(0.02)

hx_lab = generate_location(Lab,"hx lab")
hx_a = generate_location(Room,"hx room a")
hx_b = generate_location(Room,"hx room b")
upload(move_into!,hx_lab,hx_a); upload(move_into!,hx_lab,hx_b)
hx_plate = generate_location(WP96,"hx plate")
hx_well = hx_plate[1,1]
hx_bottle = commit_location!(build_location(Bottle1L,"hx bottle"))
hx_id(x) = location_id(x)

hx_s0 = get_last_sequence_id()
hx_ledgers = Dict{Symbol,Int}()
function hx_do(name,f,args...;kwargs...)
    hx_ledgers[name] = f in (observe,upload_instrument_setting) ? f(args...;kwargs...) : upload(f,args...;kwargs...)
    hx_tick()
    return get_sequence_id(hx_ledgers[name])
end
hx_slot = Dict{Symbol,Int}()
hx_slot[:into_a] = hx_do(:into_a,move_into!,hx_a,hx_plate)
hx_slot[:a20] = hx_do(:a20,set_attribute!,hx_a,Temperature(20u"°C"))
hx_slot[:b30] = hx_do(:b30,set_attribute!,hx_b,Temperature(30u"°C"))
hx_slot[:p25] = hx_do(:p25,set_attribute!,hx_plate,Temperature(25u"°C"))
hx_slot[:w5] = hx_do(:w5,set_attribute!,hx_well,Temperature(5u"°C"))
hx_slot[:wunset] = hx_do(:wunset,set_attribute!,hx_well,Temperature(missing))
hx_slot[:into_b] = hx_do(:into_b,move_into!,hx_b,hx_plate)
hx_slot[:punset] = hx_do(:punset,set_attribute!,hx_plate,Temperature(missing))
hx_slot[:b31] = hx_do(:b31,set_attribute!,hx_b,Temperature(31u"°C"))
hx_slot[:lock] = hx_do(:lock,lock!,hx_plate)
hx_slot[:unlock] = hx_do(:unlock,unlock!,hx_plate)
hx_slot[:deact] = hx_do(:deact,deactivate!,hx_well)
hx_slot[:react] = hx_do(:react,activate!,hx_well)
hx_lot1 = Lot("Hx Supplier","HX1","HXLOT1")
hx_lot2 = Lot("Hx Supplier","HX1","HXLOT2")
hx_slot[:lot1] = hx_do(:lot1,observe,hx_bottle,hx_lot1)
hx_slot[:lot2] = hx_do(:lot2,observe,hx_bottle,hx_lot2)
hx_slot[:gain1] = hx_do(:gain1,upload_instrument_setting,hx_a,"Gain","1.5")
hx_slot[:gain2] = hx_do(:gain2,upload_instrument_setting,hx_a,"Gain","2.5")
hx_slot[:filter] = hx_do(:filter,upload_instrument_setting,hx_a,"Filter","F1")
hx_cplate = generate_location(WP96,"hx cached plate")
hx_slot[:clock] = hx_do(:clock,lock!,hx_cplate)
hx_slot[:cache] = (cache(hx_cplate); get_last_sequence_id())
hx_last = get_last_sequence_id()

hx_expected_effective = [(:a20,20.0,hx_id(hx_a)),(:p25,25.0,hx_id(hx_plate)),(:w5,5.0,hx_id(hx_well)),(:wunset,25.0,hx_id(hx_plate)),
    (:punset,30.0,hx_id(hx_b)),(:b31,31.0,hx_id(hx_b))]

# the value of the matching reconstruction
function hx_quantity(dict,name)
    for (k,a) in dict
        kname = k isa Symbol ? k : hasproperty(k,:name) ? k.name : Symbol(string(k))
        kname === Symbol(name) || continue
        return ismissing(CHESSCore.value(a)) ? missing : CHESSCore.quantity(a)
    end
    return missing
end

@testset "history: the effective temperature of a well follows its own value, its plate and the rooms the plate moves through" begin
    h = reconstruct_history(hx_id(hx_well),:Temperature;from=hx_s0)
    @test names(h) == ["SequenceID","LedgerID","Time","Value","Unit","Origin","Event"]
    @test h.SequenceID == [hx_slot[k] for (k,_,_) in hx_expected_effective]
    @test h.Value == [v for (_,v,_) in hx_expected_effective]
    @test h.Origin == [o for (_,_,o) in hx_expected_effective]
    @test all(==("°C"),h.Unit)
    @test h.LedgerID == [hx_ledgers[k] for (k,_,_) in hx_expected_effective]
    @test h.Event == ["set_attribute","set_attribute","set_attribute","set_attribute","set_attribute","set_attribute"]
    @test issorted(h.Time) && all(t -> t isa DateTime,h.Time)
    # moving the plate between two rooms of the same temperature changes only the origin; here the move itself is not a row
    # because the plate has its own value when it moves
    @test !(hx_slot[:into_b] in h.SequenceID)
    # the first row is the state in force at `from`
    h2 = reconstruct_history(hx_id(hx_well),:Temperature;from=hx_slot[:w5])
    @test h2.SequenceID == [hx_slot[:w5],hx_slot[:wunset],hx_slot[:punset],hx_slot[:b31]]
    h3 = reconstruct_history(hx_id(hx_well),:Temperature;from=hx_slot[:w5] + 0)
    @test isequal(h3,h2)
    h4 = reconstruct_history(hx_id(hx_well),:Temperature;from=hx_slot[:wunset],to=hx_slot[:punset])
    # the state at `from` is 25 from the plate, which was set at :p25, before `from`
    @test h4.SequenceID == [hx_slot[:p25],hx_slot[:punset]] && h4.Value == [25.0,30.0]
    # the value of the matching reconstruction at every slot, with the default and an earlier time
    for tm in (Dates.now(),hx_time(hx_ledgers[:punset]),hx_time(hx_ledgers[:w5]))
        hist = reconstruct_history(hx_id(hx_well),:Temperature;time=tm)
        for s in 0:hx_last
            want = hx_quantity(CHESSCore.environment(reconstruct_environment(hx_id(hx_well),s,tm)),"Temperature")
            got = history_value_at(hist,s)
            @test (ismissing(want) && ismissing(got)) || (!ismissing(want) && !ismissing(got) && ustrip(uconvert(u"°C",want)) ≈ got)
        end
    end
    # a time before the later events leaves them out
    early = reconstruct_history(hx_id(hx_well),:Temperature;time=hx_time(hx_ledgers[:w5]))
    @test maximum(early.SequenceID) == hx_slot[:w5]
end

@testset "history: own events, collapse and the effect of a move" begin
    own = reconstruct_history(hx_id(hx_well),:Temperature;effective=false,from=hx_s0)
    @test own.SequenceID == [hx_slot[:w5],hx_slot[:wunset]] && isequal(own.Value,[5.0,missing]) && own.Origin == fill(hx_id(hx_well),2)
    # a location whose only temperature comes from the room it is moved into: the move is the row
    cold = generate_location(WP96,"hx cold plate")
    upload(move_into!,hx_a,cold)
    s_cold = get_last_sequence_id()
    upload(move_into!,hx_b,cold)
    r = reconstruct_history(hx_id(cold[1,1]),:Temperature;from=hx_s0)
    @test r.Value[end] == 31.0 && r.Origin[end] == hx_id(hx_b) && r.Event[end] == "move" && r.SequenceID[end] == s_cold + 1
    @test r.Value[end-1] == 20.0 && r.Origin[end-1] == hx_id(hx_a)
    # collapse=false keeps the cache rows and every event
    raw = reconstruct_history(hx_id(hx_cplate),:locked;collapse=false)
    col = reconstruct_history(hx_id(hx_cplate),:locked)
    @test nrow(raw) >= nrow(col) && "cache" in raw.Event
    @test all(history_value_at(raw,s) === history_value_at(col,s) for s in 0:hx_last)
end

@testset "history: parent, lock, activity, lot and instrument settings" begin
    p = reconstruct_history(hx_id(hx_plate),:parent;from=hx_s0)
    @test p.SequenceID == [hx_slot[:into_a],hx_slot[:into_b]] && p.Value == [hx_id(hx_a),hx_id(hx_b)] && p.Event == ["move","move"]
    @test ismissing(history_value_at(p,hx_slot[:into_a] - 1)) || history_value_at(p,hx_slot[:into_a] - 1) isa Int
    l = reconstruct_history(hx_id(hx_plate),:locked;from=hx_s0)
    @test l.Event[1] == "cache" && l.Value[1] == false      # the state the plate was created in
    l_events = l[l.Event .!= "cache",:]
    @test l_events.SequenceID == [hx_slot[:lock],hx_slot[:unlock]] && l_events.Value == [true,false] && l_events.Event == ["set_lock","set_lock"]
    a = reconstruct_history(hx_id(hx_well),:active;from=hx_s0)
    a_events = a[a.Event .!= "cache",:]
    @test a_events.SequenceID == [hx_slot[:deact],hx_slot[:react]] && a_events.Value == [false,true] && a_events.Event == ["set_activity","set_activity"]
    lot = reconstruct_history(hx_id(hx_bottle),:lot)
    @test lot.SequenceID[end-1:end] == [hx_slot[:lot1],hx_slot[:lot2]] && lot.Value[end-1:end] == ["Hx Supplier HX1 lot HXLOT1","Hx Supplier HX1 lot HXLOT2"]
    g = reconstruct_history(hx_id(hx_a),(:setting,"Gain"))
    @test g.SequenceID == [hx_slot[:gain1],hx_slot[:gain2]] && g.Value == ["1.5","2.5"] && g.Event == ["set_instrument_setting","set_instrument_setting"]
    @test reconstruct_history(hx_id(hx_a),(:setting,"Filter")).Value == ["F1"]
    @test nrow(reconstruct_history(hx_id(hx_a),(:setting,"Nothing"))) == 0
    # every facet against the reconstruction at every slot
    for s in 0:hx_last
        @test is_locked(reconstruct_lock(hx_id(hx_plate),s)) == coalesce(history_value_at(l,s),false)
        @test is_active(reconstruct_activity(hx_id(hx_well),s)) == coalesce(history_value_at(a,s),true)
        prt = CHESSCore.parent(reconstruct_parent(hx_id(hx_plate),s))
        @test (isnothing(prt) ? missing : location_id(prt)) === history_value_at(p,s)
        lt = reconstruct_lot(hx_id(hx_bottle),s)
        @test (isnothing(lt) ? missing : "$(lt.supplier) $(lt.catalog_number) lot $(lt.lot)") === history_value_at(lot,s)
    end
end

@testset "history: reads are paged by the time of the read" begin
    rd = generate_location(WP96,"hx read plate")[1,1]
    t0 = Dates.now() - Hour(1)
    for k in 1:5
        upload(record_read!,rd,Absorbance(10.0k*u"percent",t0 + Minute(k)))
    end
    all_reads = reconstruct_history(hx_id(rd),:Absorbance)
    @test nrow(all_reads) == 5 && all_reads.Value == [10.0k for k in 1:5] && all(==("read"),all_reads.Event) && all(==("percent"),all_reads.Unit)
    @test issorted(all_reads.Time)
    p1 = reconstruct_history(hx_id(rd),:Absorbance;limit=2)
    p2 = reconstruct_history(hx_id(rd),:Absorbance;limit=2,after=p1.Time[end])
    p3 = reconstruct_history(hx_id(rd),:Absorbance;limit=2,after=p2.Time[end])
    @test isequal(vcat(p1,p2,p3),all_reads)
    d1 = reconstruct_history(hx_id(rd),:Absorbance;limit=2,order=:desc)
    @test d1.Value == [50.0,40.0]
    d2 = reconstruct_history(hx_id(rd),:Absorbance;limit=2,order=:desc,after=d1.Time[end])
    @test d2.Value == [30.0,20.0]
    @test nrow(reconstruct_history(hx_id(rd),:Absorbance;to=get_last_sequence_id() - 10^6)) == 0
end

@testset "history: pages join up to the whole history in either order, under every window schedule" begin
    full = reconstruct_history(hx_id(hx_well),:Temperature)
    oldf,oldg,olds = CHESSDatabase._HISTORY_FIRST_WINDOW[],CHESSDatabase._HISTORY_GROWTH[],CHESSDatabase._SERIES_SCAN_FACTOR[]
    try
        for (first_window,growth,factor) in ((1,2,4),(2,3,0),(3,2,10^6),(256,8,4))
            CHESSDatabase._HISTORY_FIRST_WINDOW[] = first_window; CHESSDatabase._HISTORY_GROWTH[] = growth; CHESSDatabase._SERIES_SCAN_FACTOR[] = factor
            @test isequal(reconstruct_history(hx_id(hx_well),:Temperature),full)
            for order in (:asc,:desc), limit in (1,2,4)
                pages = DataFrame[]; after = nothing
                while true
                    pg = reconstruct_history(hx_id(hx_well),:Temperature;order=order,limit=limit,after=after)
                    nrow(pg) == 0 && break
                    @test nrow(pg) <= limit
                    push!(pages,pg); after = pg.SequenceID[end]
                    length(pages) > 100 && break
                end
                @test isequal(reduce(vcat,pages),order === :asc ? full : full[end:-1:1,:])
            end
            for facet in (:parent,:locked,:active)
                id = facet === :active ? hx_id(hx_well) : hx_id(hx_plate)
                @test isequal(reconstruct_history(id,facet;limit=1),reconstruct_history(id,facet)[1:1,:])
            end
        end
    finally
        CHESSDatabase._HISTORY_FIRST_WINDOW[],CHESSDatabase._HISTORY_GROWTH[],CHESSDatabase._SERIES_SCAN_FACTOR[] = oldf,oldg,olds
    end
    # `from`/`to` bound the page, `after` past the end gives an empty page
    @test nrow(reconstruct_history(hx_id(hx_well),:Temperature;after=hx_last)) == 0
    @test nrow(reconstruct_history(hx_id(hx_well),:Temperature;order=:desc,after=0)) == 0
end

@testset "history: arguments that are refused" begin
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:contents;effective=true)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:Temperature;encumbrances=true)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:NoSuchFacet)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_plate),:locked;effective=true)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:Temperature;order=:sideways)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:Temperature;limit=0)
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),:Temperature;after="x")
    @test_throws ArgumentError reconstruct_history(hx_id(hx_well),42)
    # a facet may be given as a kind or by name
    @test isequal(reconstruct_history(hx_id(hx_well),"Temperature"),reconstruct_history(hx_id(hx_well),:Temperature))
    @test isequal(reconstruct_history(hx_id(hx_well),CHESSCore.attribute_kinds[:Temperature]),reconstruct_history(hx_id(hx_well),:Temperature))
end

@testset "history: the queries read through indexes" begin
    for facet in (:parent,:locked,:active,:lot), loc in (hx_id(hx_plate),)
        sources = CHESSDatabase._history_sources(facet,"",loc)
        for src in sources, walk in (true,false)
            sql,params = CHESSDatabase._window_query(src,0,10^6,Dates.now(),walk)
            plan = hx_plan(sql,params)
            @test !any(l -> startswith(l,"SCAN") && !occursin("USING COVERING INDEX",l) && !occursin("USING INDEX",l),plan)
            @test !any(l -> occursin(r"^SCAN (Ledger|vl)\b",l) && walk === false,plan)
            @test !any(l -> occursin("MATERIALIZE",l) || occursin("CO-ROUTINE",l),plan)
        end
    end
    for (facet,name) in ((:attribute,"Temperature"),(:setting,"Gain"))
        for src in CHESSDatabase._history_sources(facet,name,hx_id(hx_plate)), walk in (true,false)
            sql,params = CHESSDatabase._window_query(src,0,10^6,Dates.now(),walk)
            plan = hx_plan(sql,params)
            @test !any(l -> startswith(l,"SCAN") && !occursin("INDEX",l),plan)
            @test !any(l -> occursin("MATERIALIZE",l),plan)
        end
    end
    # the walk is bounded by the window: a range of Ledger.SequenceID, not a scan
    src = CHESSDatabase._history_sources(:attribute,"Temperature",hx_id(hx_plate))[1]
    sql,params = CHESSDatabase._window_query(src,5,50,Dates.now(),true)
    @test any(l -> occursin(r"SEARCH vl USING (COVERING )?INDEX idx_chess_ledger_sequenceid_id \(SequenceID>\? AND SequenceID<\?\)",l) || occursin("SequenceID>? AND SequenceID<?",l),hx_plan(sql,params))
end

@testset "history: the property check catches a history with a row missing" begin
    h = reconstruct_history(hx_id(hx_well),:Temperature;from=hx_s0)
    bad = h[[1,2,4,5,6],:]   # the row of the well's own value left out
    differs = [s for s in 0:hx_last if !isequal(history_value_at(h,s),history_value_at(bad,s))]
    @test !isempty(differs)
    wrong = copy(h); wrong.SequenceID = wrong.SequenceID .+ 1
    @test any(s -> !isequal(history_value_at(h,s),history_value_at(wrong,s)),0:hx_last)
end
