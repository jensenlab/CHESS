# Observations: declaring state in the ledger without a history for it. Runs against the shared
# database/connection build_test_database.jl set up; every location here is new (prefixed `ob_`).

ob_contents(id) = stock(reconstruct_contents(id))
ob_solid(id,r) = get(solids(ob_contents(id)),r,0u"g")
ob_liquid(id,r) = get(liquids(ob_contents(id)),r,0u"mL")
ob_drop_content_caches(id) = execute_db("DELETE FROM CachedContents WHERE LocationID = ?",(id,))

ob_room = generate_location(Room,"ob room")

@testset "observe: a bottle appears out of thin air" begin
    bottle = generate_location(Bottle1L,"ob new bottle")
    w = bottle[1,1]
    observe(w,rgt"water",500u"mL")
    observe(w,:cost,12.0)
    @test stock(w) == 500u"mL"*rgt"water" # updated in memory too
    ob_drop_content_caches(location_id(w)) # the ledger alone holds it
    @test ob_contents(location_id(w)) == 500u"mL"*rgt"water"
    @test cost(reconstruct_contents(location_id(w))) == 12.0
end

@testset "commit_location! records starting state as observations" begin
    eph = build_location(Bottle1L,"ob committed bottle")
    deposit!(eph[1,1],100u"mL"*rgt"water"+2.35u"g"*rgt"paba",3)
    before = get_last_sequence_id()
    bottle = commit_location!(eph)
    @test get_last_sequence_id() == before + 1 # one ledger entry for the whole commit
    w_id = location_id(bottle[1,1])
    ob_drop_content_caches(w_id)
    @test ob_contents(w_id) == 100u"mL"*rgt"water"+2.35u"g"*rgt"paba"
    @test cost(reconstruct_contents(w_id)) == 3

    # a location committed with nothing in it needs no ledger entry
    before = get_last_sequence_id()
    commit_location!(build_location(WP96,"ob empty committed plate"))
    @test get_last_sequence_id() == before
end

# the worked example: W holds 100 mL water + 2.35 g paba, glucose-like solid is found at 2.04 g,
# then 10 mL goes to B
ob_src = commit_location!(build_location(Bottle1L,"ob upstream bottle"))
observe(ob_src[1,1],rgt"water",500u"mL")
observe(ob_src[1,1],rgt"paba",11.75u"g")
ob_w = generate_location(Bottle1L,"ob observed bottle")[1,1]
ob_b = generate_location(Bottle1L,"ob downstream bottle")[1,1]
ob_upstream_ledger = upload(transfer!,ob_src[1,1],ob_w,100u"mL") # brings 2.35 g paba
ob_obs_ledger = observe(ob_w,rgt"paba",2.04u"g")
upload(transfer!,ob_w,ob_b,10u"mL")

@testset "a single-component observation pins only that component" begin
    w_id, b_id = location_id(ob_w), location_id(ob_b)
    @test ob_liquid(w_id,rgt"water") ≈ 90u"mL"
    @test ob_solid(w_id,rgt"paba") ≈ 1.836u"g"
    @test ob_liquid(b_id,rgt"water") ≈ 10u"mL"
    @test ob_solid(b_id,rgt"paba") ≈ 0.204u"g" # from the observed value, not the predicted one

    # just before the observation, history's prediction still stands
    before_obs = stock(reconstruct_contents(w_id,get_sequence_id(ob_obs_ledger)-1))
    @test solids(before_obs)[rgt"paba"] ≈ 2.35u"g"
end

@testset "observation_discrepancies reports predicted vs observed" begin
    d = observation_discrepancies(location_id(ob_w))
    row = only(eachrow(filter(r -> r.Facet == "component",d)))
    @test row.LedgerID == ob_obs_ledger
    @test row.Key == rgt"paba"
    @test row.Predicted ≈ 2.35u"g"
    @test row.Observed ≈ 2.04u"g"
end

@testset "editing history before an observation leaves the observed facet alone" begin
    w_id = location_id(ob_w)
    cache(reconstruct_location(w_id)) # a cache after the edit point, which repair has to fix
    src = reconstruct_location(location_id(ob_src[1,1]),get_sequence_id(ob_upstream_ledger)-1)
    w = reconstruct_location(w_id,get_sequence_id(ob_upstream_ledger)-1)
    update(transfer!,src,w,200u"mL";ledger_id=replace_ledger(get_sequence_id(ob_upstream_ledger)))
    @test ob_liquid(w_id,rgt"water") ≈ 190u"mL"  # unobserved: follows the corrected history
    @test ob_solid(w_id,rgt"paba") ≈ 2.04u"g"*190/200 # observed: still 2.04 g at the observation
end

