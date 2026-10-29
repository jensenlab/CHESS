# Simultaneous ticks (section 6 of the reconstruction plan, decision D4 = O3). Every location is new (prefixed `tk`).

import CHESSDatabase: get_transfer_participants, get_movement_participants, get_transfer_ancestors, get_transfer_descendents, isa_transfer, validate, cache_repair

tk_rows(table) = nrow(query_db("SELECT 1 FROM $table"))
tk_water(w) = get(liquids(stock(reconstruct_contents(location_id(w)))),rgt"water",0u"mL")
tk_temperature(loc) = CHESSCore.value(CHESSCore.attributes(reconstruct_attributes(location_id(loc)))[:Temperature])

# a message that names both rows of the pair
function tk_throws_naming(f,fragments...)
    err = try f(); nothing catch e e end
    err isa ArgumentError || return false
    return all(fr -> occursin(fr,err.msg),fragments)
end

@testset "ticks: the rule, enforced when a tick is written" begin
    room = generate_location(Room,"tk rule room")
    other = generate_location(Room,"tk rule other")

    # attributes of different kinds, and a read, share a tick
    l = upload(set_attribute!,room,Temperature(20u"°C"))
    upload(set_attribute!,room,Pressure(1u"atm");ledger_id=l)
    upload(record_read!,room,Observation("tk read");ledger_id=l)
    upload(set_attribute!,other,Temperature(21u"°C");ledger_id=l)
    @test sort(operation_classes(l)) == [:attribute,:read]
    @test nrow(tick_operations(l)) == 4

    # the same fact twice does not, and the error names the pair and leaves the tick as it was
    n = tk_rows("EnvironmentAttributes")
    @test tk_throws_naming(() -> upload(set_attribute!,room,Temperature(25u"°C");ledger_id=l),
        "ledger entry $l","EnvironmentAttributes row","same fact","attribute $(location_id(room)) Temperature")
    @test tk_rows("EnvironmentAttributes") == n

    # an operation that depends on order must be alone, whichever comes first
    src = generate_location(Bottle1L,"tk rule src")[1,1]; dst = generate_location(Bottle1L,"tk rule dst")[1,1]
    observe(src,rgt"water",100u"mL")
    t = upload(transfer!,src,dst,10u"mL")
    @test tk_throws_naming(() -> upload(transfer!,src,dst,10u"mL";ledger_id=t),"Transfers row","must be alone")
    @test tk_throws_naming(() -> upload(record_read!,src,Observation("x");ledger_id=t),"Transfers row","Reads row","must be alone")
    @test tk_throws_naming(() -> upload(set_attribute!,room,Humidity(40u"percent");ledger_id=t),"Transfers row","EnvironmentAttributes row")
    @test tk_throws_naming(() -> upload(transfer!,src,dst,10u"mL";ledger_id=l),"EnvironmentAttributes row","Transfers row","must be alone")
    @test nrow(query_db("SELECT 1 FROM Transfers WHERE LedgerID = ?",(t,))) == 1

    # observations of different facts share a tick; the same fact twice does not
    o = observe(src,rgt"water",90u"mL")
    @test tk_throws_naming(() -> observe(src,rgt"water",80u"mL";ledger_id=o),"ObservedComponents row","same fact","component")
    observe(dst,rgt"water",5u"mL";ledger_id=o)
    @test nrow(tick_operations(o)) == 2

    # the enforcement can be switched off, and back on
    @test CHESSDatabase.tick_rule_enforced[]
    @test tick_rule_enforcement!(false)
    try
        @test_nowarn upload(set_attribute!,room,Temperature(25u"°C");ledger_id=l)
    finally
        @test !tick_rule_enforcement!(true)
    end
    @test_throws ArgumentError check_tick(l)
end

