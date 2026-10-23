# Regression tests for the small fixes made before the reconstruction-at-scale work (plan phase 0).
# Each testset fails on the code as it was before its fix.

@testset "phase 0: reconstruct_parent! on a single location" begin
    # the single-location method called a misspelled `reconstrut_parent`
    with_scratch_db() do _
        room = generate_location(Room,"p0 room")
        plate = generate_location(WP96,"p0 plate")
        upload(move_into!,room,plate)
        n,t = CHESSDatabase.get_location_info(location_id(plate))
        bare = t(location_id(plate),n)
        @test CHESSCore.parent(bare) === nothing
        reconstruct_parent!(bare)
        @test location_id(CHESSCore.parent(bare)) == location_id(room)
    end
end

@testset "phase 0: reconstruct_attributes! on a single location" begin
    # the single-location method called a misspelled `locaton_id`
    with_scratch_db() do _
        room = generate_location(Room,"p0 room")
        upload(set_attribute!,room,Temperature(21u"°C"))
        n,t = CHESSDatabase.get_location_info(location_id(room))
        bare = t(location_id(room),n)
        reconstruct_attributes!(bare)
        @test CHESSCore.attributes(bare)[:Temperature] == Temperature(21u"°C")
    end
end

@testset "phase 0: cache_children_helper(()) uses the real column name" begin
    # the INSERT into CachedChildren named a column `CachedhildSetID`. The statement sits inside a loop over
    # the (empty) tuple, so it never ran; check the source text as well as the call.
    with_scratch_db() do _
        id = CHESSDatabase.cache_children_helper(())
        @test id isa Integer
        @test CHESSDatabase.cache_children_helper(()) == id # second call finds the same child set
    end
    @test !occursin("CachedhildSetID",read(joinpath(pkgdir(CHESSDatabase),"src","caching.jl"),String))
end

@testset "phase 0: get_child_movements honours its time argument" begin
    with_scratch_db() do _
        room = generate_location(Room,"p0 room")
        shelf = generate_location(IncubatorShelf,"p0 shelf")
        inc = generate_location(Incubator,"p0 incubator")
        upload(move_into!,room,inc)
        sleep(0.02)
        lid = upload(move_into!,inc,shelf)
        t_move = CHESSDatabase.get_ledger_time(lid)
        last_seq = get_last_sequence_id()
        before = t_move - Dates.Millisecond(1)

        # as parent: the movement of `shelf` into `inc`
        none = CHESSDatabase.get_child_movements([location_id(inc)],Dict{Integer,Integer}(),0,last_seq,before)
        @test nrow(none) == 0
        one = CHESSDatabase.get_child_movements([location_id(inc)],Dict{Integer,Integer}(),0,last_seq,t_move)
        @test nrow(one) == 1
        # as child: `shelf` is a known current child of `inc`; before the move it had no movement
        none = CHESSDatabase.get_child_movements(Int[],Dict{Integer,Integer}(location_id(shelf)=>location_id(inc)),0,last_seq,before)
        @test nrow(none) == 0
        one = CHESSDatabase.get_child_movements(Int[],Dict{Integer,Integer}(location_id(shelf)=>location_id(inc)),0,last_seq,t_move)
        @test nrow(one) == 1
    end
end

@testset "phase 0: validate_transfer reconstructs the destination" begin
    with_scratch_db() do _
        room = generate_location(Room,"p0 room")
        bottle = generate_location(Bottle1L,"p0 bottle")
        other = generate_location(Bottle1L,"p0 other bottle")
        plate = generate_location(WP96,"p0 plate")
        for l in (bottle,other,plate)
            upload(move_into!,room,l)
        end
        src,other_src,dest = bottle[1,1],other[1,1],plate[1,1]
        deposit!(src,500u"mL"*rgt"water"); cache(src)
        deposit!(other_src,500u"mL"*rgt"water"); cache(other_src)
        lid = upload(transfer!,src,dest,50u"µL")
        @test CHESSDatabase.validate(lid) === nothing # healthy ledger

        # A later transfer into `dest` that overfills it (200 µL wells). The closure of `src` does not
        # contain it, so only a reconstruction of the destination notices.
        seq = get_last_sequence_id()+1
        bad = CHESSDatabase.update_ledger(seq)
        execute_db("INSERT INTO Transfers(LedgerID,Source,Destination,Quantity,Unit,Time) Values(?,?,?,?,?,?)",
            (bad,location_id(other_src),location_id(dest),1000.0,"µL",db_time(Dates.now())))
        @test_throws Exception reconstruct_contents(location_id(dest))
        @test_throws Exception CHESSDatabase.validate(lid)
    end
end
