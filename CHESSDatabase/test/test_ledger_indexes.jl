# Indexes (src/indexes.jl), the visibility helpers (src/reconstruction/visibility.jl) and the ledger
# allocation rules (src/ledger.jl): atomic slot allocation, monotone ledger clock.

_chess_index_names() = String.(query_db("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx\\_chess\\_%' ESCAPE '\\'").name)
_plan(sql,params=()) = join(query_db("EXPLAIN QUERY PLAN " * sql,params).detail,"; ")

@testset "indexes: create_db, create_indexes!, drop_indexes!" begin
    with_scratch_db() do path
        names = _chess_index_names()
        @test "idx_chess_ledger_sequenceid_id_time" in names
        @test "idx_chess_transfers_source_ledgerid" in names
        @test "idx_chess_environmentattributes_locationid_attribute_ledgerid" in names
        @test length(names) == length(unique(names)) > 30
        @test isempty(create_indexes!(progress=false)) # nothing missing in a new database

        # an index made by another tool with the same leading columns counts: no duplicate is created
        execute_db("CREATE INDEX idx_perf_transfers_dest ON Transfers(Destination, LedgerID, Quantity)")
        dropped = drop_indexes!()
        @test Set(dropped) == Set(names)
        @test isempty(_chess_index_names())
        @test nrow(query_db("SELECT 1 FROM sqlite_master WHERE name='idx_perf_transfers_dest'")) == 1 # not touched
        created = create_indexes!(progress=false)
        @test Set(created) == setdiff(Set(names),Set(["idx_chess_transfers_destination_ledgerid"]))
        @test !("idx_chess_transfers_destination_ledgerid" in _chess_index_names())

        # a table the database lacks is skipped
        drop_indexes!()
        execute_db("DROP TABLE EncumberedCachedLockActivity")
        created = create_indexes!(progress=false)
        @test !any(occursin("encumberedcachedlockactivity",n) for n in created)
        @test length(created) == length(names) - 2 # also the Transfers one covered by idx_perf_*; and this table
    end
end

@testset "indexes: connect_SQLite builds them on a database of any size, with a warning" begin
    with_scratch_db() do path
        drop_indexes!()
        @test_logs (:warn,r"missing .* CHESS indexes") connect_SQLite(path)
        @test "idx_chess_ledger_sequenceid_id_time" in _chess_index_names() # created on connect
        @test_logs connect_SQLite(path) # nothing missing: silent

        # a database past the old 1,000,000-row limit (the largest ledger ID is what counts)
        execute_db("INSERT INTO Ledger(ID,SequenceID,Time) VALUES (2000000,1999999,1)")
        drop_indexes!()
        @test isempty(_chess_index_names())
        @test_logs (:warn,r"has 2000000 ledger rows and was missing .* CHESS indexes") connect_SQLite(path)
        @test length(_chess_index_names()) > 30
        @test isempty(create_indexes!(progress=false)) # nothing left for the explicit call
        execute_db("DELETE FROM Ledger WHERE ID = 2000000")
    end
end

@testset "indexes: a database made before the Ledger index carried Time gets the covering index" begin
    with_scratch_db() do _
        drop_indexes!()
        execute_db("CREATE INDEX idx_chess_ledger_sequenceid_id ON Ledger(SequenceID, ID)")
        @test "idx_chess_ledger_sequenceid_id_time" in create_indexes!(progress=false)
        names_now = _chess_index_names()
        @test "idx_chess_ledger_sequenceid_id_time" in names_now && !("idx_chess_ledger_sequenceid_id" in names_now)
        @test isempty(create_indexes!(progress=false))
    end
end

@testset "ledger helpers use Ledger(SequenceID, ID)" begin
    with_scratch_db() do _
        room = generate_location(Room,"idx room")
        for t in 1:5
            upload(set_attribute!,room,Temperature((20+t)*u"°C"))
        end
        last_seq = get_last_sequence_id()
        @test _plan("SELECT SequenceID FROM Ledger WHERE Time <= ? ORDER BY SequenceID DESC LIMIT 1",(1e12,)) ==
            "SCAN Ledger USING COVERING INDEX idx_chess_ledger_sequenceid_id_time"
        @test occursin(r"INDEX idx_chess_ledger_sequenceid_id",_plan("SELECT ID FROM Ledger WHERE SequenceID = ? AND Time <= ? ORDER BY ID DESC LIMIT 1",(3,1e12)))
        @test occursin(r"INDEX idx_chess_ledger_sequenceid_id",_plan("SELECT 1 FROM Ledger WHERE SequenceID = ? LIMIT 1",(3,)))

        # results equal the definitions in terms of the whole table
        @test last_seq == query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
        @test get_last_ledger_id() == query_db("SELECT Max(ID) FROM Ledger")[1,1]
        @test CHESSDatabase.get_all_ledger_ids(last_seq) == [get_last_ledger_id()]
        # before the first row was written there is nothing
        before = Dates.now() - Dates.Year(1)
        @test ismissing(get_last_sequence_id(before))
        @test ismissing(get_last_ledger_id(before))
    end