@testset "an observation inserted into the past is validated and repairs later caches" begin
    bottle = generate_location(Bottle1L,"ob inserted bottle")
    w = bottle[1,1]
    observe(w,rgt"water",100u"mL")
    dest = generate_location(Bottle1L,"ob inserted dest")[1,1]
    t_ledger = upload(transfer!,w,dest,50u"mL")
    cache(reconstruct_location(location_id(w)))
    @test ob_liquid(location_id(w),rgt"water") ≈ 50u"mL"

    # it turns out the bottle only ever had 80 mL before that transfer
    observe(reconstruct_location(location_id(w),get_sequence_id(t_ledger)-1),rgt"water",80u"mL";
        ledger_id=insert_ledger(get_sequence_id(t_ledger)))
    @test ob_liquid(location_id(w),rgt"water") ≈ 30u"mL" # the later cache was repaired

    # an observation that makes a later operation impossible is rejected
    @test_throws Exception observe(reconstruct_location(location_id(w),get_sequence_id(t_ledger)-1),rgt"water",10u"mL";
        ledger_id=insert_ledger(get_sequence_id(t_ledger)))
end

@testset "attribute observations: own vs confirmed inherited" begin
    room = generate_location(Room,"ob attr room")
    bench = generate_location(Bench,"ob attr bench")
    upload(move_into!,room,bench)
    upload(set_attribute!,room,Temperature(37u"°C"))

    # matches what the bench inherits, so it stays unpinned and keeps following the room
    observe(bench,Temperature(37u"°C"))
    @test !haskey(attributes(bench),:Temperature)
    upload(set_attribute!,room,Temperature(30u"°C"))
    @test environment(reconstruct_environment(location_id(bench)))[:Temperature] == Temperature(30u"°C")

    # differs, so the bench gets its own value
    observe(bench,Temperature(25u"°C"))
    upload(set_attribute!,room,Temperature(20u"°C"))
    @test environment(reconstruct_environment(location_id(bench)))[:Temperature] == Temperature(25u"°C")

    d = observation_discrepancies(location_id(bench))
    @test nrow(d) == 1 && d[1,:Observed] == Temperature(25u"°C") && d[1,:Predicted] == Temperature(30u"°C")
end

@testset "position, lock and activity observations" begin
    room1 = generate_location(Room,"ob room 1")
    room2 = generate_location(Room,"ob room 2")
    bench = generate_location(Bench,"ob moved bench")
    upload(move_into!,room1,bench)
    upload(lock!,bench)

    observe(bench,room2) # found somewhere else, lock notwithstanding
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(bench)))) == location_id(room2)
    @test isempty(children(reconstruct_children(location_id(room1))))
    @test location_id.(children(reconstruct_children(location_id(room2)))) == [location_id(bench)]

    observe(bench,:locked,false)
    observe(bench,:active,false)
    @test !is_locked(reconstruct_lock(location_id(bench)))
    @test !is_active(reconstruct_activity(location_id(bench)))
end

@testset "observe(loc) declares a whole location" begin
    plate = generate_location(WP96,"ob full plate")
    upload(move_into!,ob_room,plate)
    observe(plate[1,1],rgt"water",100u"µL")
    observe(plate[1,1],rgt"paba",1u"mg")

    # in memory: A1 lost its paba, A2 gained water; observe the plate as it is now
    p = reconstruct_location(location_id(plate))
    a1 = reconstruct_location(location_id(plate[1,1]))
    a2 = reconstruct_location(location_id(plate[1,2]))
    a1.stock = 100u"µL"*rgt"water"
    a2.stock = 20u"µL"*rgt"water"
    p.children[1,1] = a1; a1.parent = p
    p.children[1,2] = a2; a2.parent = p
    before = get_last_sequence_id()
    observe(p)
    @test get_last_sequence_id() == before + 1
    @test ob_liquid(location_id(a1),rgt"water") ≈ 100u"µL"
    @test isempty(solids(ob_contents(location_id(a1)))) # the predicted paba was declared absent
    @test ob_liquid(location_id(a2),rgt"water") ≈ 20u"µL"
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(plate)))) == location_id(ob_room)
end

@testset "observations can link to the Read that produced them" begin
    bottle = generate_location(Bottle1L,"ob read bottle")
    w = bottle[1,1]
    read_ledger = upload(record_read!,w,Absorbance(50u"percent",Dates.now()))
    obs_ledger = observe(w,rgt"water",1u"mL";read_ledger_id=read_ledger)
    row = query_db("SELECT ReadLedgerID FROM ObservedComponents WHERE LedgerID = ?",(obs_ledger,))
    @test row[1,1] == read_ledger
end

@testset "backfill_observations turns cache-only state into observations" begin
    # the pre-observation way to seed a bottle: change it in memory, then cache it
    bottle = generate_location(Bottle1L,"ob legacy bottle")
    w = bottle[1,1]
    deposit!(w,250u"mL"*rgt"water",4)
    cache(w)
    dest = generate_location(Bottle1L,"ob legacy dest")[1,1]
    upload(transfer!,w,dest,50u"mL")

    # before the backfill only the cache knows about the water
    @test ob_contents(location_id(w)) == 200u"mL"*rgt"water"
    @test nrow(query_db("SELECT 1 FROM ObservedComponents WHERE LocationID = ?",(location_id(w),))) == 0

    @test backfill_observations() >= 1
    @test backfill_observations() == 0 # idempotent: nothing left unexplained
    ob_drop_content_caches(location_id(w))
    ob_drop_content_caches(location_id(dest))
    @test ob_contents(location_id(w)) == 200u"mL"*rgt"water"
    @test ob_contents(location_id(dest)) == 50u"mL"*rgt"water"
    @test cost(reconstruct_contents(location_id(w))) ≈ 3.2
end
