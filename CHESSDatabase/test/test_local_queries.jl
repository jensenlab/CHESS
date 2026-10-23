# The filter-by-key-first lookups (src/reconstruction/local_queries.jl): their fallbacks, and the one place
# where they define what the original left to SQLite.

@testset "local lookups: ties inside one ledger entry are resolved by insertion order" begin
    # The original picked an arbitrary row when one ledger entry held several events for one key. The
    # lookups now take the operation table before its observation table, and the lowest row ID within a table.
    with_scratch_db() do _
        room_a,room_b,room_c = (generate_location(Room,"tie room $i") for i in 1:3)
        plate = generate_location(WP96,"tie plate")
        tick = append_ledger()
        execute_db("INSERT INTO ObservedParents(LedgerID,Parent,Child,Time) Values(?,?,?,?)",(tick,location_id(room_c),location_id(plate),db_time(Dates.now())))
        for room in (room_a,room_b)
            execute_db("INSERT INTO Movements(LedgerID,Parent,Child,Time) Values(?,?,?,?)",(tick,location_id(room),location_id(plate),db_time(Dates.now())))
        end
        execute_db("INSERT INTO Locks(LedgerID,LocationID,IsLocked,Time) Values(?,?,?,?)",(tick,location_id(plate),1,db_time(Dates.now())))
        execute_db("INSERT INTO Locks(LedgerID,LocationID,IsLocked,Time) Values(?,?,?,?)",(tick,location_id(plate),0,db_time(Dates.now())))
        mv = CHESSDatabase.get_last_movement_as_child([location_id(plate)])
        @test nrow(mv) == 1 && mv.Parent[1] == location_id(room_a)           # first Movements row
        @test CHESSDatabase.get_locks([location_id(plate)]).IsLocked == [1]  # first Locks row
        # the original returns one of the candidates, whichever SQLite meets
        old = Legacy.get_last_movement_as_child([location_id(plate)])
        @test nrow(old) == 1 && old.Parent[1] in location_id.([room_a,room_b,room_c])
        # a child counts as being in a parent only through its latest movement
        @test location_id(plate) in CHESSDatabase.get_last_movements_as_parent([location_id(room_a)]).Child
        @test isempty(CHESSDatabase.get_last_movements_as_parent([location_id(room_b)]).Child)
    end
end

@testset "local lookups: legacy mode, many keys and encumbrances use the original queries" begin
    with_scratch_db() do _
        eqv_generate(5;nops=80)
        ids = query_db("SELECT DISTINCT LocationID FROM Locks UNION SELECT DISTINCT LocationID FROM Activity").LocationID
        seq = get_last_sequence_id(); t = Dates.now()
        local_result = (CHESSDatabase.get_locks(ids,0,seq,t),CHESSDatabase.get_activity(ids,0,seq,t),CHESSDatabase.get_parent_caches(ids[1],0,seq,t),
            CHESSDatabase.get_instrument_settings(first(ids),seq,t),CHESSDatabase.find_locations(;kind=:WP96,sequence_id=seq,time=t))
        old_mode = CHESSDatabase.reconstruction_mode[]
        old_limit = CHESSDatabase.LOCAL_KEY_LIMIT[]
        try
            CHESSDatabase.reconstruction_mode[] = :legacy
            legacy_result = (CHESSDatabase.get_locks(ids,0,seq,t),CHESSDatabase.get_activity(ids,0,seq,t),CHESSDatabase.get_parent_caches(ids[1],0,seq,t),
                CHESSDatabase.get_instrument_settings(first(ids),seq,t),CHESSDatabase.find_locations(;kind=:WP96,sequence_id=seq,time=t))
            CHESSDatabase.reconstruction_mode[] = :local
            CHESSDatabase.LOCAL_KEY_LIMIT[] = 0
            many_result = (CHESSDatabase.get_locks(ids,0,seq,t),CHESSDatabase.get_activity(ids,0,seq,t))
            for (a,b) in zip(local_result,legacy_result)
                @test eqv_canon(a) == eqv_canon(b)
            end
            @test eqv_canon(many_result[1]) == eqv_canon(local_result[1]) && eqv_canon(many_result[2]) == eqv_canon(local_result[2])
        finally
            CHESSDatabase.reconstruction_mode[] = old_mode
            CHESSDatabase.LOCAL_KEY_LIMIT[] = old_limit
        end
        @test_throws Exception withenv("CHESS_RECONSTRUCTION"=>"nonsense") do; CHESSDatabase.__init__(); end
        CHESSDatabase.reconstruction_mode[] = old_mode
    end
end