end

@testset "visibility: visible_ledger_id, is_visible and visible_join agree with ledger_subset" begin
    with_scratch_db() do _
        room = generate_location(Room,"vis room")
        for t in 1:6
            upload(set_attribute!,room,Temperature((20+t)*u"°C"))
            sleep(0.003)
        end
        marks = Dates.DateTime[]
        slots = [get_sequence_id(id) for id in query_db("SELECT LedgerID FROM EnvironmentAttributes ORDER BY ID").LedgerID]
        for s in (slots[2],slots[4],slots[2],slots[2])  # amendments of two slots, one of them three times
            sleep(0.003)
            push!(marks,Dates.now())
            sleep(0.003)
            update(set_attribute!,room,Temperature(40u"°C");replace=s)
        end
        times = vcat(Dates.now()+Dates.Second(1),marks,Dates.now()-Dates.Year(1))
        last_seq = get_last_sequence_id()
        for t in times
            lt = db_time(t)
            # the definition: Max(ID) per slot among rows written by `t` (what ledger_subset computes)
            subset = query_db("SELECT Max(ID) AS ID, SequenceID FROM Ledger WHERE Time <= ? GROUP BY SequenceID",(lt,))
            expected = Dict(r.SequenceID => r.ID for r in eachrow(subset))
            for slot in 0:last_seq+1
                @test isequal(CHESSDatabase.visible_ledger_id(slot,t),get(expected,slot,missing))
            end
            for id in query_db("SELECT ID FROM Ledger").ID
                from,to = 2,last_seq-1
                seq = get_sequence_id(id)
                @test CHESSDatabase.is_visible(id,from,to,t) == (id in values(expected) && from <= seq <= to)
            end
            # visible_join over an operation table returns exactly the attribute rows whose ledger row is current
            joined = query_db("SELECT e.ID FROM EnvironmentAttributes e " * CHESSDatabase.visible_join("e";from="2",to="$(last_seq-1)",t="$lt") * " ORDER BY e.ID")
            direct = query_db("""SELECT e.ID FROM EnvironmentAttributes e WHERE e.LedgerID IN
                (SELECT Max(ID) FROM Ledger WHERE Time <= $lt AND SequenceID BETWEEN 2 AND $(last_seq-1) GROUP BY SequenceID) ORDER BY e.ID""")
            @test joined.ID == direct.ID
        end
        # named placeholders work too
        sql = "SELECT e.ID FROM EnvironmentAttributes e " * CHESSDatabase.visible_join("e") * " ORDER BY e.ID"
        named = query_db(sql,(from=1,to=last_seq,t=db_time(Dates.now()+Dates.Second(1))))
        @test nrow(named) == nrow(query_db("SELECT e.ID FROM EnvironmentAttributes e " *
            CHESSDatabase.visible_join("e";from="1",to="$last_seq",t="$(db_time(Dates.now()+Dates.Second(1)))")))
        @test get_last_ledger_id(slots[2],marks[2]) == CHESSDatabase.visible_ledger_id(slots[2],marks[2])
    end
end

