# The transfer closure by frontier expansion (src/reconstruction/local_closure.jl) against the original
# whole-ledger queries it replaced (`_get_transfer_ancestors_global`, `_get_transfer_descendents_global`).
# One testset per proof obligation T1-T6 of CHESSDatabase/docs/transfer_closure.md. Every location is new (prefixed
# `tc_`) and runs against the shared database set up in build_test_database.jl.

tc_canon(x::DataFrame) = (names(x),sort!([join(string.(Tuple(r)),"\u1f") for r in eachrow(x)]))
tc_same_anc(locs,starting,ending,time) = tc_canon(CHESSDatabase.get_transfer_ancestors(collect(Int,locs),starting,ending,time)) ==
    tc_canon(CHESSDatabase._get_transfer_ancestors_global(collect(Int,locs),starting,ending,time))
tc_same_desc(locs,starting,ending,time) = tc_canon(CHESSDatabase.get_transfer_descendents(collect(Int,locs),starting,ending,time)) ==
    tc_canon(CHESSDatabase._get_transfer_descendents_global(collect(Int,locs),starting,ending,time))
tc_pairs(df) = Set((r.Source,ismissing(r.Destination) ? 0 : r.Destination) for r in eachrow(df))
tc_core(df) = tc_pairs(df[df.Core .== 1,:])

tc_bottle = commit_location!(build_location(Bottle1L,"tc bottle water"))
tc_bottle2 = commit_location!(build_location(Bottle1L,"tc bottle glycerol"))
observe(tc_bottle[1,1],rgt"water",500u"mL")
observe(tc_bottle2[1,1],rgt"glycerol",500u"mL")
tc_plate = generate_location(WP96,"tc plate")
tc_A,tc_B,tc_C,tc_D,tc_E,tc_F = (tc_plate[1,k] for k in 1:6)
tc_id(x) = location_id(x)
tc_src,tc_src2 = tc_bottle[1,1],tc_bottle2[1,1]

# A takes water and glycerol, passes some on to B and C, discards some, and a cycle D <-> E hangs on water
tc_l1 = upload(transfer!,tc_src,tc_A,100u"µL")
tc_l2 = upload(transfer!,tc_A,tc_B,30u"µL")
tc_l3 = upload(transfer!,tc_src2,tc_A,50u"µL")
tc_l4 = upload(transfer!,tc_A,tc_C,20u"µL")
tc_l5 = upload(discard!,tc_A,5u"µL")
tc_l6 = upload(transfer!,tc_src,tc_D,100u"µL")
tc_l7 = upload(transfer!,tc_D,tc_E,20u"µL")
tc_l8 = upload(transfer!,tc_E,tc_D,5u"µL")
tc_seq(l) = get_sequence_id(l)

@testset "transfer closure: ancestors match the original and have the documented shape" begin
    now_ = Dates.now()
    last_ = get_last_sequence_id()
    rows = CHESSDatabase.get_transfer_ancestors([tc_id(tc_C)],0,last_,now_)
    @test names(rows) == ["LedgerID","Source","Destination","Quantity","Unit","Core","SequenceID"]
    # T5: one row per ledger entry, oldest first
    @test allunique(rows.LedgerID)
    @test issorted(rows.SequenceID)
    # T2/T3: C is fed by A, A by both bottles; T4: what A sent to B and the discard are collateral
    @test tc_core(rows) == Set([(tc_id(tc_A),tc_id(tc_C)),(tc_id(tc_src),tc_id(tc_A)),(tc_id(tc_src2),tc_id(tc_A))])
    @test tc_pairs(rows[rows.Core .== 0,:]) == Set([(tc_id(tc_A),tc_id(tc_B)),(tc_id(tc_A),0),(tc_id(tc_src),tc_id(tc_D))])
    discard_row = rows[rows.LedgerID .== tc_l5,:]
    @test nrow(discard_row) == 1 && ismissing(discard_row.Destination[1]) && discard_row.Core[1] == 0
    @test tc_same_anc([tc_id(tc_C)],0,last_,now_)
    # several locations, a source only, a destination only, an unrelated location
    for locs in ([tc_id(tc_B),tc_id(tc_C)],[tc_id(tc_src)],[tc_id(tc_E)],[tc_id(tc_F)],[tc_id(tc_F),tc_id(tc_B)],Int[])
        @test tc_same_anc(locs,0,last_,now_)
    end
    none = CHESSDatabase.get_transfer_ancestors([tc_id(tc_F)],0,last_,now_)
    @test nrow(none) == 0 && names(none) == names(rows)
end