@testset "ticks: upload_tick and update_tick" begin
    room = generate_location(Room,"tk tick room")
    l = upload_tick((set_attribute!,room,Temperature(30u"°C")),(set_attribute!,room,Pressure(2u"atm")),(record_read!,room,Observation("tk r1")))
    @test nrow(tick_operations(l)) == 3
    @test get_sequence_id(l) == get_last_sequence_id()
    env = CHESSCore.attributes(reconstruct_attributes(location_id(room)))
    @test CHESSCore.value(env[:Temperature]) == 30 && CHESSCore.value(env[:Pressure]) == 2

    # nothing is recorded when the tick breaks the rule or an operation fails
    n = nrow(query_db("SELECT 1 FROM Ledger"))
    @test tk_throws_naming(() -> upload_tick((set_attribute!,room,Temperature(1u"°C")),(set_attribute!,room,Temperature(2u"°C"))),"same fact")
    @test_throws ArgumentError upload_tick()
    @test nrow(query_db("SELECT 1 FROM Ledger")) == n

    # the complete set replaces the entry: siblings that are not repeated are dropped, those repeated are kept
    seq = get_sequence_id(l)
    before = Dates.now(); sleep(0.05)
    l2 = update_tick((set_attribute!,room,Temperature(31u"°C")),(set_attribute!,room,Pressure(2u"atm")),(record_read!,room,Observation("tk r1"));replace=seq)
    @test get_sequence_id(l2) == seq
    env = CHESSCore.attributes(reconstruct_attributes(location_id(room)))
    @test CHESSCore.value(env[:Temperature]) == 31 && CHESSCore.value(env[:Pressure]) == 2
    old = CHESSCore.attributes(reconstruct_attributes(location_id(room),seq,before))
    @test CHESSCore.value(old[:Temperature]) == 30
    @test nrow(tick_operations(l2)) == 3

    # a replacement of one operation would drop the others: refused, whatever the operation is
    n = nrow(query_db("SELECT 1 FROM Ledger"))
    @test tk_throws_naming(() -> update(set_attribute!,room,Temperature(40u"°C");replace=seq),"slot $seq holds 3 operations","update_tick")
    @test nrow(query_db("SELECT 1 FROM Ledger")) == n
    @test CHESSCore.value(CHESSCore.attributes(reconstruct_attributes(location_id(room)))[:Temperature]) == 31
    # a slot of one operation is replaced as before
    s1 = upload(set_attribute!,room,Humidity(10u"percent"))
    @test update(set_attribute!,room,Humidity(11u"percent");replace=get_sequence_id(s1)) isa Integer

    # a replacement has to be the same kinds of operation, and the rule applies to it
    @test_throws ErrorException update_tick((record_read!,room,Observation("tk r2"));replace=seq)
    @test tk_throws_naming(() -> update_tick((set_attribute!,room,Temperature(1u"°C")),(set_attribute!,room,Temperature(2u"°C"));replace=seq),"same fact")
    @test CHESSCore.value(CHESSCore.attributes(reconstruct_attributes(location_id(room)))[:Temperature]) == 31
    @test_throws ArgumentError update_tick((record_read!,room,Observation("x"));replace=seq,insert=seq)

    # an insert states the whole entry too
    ins = update_tick((set_attribute!,room,Oxygen(21u"percent")),(record_read!,room,Observation("tk inserted"));insert=seq)
    @test get_sequence_id(ins) == seq && get_sequence_id(l2) == seq + 1
    @test nrow(tick_operations(ins)) == 2
end

@testset "ticks: a tick of observations is replaced as a whole" begin
    w = generate_location(Bottle1L,"tk obs bottle")[1,1]
    o = upload_tick((observe!,w,rgt"water",5u"mL"),(observe!,w,rgt"paba",2u"g"))
    n_ops = nrow(tick_operations(o))
    @test n_ops == 2
    seq = get_sequence_id(o)
    @test tk_throws_naming(() -> update(observe!,w,rgt"water",1u"mL";replace=seq),"slot $seq holds $n_ops operations")
    l = update_tick((observe!,w,rgt"water",1u"mL");replace=seq)
    @test nrow(tick_operations(l)) == 1
end

