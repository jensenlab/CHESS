# Ledgered discard and remove-from-parent. Every location is new (prefixed `dc`).

dc_stock(w) = stock(reconstruct_contents(location_id(w)))
dc_water(w) = liquids(dc_stock(w))[rgt"water"]

@testset "discard!: in-memory operation" begin
    w = Well(nothing,"dc mem",Well1000000;stock=100u"mL"*rgt"water"+2u"g"*rgt"paba")
    discard!(w,25u"mL")
    @test liquids(stock(w))[rgt"water"] ≈ 75u"mL"
    @test_throws MixingError discard!(w,500u"mL")
end

dc_src = commit_location!(build_location(Bottle1L,"dc src"))
dc_dest = generate_location(Bottle1L,"dc dest")[1,1]
observe(dc_src[1,1],rgt"water",500u"mL")
dc_l1 = upload(discard!,dc_src[1,1],100u"mL")
dc_l2 = upload(transfer!,dc_src[1,1],dc_dest,100u"mL")

@testset "discard!: ledgered, replayed, and traced" begin
    @test dc_water(dc_src[1,1]) ≈ 300u"mL"
    @test dc_water(dc_dest) ≈ 100u"mL"
    seq1 = get_sequence_id(dc_l1)
    @test liquids(stock(reconstruct_contents(location_id(dc_src[1,1]),seq1-1)))[rgt"water"] ≈ 500u"mL"
    execute_db("DELETE FROM CachedContents WHERE LocationID = ?",(location_id(dc_src[1,1]),))
    @test dc_water(dc_src[1,1]) ≈ 300u"mL"
    observe(dc_src,Lot("DC Supplier","DC-1","DC-LOT"))
    tr = trace_contents(location_id(dc_dest))
    @test all(r->!ismissing(r.Lot) && r.Lot.lot=="DC-LOT",eachrow(tr))
end

@testset "discard!: refused when the well holds less" begin
    n = nrow(query_db("SELECT 1 FROM Discards"))
    @test_throws Exception upload(discard!,dc_src[1,1],5u"L")
    @test nrow(query_db("SELECT 1 FROM Discards")) == n
    @test dc_water(dc_src[1,1]) ≈ 300u"mL"
end

@testset "discard!: amending the ledger" begin
    seq1 = get_sequence_id(dc_l1)
    before_time = Dates.now(); sleep(0.05)
    before_seq = get_last_sequence_id()
    update(discard!,dc_src[1,1],50u"mL";replace=seq1)
    @test dc_water(dc_src[1,1]) ≈ 350u"mL"
    @test liquids(stock(reconstruct_contents(location_id(dc_src[1,1]),before_seq,before_time)))[rgt"water"] ≈ 300u"mL"
    @test_throws Exception update(transfer!,dc_src[1,1],dc_dest,1u"mL";replace=seq1)
    @test dc_water(dc_src[1,1]) ≈ 350u"mL"
    @test_throws Exception update(discard!,dc_src[1,1],450u"mL";replace=seq1)
    @test dc_water(dc_src[1,1]) ≈ 350u"mL"
    update(discard!,dc_src[1,1],50u"mL";insert=get_sequence_id(dc_l2))
    @test dc_water(dc_src[1,1]) ≈ 300u"mL"
    cached = dc_stock(dc_src[1,1])
    execute_db("DELETE FROM CachedContents WHERE LocationID = ?",(location_id(dc_src[1,1]),))
    @test dc_stock(dc_src[1,1]) == cached
end

@testset "remove_from_parent!: in-memory operation" begin
    room = build_location(Room,"dc mem room")
    b = build_location(Bottle1L,"dc mem bottle")
    move_into!(room,b)
    remove_from_parent!(b)
    @test isnothing(CHESSCore.parent(b))
    @test !(b in children(room))
    @test_throws ArgumentError remove_from_parent!(b)
    move_into!(room,b)
    lock!(b)
    @test_throws LockedLocationError remove_from_parent!(b)
    @test_throws FixedMembershipError remove_from_parent!(b[1,1])
end

dc_room = generate_location(Room,"dc room")
dc_shelf = generate_location(Room,"dc shelf")
dc_bottle = generate_location(Bottle1L,"dc bottle")
upload(move_into!,dc_room,dc_bottle)
dc_m2 = upload(remove_from_parent!,dc_bottle)

@testset "remove_from_parent!: ledgered and reconstructed" begin
    @test isnothing(CHESSCore.parent(reconstruct_parent(location_id(dc_bottle))))
    @test !(location_id(dc_bottle) in location_id.(children(reconstruct_children(location_id(dc_room)))))
    seq = get_sequence_id(dc_m2)
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(dc_bottle),seq-1))) == location_id(dc_room)
    @test isnothing(CHESSCore.parent(reconstruct_location(location_id(dc_bottle))))
    upload(move_into!,dc_shelf,dc_bottle)
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(dc_bottle)))) == location_id(dc_shelf)
end

@testset "remove_from_parent!: amending the ledger" begin
    b2 = generate_location(Bottle1L,"dc bottle 2")
    upload(move_into!,dc_room,b2)
    rm_l = upload(remove_from_parent!,b2)
    cache(dc_room); cache(b2)
    update(move_into!,dc_room,b2;replace=get_sequence_id(rm_l))
    @test location_id(CHESSCore.parent(reconstruct_parent(location_id(b2)))) == location_id(dc_room)
    @test location_id(b2) in location_id.(children(reconstruct_children(location_id(dc_room))))
end
