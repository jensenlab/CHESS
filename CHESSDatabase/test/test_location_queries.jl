# Bulk location queries. Every location is new (prefixed `lq`).

lq_room = generate_location(Room,"lq room")
lq_bench = generate_location(Bench,"lq bench")
lq_b1 = generate_location(Bottle1L,"lq bottle 1")
lq_b2 = generate_location(Bottle1L,"LQ Bottle 2")
lq_plate = generate_location(WP96,"lq plate")
upload(move_into!,lq_room,lq_bench)
upload(move_into!,lq_bench,lq_b1)
lq_mv = upload(move_into!,lq_bench,lq_b2)
upload(move_into!,lq_bench,lq_plate)
lq_bc = Barcode(string(UUIDs.uuid4()),"lq barcode")
upload_barcode(lq_bc)
upload(assign_barcode!,lq_bc,lq_b1)

lq_ids(df) = Set(df.ID)

@testset "find_locations: filters" begin
    @test lq_ids(find_locations(name="lq bench")) == Set([location_id(lq_bench)])
    @test isempty(find_locations(name="LQ BENCH"))
    @test lq_ids(find_locations(name="LQ BENCH",ignorecase=true)) == Set([location_id(lq_bench)])
    kids = find_locations(parent=location_id(lq_bench))
    @test lq_ids(kids) == Set(location_id.([lq_b1,lq_b2,lq_plate]))
    @test all(kids.Kind .!= "")
    @test lq_ids(find_locations(parent=location_id(lq_bench),kind=:Bottle1L)) == Set(location_id.([lq_b1,lq_b2]))
    @test lq_ids(find_locations(barcode=barcode(lq_bc))) == Set([location_id(lq_b1)])
    @test location_id(lq_room) in find_locations(parent=nothing,kind=:Room).ID
    # wells are the children of their labware
    @test nrow(find_locations(parent=location_id(lq_plate))) == 96
    @test lq_ids(find_locations(parent=location_id(lq_plate),limit=5)) |> length == 5
    page1 = find_locations(parent=location_id(lq_plate),limit=40)
    page2 = find_locations(parent=location_id(lq_plate),limit=40,offset=40)
    @test isempty(intersect(page1.ID,page2.ID))
end

@testset "find_locations: as of a sequence, and activity" begin
    seq = get_sequence_id(lq_mv)
    @test !(location_id(lq_b2) in find_locations(parent=location_id(lq_bench),sequence_id=seq-1).ID)
    @test location_id(lq_b2) in find_locations(parent=location_id(lq_bench),sequence_id=seq).ID
    @test location_id(lq_b2) in find_locations(parent=nothing,sequence_id=seq-1).ID
    upload(deactivate!,lq_b2)
    @test !(location_id(lq_b2) in find_locations(active=true,parent=location_id(lq_bench)).ID)
    @test location_id(lq_b2) in find_locations(active=false,parent=location_id(lq_bench)).ID
    # a removal takes it out of the bench
    upload(remove_from_parent!,lq_b2)
    @test !(location_id(lq_b2) in find_locations(parent=location_id(lq_bench)).ID)
    # amending a move changes the answer
    update(move_into!,lq_room,lq_b2;replace=get_sequence_id(lq_mv))
    @test find_locations(name="LQ Bottle 2",sequence_id=get_sequence_id(lq_mv)).ParentID[1] == location_id(lq_room)
end

@testset "descendants" begin
    d = descendants(location_id(lq_room))
    @test Set(d[d.Depth .== 1,:ID]) == Set([location_id(lq_bench)])
    @test Set(d[d.Depth .== 2,:ID]) == Set(location_id.([lq_b1,lq_plate]))
    @test location_id(lq_plate[2,3]) in d[d.Depth .== 3,:ID]
    @test nrow(descendants(location_id(lq_room);max_depth=1)) == 1
    @test lq_ids(descendants(location_id(lq_room);kinds=[:Bottle1L])) == Set([location_id(lq_b1)])
    @test isempty(descendants(location_id(lq_b1[1,1])))
end

@testset "reconstruct_locations equals one-by-one reconstruction" begin
    ids = location_id.([lq_bench,lq_b1,lq_plate])
    locs = reconstruct_locations(ids)
    @test location_id.(locs) == ids
    @test name.(locs) == name.(reconstruct_location.(ids))
end