@testset "ticks: the audit query" begin
    clean = with_scratch_db() do _
        room = generate_location(Room,"tk audit room")
        upload_tick((set_attribute!,room,Temperature(30u"°C")),(set_attribute!,room,Pressure(2u"atm")))
        a = generate_location(Bottle1L,"tk audit a")[1,1]; b = generate_location(Bottle1L,"tk audit b")[1,1]
        observe(a,rgt"water",100u"mL")
        upload(transfer!,a,b,10u"mL")
        audit_ticks()
    end
    @test clean isa DataFrame && nrow(clean) == 0
    @test names(clean) == ["LedgerID","SequenceID","Current","First","Second","Reason","Operations"]

    dirty = with_scratch_db() do _
        room = generate_location(Room,"tk audit room")
        a = generate_location(Bottle1L,"tk audit a")[1,1]; b = generate_location(Bottle1L,"tk audit b")[1,1]; c = generate_location(Bottle1L,"tk audit c")[1,1]
        observe(a,rgt"water",100u"mL")
        local t,s,m,r,u
        old = tick_rule_enforcement!(false)
        try
            t = upload(transfer!,a,b,10u"mL")
            upload(transfer!,a,c,10u"mL";ledger_id=t)                        # two transfers
            s = upload(set_attribute!,room,Temperature(20u"°C"))
            upload(set_attribute!,room,Temperature(21u"°C");ledger_id=s)      # one fact twice
            m = upload(set_attribute!,room,Pressure(1u"atm"))
            upload(record_read!,room,Observation("audit");ledger_id=m)        # allowed
            r = upload(record_read!,room,Observation("audit 2"))
            upload(transfer!,a,b,1u"mL";ledger_id=r)                          # a read and a transfer
            # a superseded revision that broke the rule
            u = upload(transfer!,a,b,1u"mL")
            upload(transfer!,a,c,1u"mL";ledger_id=u)
            update_tick((transfer!,a,b,1u"mL");replace=get_sequence_id(u))
        finally
            tick_rule_enforcement!(old)
        end
        (audit_ticks(),get_sequence_id.([t,s,m,r,u]),t,s,u)
    end
    out,seqs,t,s,u = dirty
    @test nrow(out) == 4
    @test out.SequenceID == sort(seqs[[1,2,4,5]])
    bytick(l) = out[out.LedgerID .== l,:]
    @test bytick(t).Current == [true] && bytick(t).Operations == [2]
    @test occursin("Transfers row",bytick(t).First[1]) && occursin("Transfers row",bytick(t).Second[1])
    @test occursin("must be alone",bytick(t).Reason[1])
    @test occursin("same fact",bytick(s).Reason[1]) && occursin("Temperature",bytick(s).Reason[1])
    @test bytick(u).Current == [false]
    @test count(out.Current) == 3
    # the entry of a tick that is allowed is not reported
    @test !(seqs[3] in out.SequenceID)
end