@testset "transfer closure: a cycle ends and expands each well once" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    rows = CHESSDatabase.get_transfer_ancestors([tc_id(tc_E)],0,last_,now_)
    @test tc_core(rows) == Set([(tc_id(tc_src),tc_id(tc_D)),(tc_id(tc_D),tc_id(tc_E)),(tc_id(tc_E),tc_id(tc_D))])
    @test tc_same_anc([tc_id(tc_E)],0,last_,now_)
    @test tc_same_anc([tc_id(tc_D)],0,last_,now_)
    down = CHESSDatabase.get_transfer_descendents([tc_id(tc_D)],0,last_,now_)
    @test tc_pairs(down) ⊇ Set([(tc_id(tc_D),tc_id(tc_E)),(tc_id(tc_E),tc_id(tc_D))])
    @test tc_same_desc([tc_id(tc_D)],0,last_,now_)
end

@testset "transfer closure T1: visibility of amended slots, windows and time cut-offs" begin
    t_before = Dates.now(); sleep(0.05)
    seq_l4 = tc_seq(tc_l4)
    # amend A -> C into A -> F with another quantity
    tc_l4b = update(transfer!,reconstruct_location(tc_id(tc_A)),reconstruct_location(tc_id(tc_F)),12u"µL";replace=seq_l4)
    sleep(0.05); t_after = Dates.now(); last_ = get_last_sequence_id()
    old = CHESSDatabase.get_transfer_ancestors([tc_id(tc_C)],0,last_,t_before)
    new = CHESSDatabase.get_transfer_ancestors([tc_id(tc_C)],0,last_,t_after)
    @test (tc_id(tc_A),tc_id(tc_C)) in tc_core(old)           # as of before the amendment
    @test (tc_id(tc_A),tc_id(tc_C)) ∉ tc_pairs(new)             # superseded now
    @test (tc_id(tc_A),tc_id(tc_F)) in tc_pairs(CHESSDatabase.get_transfer_ancestors([tc_id(tc_F)],0,last_,t_after))
    for locs in ([tc_id(tc_C)],[tc_id(tc_F)],[tc_id(tc_B),tc_id(tc_C),tc_id(tc_F)],[tc_id(tc_A)])
        for t in (t_before,t_after), (from,to) in ((0,last_),(seq_l4,last_),(0,seq_l4),(seq_l4+1,last_),(0,tc_seq(tc_l2)),(tc_seq(tc_l3),seq_l4))
            @test tc_same_anc(locs,from,to,t)
            @test tc_same_desc(locs,from,to,t)
        end
    end
    # a time before anything was written
    @test tc_same_anc([tc_id(tc_C)],0,last_,Dates.DateTime(2000,1,1))
    @test nrow(CHESSDatabase.get_transfer_ancestors([tc_id(tc_C)],0,last_,Dates.DateTime(2000,1,1))) == 0
end

@testset "transfer closure T6: descendants follow transfers the window hides, and filter at the end" begin
    # P -> Q is outside the window, Q -> S inside it
    tc_P,tc_Q,tc_S = tc_plate[2,1],tc_plate[2,2],tc_plate[2,3]
    upload(transfer!,tc_src,tc_P,50u"µL")
    l_pq = upload(transfer!,tc_P,tc_Q,20u"µL")
    l_qs = upload(transfer!,tc_Q,tc_S,10u"µL")
    now_ = Dates.now(); last_ = get_last_sequence_id()
    from = tc_seq(l_qs)
    down = CHESSDatabase.get_transfer_descendents([tc_id(tc_P)],from,last_,now_)
    @test tc_pairs(down) == Set([(tc_id(tc_Q),tc_id(tc_S))])         # P -> Q is not visible in the window, Q -> S is reached through it
    @test names(down) == ["LedgerID","EncumbranceID","Source","Destination","Quantity","Unit","ID","SequenceID","Time"]
    @test tc_same_desc([tc_id(tc_P)],from,last_,now_)
    # ancestors filter first: the hidden transfer does not lead to P
    up = CHESSDatabase.get_transfer_ancestors([tc_id(tc_S)],from,last_,now_)
    @test tc_core(up) == Set([(tc_id(tc_Q),tc_id(tc_S))])
    @test tc_same_anc([tc_id(tc_S)],from,last_,now_)
    # discards are not followed by descendants, but are collateral for ancestors
    @test all(!ismissing, CHESSDatabase.get_transfer_descendents([tc_id(tc_A)],0,last_,now_).Destination)
end

