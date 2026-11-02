# Encumbered observations (CHESS request 21): `encumber(protocol_id, observe!, well, component, amount)` plans that a
# well holds a component at an amount. Encumbered reconstruction applies it in encumbrance order, as it applies an
# encumbered transfer. Every location here is new (prefixed `eo_`).

eo_room = generate_location(Room,"eo room")
eo_bottle(name) = (b = generate_location(Bottle1L,name); upload(move_into!,eo_room,b); b[1,1])
eo_contents(w;kw...) = stock(reconstruct_location(location_id(w);kw...))
eo_liquid(w,r;kw...) = get(liquids(eo_contents(w;kw...)),r,0u"mL")
eo_protocol(name) = upload_protocol(upload_experiment(name,"Ben"),name)

@testset "encumber(observe!) applies in memory, is recorded, and is read back only when planned operations are asked for" begin
    w = eo_bottle("eo plain")
    p = eo_protocol("eo plain")
    e = encumber(p,observe!,w,rgt"water",250u"mL")
    @test stock(w) == 250u"mL"*rgt"water" # applied in memory
    row = CHESSDatabase.get_encumbered_observation(e)
    @test nrow(row) == 1 && row.LocationID[1] == location_id(w) && row.Quantity[1] ≈ 250 && row.Unit[1] == "mL"
    @test CHESSDatabase.get_encumbrance_operation(e) === CHESSDatabase.get_encumbered_observation
    @test only(CHESSDatabase.get_encumbrance_status(p).Operation) == "Observation"
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 250u"mL"
    @test eo_contents(w) isa Empty # nothing recorded in the ledger
    @test eo_contents(w;encumbrances=true) == 250u"mL"*rgt"water"
end

@testset "a planned untraced addition of water; a later planned transfer of more than the glycerol alone" begin
    w = eo_bottle("eo glycerol tube")
    observe(w,rgt"glycerol",100u"mL")
    p_fill = eo_protocol("eo fill")
    encumber(p_fill,observe!,w,rgt"water",50u"mL")
    @test eo_liquid(w,rgt"glycerol";encumbrances=true) ≈ 100u"mL"
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 50u"mL"
    @test eo_liquid(w,rgt"water") == 0u"mL"

    sink = eo_bottle("eo sink")
    p_draw = eo_protocol("eo draw")
    e_draw = encumber(p_draw,transfer!,w,sink,120u"mL") # more than the 100 mL of glycerol
    @test quantity(eo_contents(sink;encumbrances=true)) ≈ 120u"mL"
    @test quantity(eo_contents(w;encumbrances=true)) ≈ 30u"mL"
    # the planned transfer takes the mixture, not one component
    @test eo_liquid(sink,rgt"water";encumbrances=true) ≈ 120u"mL"*(50/150)
    # one slice of history: the sink read at the last ledger entry still sees the planned fill and draw
    @test quantity(stock(reconstruct_contents(location_id(sink),get_last_sequence_id();encumbrances=true))) ≈ 120u"mL"
    @test eo_contents(sink) isa Empty

    # the fill is lifted while the draw is enforced: the draw is out of a well that holds too little
    CHESSDatabase.upload_protocol_enforcement(p_fill,false)
    err = try; reconstruct_location(location_id(sink);encumbrances=true); nothing; catch e; e; end
    @test err isa UnfilledDrawError
    @test err.encumbrance_id == e_draw && err.source == location_id(w)
    @test err.quantity ≈ 120u"mL" && err.available ≈ 100u"mL"
    @test_throws UnfilledDrawError reconstruct_location(location_id(w);encumbrances=true) # the draw is replayed against the well
    # the fill is enforced again
    CHESSDatabase.upload_protocol_enforcement(p_fill,true)
    @test quantity(eo_contents(sink;encumbrances=true)) ≈ 120u"mL"
end

@testset "protocol enforcement turns the observation on and off" begin
    w = eo_bottle("eo switch")
    p = eo_protocol("eo switch")
    encumber(p,observe!,w,rgt"water",80u"mL")
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 80u"mL"
    CHESSDatabase.upload_protocol_enforcement(p,false)
    @test eo_contents(w;encumbrances=true) isa Empty
    CHESSDatabase.upload_protocol_enforcement(p,true)
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 80u"mL"
    # enforcement is read as of the sequence point asked for
    off = get_last_sequence_id() # enforced
    CHESSDatabase.upload_protocol_enforcement(p,false)
    @test eo_liquid(w,rgt"water";encumbrances=true) == 0u"mL"
    @test quantity(stock(reconstruct_contents(location_id(w),off;encumbrances=true))) ≈ 80u"mL"
end