@testset "ticks: an entry holding several operations of a kind" begin
    # these ticks exist only in data written before the rule: the code that reads them has to cope
    a = generate_location(Bottle1L,"tk multi a")[1,1]; b = generate_location(Bottle1L,"tk multi b")[1,1]; c = generate_location(Bottle1L,"tk multi c")[1,1]
    observe(a,rgt"water",500u"mL")
    old = tick_rule_enforcement!(false)
    local t
    try
        t = upload(transfer!,a,b,100u"mL")
        upload(transfer!,a,c,130u"mL";ledger_id=t)
        upload(transfer!,a,b,100u"mL";ledger_id=t)  # identical to the first
    finally
        tick_rule_enforcement!(old)
    end
    @test isa_transfer(t)
    @test get_transfer_participants(t) == [(location_id(a),location_id(b)),(location_id(a),location_id(c)),(location_id(a),location_id(b))]

    # replay applies every one of them (before, the second withdrawal from a was lost)
    @test tk_water(a) ≈ 170u"mL"
    @test tk_water(b) ≈ 200u"mL"
    @test tk_water(c) ≈ 130u"mL"
    seq = get_sequence_id(t)
    @test tk_water(a) ≈ liquids(stock(reconstruct_contents(location_id(a),seq)))[rgt"water"]
    @test liquids(stock(reconstruct_contents(location_id(a),seq-1)))[rgt"water"] ≈ 500u"mL"
    # with and without a cache, from the cache and from the ledger
    for w in (a,b,c)
        cached = stock(reconstruct_contents(location_id(w)))
        execute_db("DELETE FROM CachedContents WHERE LocationID = ?",(location_id(w),))
        @test stock(reconstruct_contents(location_id(w))) == cached
    end

    # the closure keeps every row of the tick, as core or collateral, in the order they were recorded
    rows = get_transfer_ancestors([location_id(c)],0,get_last_sequence_id())
    @test nrow(rows) == 3
    @test rows.Quantity == [100.0,130.0,100.0] && rows.Core == [0,1,0]
    both = get_transfer_ancestors([location_id(b),location_id(c)],0,get_last_sequence_id())
    @test nrow(both) == 3 && all(both.Core .== 1)
    CHESSDatabase.reconstruction_mode[] = :legacy
    try
        @test isequal(get_transfer_ancestors([location_id(c)],0,get_last_sequence_id()),rows)
        @test isequal(get_transfer_ancestors([location_id(b),location_id(c)],0,get_last_sequence_id()),both)
        @test nrow(get_transfer_descendents([location_id(a)],0,get_last_sequence_id())) == 3
    finally
        CHESSDatabase.reconstruction_mode[] = :local
    end
    @test nrow(get_transfer_descendents([location_id(a)],0,get_last_sequence_id())) == 3
    @test nrow(get_transfer_descendents([location_id(c)],0,get_last_sequence_id())) == 1

    # validation and cache repair see every row of the entry
    @test validate(t) === nothing
    @test cache_repair(t) === nothing
    @test operation_classes(t) == [:transfer]

    # a tick of two discards, and a tick of two movements
    d = generate_location(Bottle1L,"tk multi d")[1,1]
    observe(d,rgt"water",100u"mL")
    old = tick_rule_enforcement!(false)
    local dd
    try
        dd = upload(discard!,d,10u"mL")
        upload(discard!,d,20u"mL";ledger_id=dd)
    finally
        tick_rule_enforcement!(old)
    end
    @test tk_water(d) ≈ 70u"mL"
    @test validate(dd) === nothing && cache_repair(dd) === nothing
    room = generate_location(Room,"tk multi room"); room2 = generate_location(Room,"tk multi room 2")
    x = generate_location(Bottle1L,"tk multi x"); y = generate_location(Bottle1L,"tk multi y")
    old = tick_rule_enforcement!(false)
    local mv
    try
        mv = upload(move_into!,room,x)
        upload(move_into!,room2,y;ledger_id=mv)
    finally
        tick_rule_enforcement!(old)
    end
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(x)))) == location_id(room)
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(y)))) == location_id(room2)
    @test validate(mv) === nothing && cache_repair(mv) === nothing
    @test get_movement_participants(mv) == [(location_id(room),location_id(x)),(location_id(room2),location_id(y))]
end

@testset "ticks: amending a history that has a tick of several transfers" begin
    a = generate_location(Bottle1L,"tk amend a")[1,1]; b = generate_location(Bottle1L,"tk amend b")[1,1]; c = generate_location(Bottle1L,"tk amend c")[1,1]
    observe(a,rgt"water",500u"mL")
    old = tick_rule_enforcement!(false)
    local t
    try
        t = upload(transfer!,a,b,100u"mL")
        upload(transfer!,a,c,50u"mL";ledger_id=t)
    finally
        tick_rule_enforcement!(old)
    end
    seq = get_sequence_id(t)
    # the entry of both can be replaced as a whole, and then each of its transfers is validated and its caches repaired
    for w in (a,b,c)
        cache(reconstruct_contents(location_id(w)))
    end
    l = update_tick((transfer!,a,b,100u"mL");replace=seq)
    @test tk_water(a) ≈ 400u"mL" && tk_water(b) ≈ 100u"mL" && tk_water(c) ≈ 0u"mL"
end