@testset "ledger: slot allocation is one statement, ledger time never goes backward" begin
    with_scratch_db() do _
        a = append_ledger(); b = append_ledger()
        @test get_sequence_id(b) == get_sequence_id(a) + 1
        # a failed operation leaves no ledger row behind (upload allocates inside its transaction)
        room = generate_location(Room,"clock room")
        plate = generate_location(WP96,"clock plate")
        n = query_db("SELECT COUNT(*) FROM Ledger")[1,1]
        @test_throws Exception upload(transfer!,plate[1,1],plate[1,2],1u"µL") # the well is empty: fails after the slot was allocated
        @test query_db("SELECT COUNT(*) FROM Ledger")[1,1] == n
        # upload with an explicit ledger_id no longer appends an unused extra row
        n = query_db("SELECT COUNT(*) FROM Ledger")[1,1]
        lid = append_ledger()
        upload(set_attribute!,room,Temperature(20u"°C");ledger_id=lid)
        @test query_db("SELECT COUNT(*) FROM Ledger")[1,1] == n + 1

        # the clock stepped back: a row written later never gets an earlier time than the newest row
        future = db_time(Dates.now() + Dates.Hour(2))
        execute_db("UPDATE Ledger SET Time = ? WHERE ID = (SELECT Max(ID) FROM Ledger)",(future,))
        c = append_ledger(); d = CHESSDatabase.update_ledger(get_sequence_id(c))  # an append and a replacement
        @test query_db("SELECT Time FROM Ledger WHERE ID = ?",(c,))[1,1] == future
        @test query_db("SELECT Time FROM Ledger WHERE ID = ?",(d,))[1,1] == future
        times = query_db("SELECT Time FROM Ledger ORDER BY ID").Time
        @test issorted(times)
        # insert_ledger shifts later slots and its row is timed the same way
        e = insert_ledger(2)
        @test get_sequence_id(e) == 2
        @test issorted(query_db("SELECT Time FROM Ledger ORDER BY ID").Time)
        # all slots are still consecutive
        seqs = sort(unique(query_db("SELECT SequenceID FROM Ledger").SequenceID))
        @test seqs == collect(1:length(seqs))
    end
end

@testset "ledger: two writer processes never share a sequence ID" begin
    mktempdir() do dir
        path = joinpath(dir,"two_writers.db")
        room_id = with_scratch_db(path=path,keep=true) do _
            room = generate_location(Room,"two writer room")
            location_id(room)
        end
        script = joinpath(dir,"writer.jl")
        write(script,"""
            using CHESSCore, CHESSDatabase, Unitful
            path, room_id, n, tag = ARGS[1], parse(Int,ARGS[2]), parse(Int,ARGS[3]), ARGS[4]
            @attribute Temperature u"°C"
            @location_kind Room Symbol[] nothing nothing nothing nothing nothing 0//1 0//1
            connect_SQLite(path)
            room = reconstruct_location(room_id)
            for i in 1:n
                upload(set_attribute!,room,Temperature((i + (tag == "b" ? 100 : 0))*u"°C"))
                sql_transaction() do
                    append_ledger()          # a bare append inside a transaction, as update does
                end
            end
            """)
        n = 30
        project = dirname(Base.active_project())
        procs = [run(pipeline(`$(Base.julia_cmd()) --project=$project $script $path $room_id $n $tag`;stderr=stderr);wait=false) for tag in ("a","b")]
        wait.(procs)
        @test all(success, procs)

        with_scratch_db(path=path,create=false) do _
            ledger = query_db("SELECT ID, SequenceID, Time FROM Ledger ORDER BY ID")
            @test nrow(ledger) == 1 + 2*n*2                       # initial row + (upload + append) x n x 2 writers
            @test length(unique(ledger.SequenceID)) == nrow(ledger) # no slot was taken twice
            @test sort(ledger.SequenceID) == collect(1:nrow(ledger))
            @test issorted(ledger.Time)
            # every upload landed on its own slot
            attrs = query_db("SELECT LedgerID FROM EnvironmentAttributes")
            @test nrow(attrs) == 2*n
            @test length(unique(attrs.LedgerID)) == 2*n
        end
    end
end

@testset "connection: foreign keys are set once on connect, and query_db leaves no statement open" begin
    with_scratch_db() do path
        db = CHESSDatabase._require_db()
        fk() = DBInterface.execute(db,"PRAGMA foreign_keys") |> DataFrame |> df -> df[1,1]
        @test fk() == 1
        # a write that breaks a foreign key is refused without any per-statement PRAGMA
        @test_throws Exception execute_db("INSERT INTO Transfers(Source,Destination,Quantity,LedgerID) VALUES (999999,999998,1,999997)")
        # statements are finalized when their rows are read, not left for the garbage collector
        live_statements() = (n = 0; st = SQLite.C.sqlite3_next_stmt(db.handle,C_NULL);
            while st != C_NULL; n += 1; st = SQLite.C.sqlite3_next_stmt(db.handle,st); end; n)
        before = live_statements()
        for _ in 1:200
            query_db("SELECT 1 AS x")
            query_db("SELECT ? AS x",(1,))
        end
        @test live_statements() - before < 5
    end
end