@testset "an expected container: a location created now that holds a reagent whose lot is unknown" begin
    exp_bottle = eo_bottle("eo expected bottle")
    p = eo_protocol("eo order")
    encumber(p,observe!,exp_bottle,rgt"glycerol",500u"mL")
    @test eo_liquid(exp_bottle,rgt"glycerol";encumbrances=true) ≈ 500u"mL"
    @test eo_contents(exp_bottle) isa Empty # not received

    dest = eo_bottle("eo expected dest")
    p_use = eo_protocol("eo use of order")
    encumber(p_use,transfer!,exp_bottle,dest,200u"mL")
    @test eo_liquid(dest,rgt"glycerol";encumbrances=true) ≈ 200u"mL"
    @test eo_liquid(exp_bottle,rgt"glycerol";encumbrances=true) ≈ 300u"mL"
    # cancelling the order leaves the draw out of an empty bottle
    CHESSDatabase.upload_protocol_enforcement(p,false)
    @test_throws UnfilledDrawError reconstruct_location(location_id(dest);encumbrances=true)
end

@testset "a planned observation of a component the well already holds sets the amount" begin
    w = eo_bottle("eo increase")
    observe(w,rgt"water",100u"mL")
    p = eo_protocol("eo increase")
    encumber(p,observe!,w,rgt"water",150u"mL")
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 150u"mL"
    @test eo_liquid(w,rgt"water") ≈ 100u"mL"
    # and a planned decrease
    p2 = eo_protocol("eo decrease")
    encumber(p2,observe!,w,rgt"water",40u"mL")
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 40u"mL" # encumbrance order: the later plan wins
end

@testset "lineage of an observed increase: trace_contents reads the ledger only" begin
    lot = Lot("EO Supplier","EO-1","EO-LOT";quantity=1u"L")
    bottle = generate_location(Bottle1L,"eo lot bottle")
    observe(bottle[1,1],rgt"water",100u"mL")
    observe(bottle,lot)
    w = bottle[1,1]
    before = trace_contents(location_id(w))
    @test nrow(before) == 1 && only(before).Lot == lot && only(before).Quantity ≈ 100u"mL"
    p = eo_protocol("eo lineage")
    encumber(p,observe!,w,rgt"water",150u"mL")
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 150u"mL"
    # a planned observation is not in the ledger, so the trace does not see it
    @test trace_contents(location_id(w)) == before
    # recording the observation later is a real observed increase (CHESS request 16): the existing share is scaled, so
    # all 150 mL are credited to the bottle's lot
    observe(w,rgt"water",150u"mL")
    after = trace_contents(location_id(w))
    @test nrow(after) == 1 && only(after).Lot == lot && only(after).Quantity ≈ 150u"mL"
end

@testset "the cache does not hide a planned observation" begin
    w = eo_bottle("eo cached")
    observe(w,rgt"water",100u"mL")
    cache(w)
    p = eo_protocol("eo cached")
    encumber(p,observe!,w,rgt"water",130u"mL")
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 130u"mL"
    # a later cache of the real contents. `w` itself holds the planned state in memory after `encumber`, so a fresh copy of the
    # recorded state is observed and cached
    real = reconstruct_location(location_id(w))
    observe(real,rgt"glycerol",10u"mL")
    cache(real)
    @test eo_liquid(w,rgt"water";encumbrances=true) ≈ 130u"mL"
    @test eo_liquid(w,rgt"glycerol";encumbrances=true) ≈ 10u"mL"
    @test eo_liquid(w,rgt"water") ≈ 100u"mL"
    # a bound on the caches used does not change it
    @test quantity(stock(reconstruct_location(location_id(w),get_last_sequence_id(),Dates.now(),0;encumbrances=true))) ≈ 140u"mL"
end

@testset "reconstruct_history sees the planned observation" begin
    w = eo_bottle("eo history")
    p = eo_protocol("eo history")
    encumber(p,observe!,w,rgt"glycerol",60u"mL")
    h = reconstruct_history(location_id(w),:contents;from=0,encumbrances=true)
    @test quantity(h[end,:Value]) ≈ 60u"mL"
    h0 = reconstruct_history(location_id(w),:contents;from=0)
    @test h0[end,:Value] isa Empty || ismissing(h0[end,:Value]) || quantity(h0[end,:Value]) == 0u"mL"
end

@testset "a database without the table gains it on connect" begin
    @test CHESSDatabase._table_exists("EncumberedObservations")
    execute_db("DROP TABLE EncumberedObservations")
    @test !CHESSDatabase._table_exists("EncumberedObservations")
    @test nrow(CHESSDatabase.get_encumbered_observations([1])) == 0 # reads cope with a missing table
    CHESSDatabase._ensure_encumbered_observation_table!()
    @test CHESSDatabase._table_exists("EncumberedObservations")
end

@testset "a planned transfer out of a well with no usable cache is applied once (ancestor bootstrap)" begin
    # the source is observed (observations write no cache) before the sink is created, so the sink's cache is newer than
    # anything of the source and the source is rebuilt as an ancestor
    w = eo_bottle("eo uncached source")
    observe(w,rgt"glycerol",100u"mL")
    sink = eo_bottle("eo late sink")
    encumber(eo_protocol("eo late draw"),transfer!,w,sink,60u"mL")
    @test quantity(eo_contents(sink;encumbrances=true)) ≈ 60u"mL"
    @test quantity(eo_contents(w;encumbrances=true)) ≈ 40u"mL"
end