@testset "transfer closure: the original is used for encumbrances, the legacy mode and many locations" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    locs = [tc_id(tc_C),tc_id(tc_E)]
    expected = tc_canon(CHESSDatabase._get_transfer_ancestors_global(locs,0,last_,now_))
    old_mode = CHESSDatabase.reconstruction_mode[]; old_limit = CHESSDatabase.LOCAL_KEY_LIMIT[]
    try
        CHESSDatabase.reconstruction_mode[] = :legacy
        @test tc_canon(CHESSDatabase.get_transfer_ancestors(locs,0,last_,now_)) == expected
        @test tc_canon(CHESSDatabase.get_transfer_descendents(locs,0,last_,now_)) == tc_canon(CHESSDatabase._get_transfer_descendents_global(locs,0,last_,now_))
        CHESSDatabase.reconstruction_mode[] = :local
        CHESSDatabase.LOCAL_KEY_LIMIT[] = 1
        @test tc_canon(CHESSDatabase.get_transfer_ancestors(locs,0,last_,now_)) == expected
        CHESSDatabase.LOCAL_KEY_LIMIT[] = old_limit
        @test tc_canon(CHESSDatabase.get_transfer_ancestors(locs,0,last_,now_)) == expected
        @test tc_canon(CHESSDatabase.get_transfer_ancestors(locs,0,last_,now_;encumbrances=true)) ==
            tc_canon(CHESSDatabase._get_transfer_ancestors_global(locs,0,last_,now_;encumbrances=true))
    finally
        CHESSDatabase.reconstruction_mode[] = old_mode; CHESSDatabase.LOCAL_KEY_LIMIT[] = old_limit
    end
end

@testset "transfer closure: transfers_touch and transfers_touched_by give what they gave" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    outcome(f) = try (:ok,sort(collect(f()))) catch err; (:err,typeof(err)) end
    touching = outcome(()->CHESSDatabase.transfers_touch(tc_id(tc_src),0,last_,now_))
    @test touching[1] === :ok
    @test tc_id(tc_A) in first.(touching[2]) && tc_id(tc_D) in first.(touching[2])
    # `transfers_touched_by` reads an EncumbranceID column that the ancestors query only has with encumbrances=true,
    # so without encumbrances it throws whenever there is a row to read, as it always did
    touched = outcome(()->CHESSDatabase.transfers_touched_by(tc_id(tc_F),0,last_,now_))
    touched_enc = outcome(()->CHESSDatabase.transfers_touched_by(tc_id(tc_F),0,last_,now_;encumbrances=true))
    @test touched_enc[1] === :ok && tc_id(tc_A) in first.(touched_enc[2])
    old_mode = CHESSDatabase.reconstruction_mode[]
    try
        CHESSDatabase.reconstruction_mode[] = :legacy
        @test outcome(()->CHESSDatabase.transfers_touch(tc_id(tc_src),0,last_,now_)) == touching
        @test outcome(()->CHESSDatabase.transfers_touched_by(tc_id(tc_F),0,last_,now_)) == touched
        @test outcome(()->CHESSDatabase.transfers_touched_by(tc_id(tc_F),0,last_,now_;encumbrances=true)) == touched_enc
    finally
        CHESSDatabase.reconstruction_mode[] = old_mode
    end
end

@testset "forward tracing: transfers out of a well are read in sequence order" begin
    # A -> B (3), B -> C (6), A -> C (9), C -> D: C is reached first through B (depth 2), so D is at depth 3
    ta,tb,tcc,td = tc_plate[3,1],tc_plate[3,2],tc_plate[3,3],tc_plate[3,4]
    upload(transfer!,tc_src,ta,200u"µL")
    upload(transfer!,ta,tb,50u"µL")
    upload(transfer!,tb,tcc,10u"µL")
    upload(transfer!,ta,tcc,50u"µL")
    upload(transfer!,tcc,td,20u"µL")
    now_ = Dates.now()
    trace = trace_forward(tc_id(ta),get_last_sequence_id(),now_)
    depth = Dict(r.WellID=>r.Depth for r in eachrow(trace)); via = Dict(r.WellID=>r.ViaWell for r in eachrow(trace))
    @test depth[tc_id(tb)] == 1 && depth[tc_id(tcc)] == 2 && depth[tc_id(td)] == 3
    @test via[tc_id(tcc)] == tc_id(tb) && via[tc_id(td)] == tc_id(tcc)
    out = CHESSDatabase._transfers_out_of([tc_id(ta),tc_id(tb),tc_id(tcc)],get_last_sequence_id(),now_)
    @test issorted(out.SequenceID)
    @test Set(zip(out.Source,out.Destination)) == Set([(tc_id(ta),tc_id(tb)),(tc_id(tb),tc_id(tcc)),(tc_id(ta),tc_id(tcc)),(tc_id(tcc),tc_id(td))])
    # the same through the whole-ledger query, and at an earlier sequence ID
    for seq in (get_last_sequence_id(),get_last_sequence_id()-2,get_last_sequence_id()-4)
        a = CHESSDatabase._transfers_out_of([tc_id(ta),tc_id(tb),tc_id(tcc)],seq,now_)
        b = CHESSDatabase._transfers_out_of_global([tc_id(ta),tc_id(tb),tc_id(tcc)],seq,now_)
        @test tc_canon(a) == tc_canon(b)
    end
    old_mode = CHESSDatabase.reconstruction_mode[]
    try
        CHESSDatabase.reconstruction_mode[] = :legacy
        legacy = trace_forward(tc_id(ta),get_last_sequence_id(),now_)
        @test tc_canon(legacy) == tc_canon(trace)
    finally
        CHESSDatabase.reconstruction_mode[] = old_mode
    end
end
