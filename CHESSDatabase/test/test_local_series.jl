# Time series and lists read key first (src/reconstruction/local_series.jl): the environment attributes, the component
# observations and the reads of a location, against the whole-ledger queries they replaced (`_<name>_global`).
# The reads differ from the original on purpose (decision D5): see the testset "get_reads hides superseded reads".
# Every location is new (prefixed `ls_`) and runs against the shared database set up in build_test_database.jl.

ls_canon(x::DataFrame) = (names(x),sort!([join(string.(Tuple(r)),"\u1f") for r in eachrow(x)]))
ls_plan(sql,params=()) = join(query_db("EXPLAIN QUERY PLAN " * sql,params).detail,"; ")
ls_ledger_time(lid) = CHESSDatabase.julia_time(query_db("SELECT Time FROM Ledger WHERE ID = ?",(lid,)).Time[1])
ls_tick() = sleep(0.02)       # ledger times of consecutive writes differ by at least a few milliseconds

ls_plate = generate_location(WP96,"ls plate")
ls_id = location_id(ls_plate)
ls_well = ls_plate[1,1]
ls_wid = location_id(ls_well)

# the temperature is set twice and then amended; the humidity once; a later observation of the temperature
ls_t1 = upload(set_attribute!,ls_plate,Temperature(25u"°C")); ls_tick()
ls_h1 = upload(set_attribute!,ls_plate,Humidity(40u"percent")); ls_tick()
ls_t2 = upload(set_attribute!,ls_plate,Temperature(30u"°C")); ls_tick()
ls_t3 = update(set_attribute!,ls_plate,Temperature(31u"°C");replace=get_sequence_id(ls_t2)); ls_tick()

ls_env(start,stop,time;locs=[ls_id]) = CHESSDatabase.get_environment_attributes(locs,start,stop,time)
ls_env_global(start,stop,time;locs=[ls_id]) = CHESSDatabase._get_environment_attributes_global(locs,start,stop,time)
ls_by_attr(df) = Dict(String(r.Attribute)=>r for r in eachrow(df))

@testset "local series: environment attributes are the latest visible event per attribute" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    rows = ls_env(0,last_,now_)
    @test names(rows) == ["LedgerID","SequenceID","EncumbranceID","LocationID","Attribute","Value","Unit"]
    @test nrow(rows) == 2 && issorted(rows.SequenceID)
    by = ls_by_attr(rows)
    @test by["Temperature"].LedgerID == ls_t3 && by["Temperature"].SequenceID == get_sequence_id(ls_t2)    # the amendment of the slot
    @test by["Humidity"].LedgerID == ls_h1
    # a window that ends before the second temperature sees the first; one that starts after the humidity sees only the temperature
    @test ls_by_attr(ls_env(0,get_sequence_id(ls_h1),now_))["Temperature"].LedgerID == ls_t1
    @test collect(ls_env(get_sequence_id(ls_t2),last_,now_).Attribute) == ["Temperature"]
    @test nrow(ls_env(last_+1,last_+5,now_)) == 0
    # the time before the amendment sees the slot's first revision
    before = ls_ledger_time(ls_t2)
    @test ls_by_attr(ls_env(0,last_,before))["Temperature"].LedgerID == ls_t2
    @test nrow(ls_env(0,last_,ls_ledger_time(ls_t1) - Millisecond(5))) == 0
    for (a,b,t) in ((0,last_,now_),(0,get_sequence_id(ls_h1),now_),(get_sequence_id(ls_t2),last_,now_),(0,last_,before),(0,last_,ls_ledger_time(ls_h1)))
        @test ls_canon(ls_env(a,b,t)) == ls_canon(ls_env_global(a,b,t))
    end
    @test ls_canon(ls_env(0,last_,now_;locs=[ls_id,ls_wid,ls_id])) == ls_canon(ls_env_global(0,last_,now_;locs=[ls_id,ls_wid,ls_id]))
    @test nrow(ls_env(0,last_,now_;locs=[ls_wid])) == 0
    @test nrow(ls_env(0,last_,now_;locs=Int[])) == 0
end

@testset "local series: an observed attribute competes with a recorded one by slot" begin
    now_ = Dates.now()
    obs = observe(ls_plate,Temperature(20u"°C")); ls_tick()
    last_ = get_last_sequence_id()
    @test ls_by_attr(ls_env(0,last_,now_ + Second(1)))["Temperature"].LedgerID == obs
    @test ls_by_attr(ls_env(0,get_sequence_id(obs)-1,now_ + Second(1)))["Temperature"].LedgerID == ls_t3
    for (a,b) in ((0,last_),(0,get_sequence_id(obs)-1))
        @test ls_canon(ls_env(a,b,now_ + Second(1))) == ls_canon(ls_env_global(a,b,now_ + Second(1)))
    end
end

@testset "local series: the global fallbacks" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    local_rows = ls_canon(ls_env(0,last_,now_))
    old_mode = CHESSDatabase.reconstruction_mode[]; old_limit = CHESSDatabase.LOCAL_KEY_LIMIT[]
    try
        CHESSDatabase.reconstruction_mode[] = :legacy
        @test ls_canon(ls_env(0,last_,now_)) == local_rows
        CHESSDatabase.reconstruction_mode[] = :local
        CHESSDatabase.LOCAL_KEY_LIMIT[] = 0
        @test ls_canon(ls_env(0,last_,now_)) == local_rows
    finally
        CHESSDatabase.reconstruction_mode[] = old_mode; CHESSDatabase.LOCAL_KEY_LIMIT[] = old_limit
    end
    # with encumbrances the original runs, as before
    @test ls_canon(CHESSDatabase.get_environment_attributes([ls_id],0,last_,now_;encumbrances=true)) ==
          ls_canon(CHESSDatabase._get_environment_attributes_global([ls_id],0,last_,now_;encumbrances=true))
end

@testset "local series: content observations are listed in slot order and match the original" begin
    o1 = observe(ls_well,rgt"water",5u"µL"); ls_tick()
    o2 = observe(ls_well,rgt"water",7u"µL"); ls_tick()
    o3 = observe(ls_plate[1,2],rgt"water",3u"µL"); ls_tick()
    now_ = Dates.now()
    last_ = get_last_sequence_id()
    ids = [ls_wid,location_id(ls_plate[1,2])]
    rows = CHESSDatabase.get_content_observations(ids,0,last_,now_)
    @test names(rows) == ["LedgerID","SequenceID","LocationID","ComponentID","Quantity","Unit"]
    @test issorted(rows.SequenceID)
    @test collect(rows.LedgerID) == [o1,o2,o3]
    @test collect(CHESSDatabase.get_content_observations([ls_wid],get_sequence_id(o2),last_,now_).LedgerID) == [o2]
    @test nrow(CHESSDatabase.get_content_observations([ls_wid],0,get_sequence_id(o2)-1,now_)) == 1
    @test nrow(CHESSDatabase.get_content_observations([ls_id],0,last_,now_)) == 0
    @test nrow(CHESSDatabase.get_content_observations(Int[],0,last_,now_)) == 0
    for (a,b,t) in ((0,last_,now_),(get_sequence_id(o2),last_,now_),(0,last_,ls_ledger_time(o1)),(0,get_sequence_id(o2),ls_ledger_time(o3)))
        @test ls_canon(CHESSDatabase.get_content_observations(ids,a,b,t)) == ls_canon(CHESSDatabase._get_content_observations_global(ids,a,b,t))
    end
    # an amended observation: only the current revision is listed
    CHESSDatabase.sql_transaction() do
        l = CHESSDatabase.replace_ledger(get_sequence_id(o2))
        CHESSDatabase.execute_db("INSERT INTO ObservedComponents(LedgerID,LocationID,ComponentID,Quantity,Unit,Time) SELECT ?,LocationID,ComponentID,9.0,Unit,Time FROM ObservedComponents WHERE LedgerID = ?",(l,o2))
    end
    last_ = get_last_sequence_id()
    rows = CHESSDatabase.get_content_observations([ls_wid],0,last_,now_ + Second(1))
    @test nrow(rows) == 2 && rows.Quantity[2] == 9.0
    @test ls_canon(rows) == ls_canon(CHESSDatabase._get_content_observations_global([ls_wid],0,last_,now_ + Second(1)))
end

# --------------------------------------------------------------------------------------------------- reads

ls_base = DateTime(2026,3,1,12,0,0)
ls_reads_plate = generate_location(WP96,"ls reads plate")
ls_r_well = ls_reads_plate[1,1]; ls_rid = location_id(ls_r_well)
# uploaded out of order of their instrument times: +3 min, +1 min, +2 min, and one without instrument time
ls_r1 = upload(record_read!,ls_r_well,Absorbance(30u"percent",ls_base + Minute(3))); ls_tick()
ls_r2 = upload(record_read!,ls_r_well,Absorbance(10u"percent",ls_base + Minute(1))); ls_tick()
ls_r3 = upload(record_read!,ls_r_well,Absorbance(20u"percent",ls_base + Minute(2))); ls_tick()
ls_r4 = upload(record_read!,ls_r_well,ColorimetricResult("Positive")); ls_tick()
ls_values(df) = [ismissing(v) ? missing : v for v in df.Value]
ls_lids(df) = collect(df.LedgerID)

@testset "local series: reads are ordered by the time of the read, and paged" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    all_ = CHESSDatabase.get_reads(ls_rid,last_,now_)
    @test names(all_) == names(CHESSDatabase._get_reads_global(ls_rid,last_,now_))
    # the read without instrument time sorts by its upload time, which is later than the others
    @test ls_lids(all_) == [ls_r2,ls_r3,ls_r1,ls_r4]
    @test ls_canon(all_) == ls_canon(CHESSDatabase._get_reads_global(ls_rid,last_,now_))
    newest = CHESSDatabase.get_reads(ls_rid,last_,now_;newest_first=true)
    @test ls_lids(newest) == reverse(ls_lids(all_))
    page = CHESSDatabase.get_reads(ls_rid,last_,now_;limit=2,offset=1)
    @test ls_lids(page) == ls_lids(all_)[2:3]
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,last_,now_;limit=2,offset=1,newest_first=true)) == ls_lids(newest)[2:3]
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,last_,now_;offset=3)) == ls_lids(all_)[4:4]
    @test nrow(CHESSDatabase.get_reads(ls_rid,last_,now_;limit=5,offset=10)) == 0
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,last_,now_;since=ls_base + Minute(2),until=ls_base + Minute(3))) == [ls_r3,ls_r1]
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,last_,now_;since=ls_base + Minute(2) + Second(1),until=ls_base + Minute(3),limit=1,newest_first=true)) == [ls_r1]
    # a window that ends before a read does not see it
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,get_sequence_id(ls_r2),now_)) == [ls_r2,ls_r1]
    @test nrow(CHESSDatabase.get_reads(ls_rid,last_,ls_ledger_time(ls_r1) - Millisecond(5))) == 0
    @test nrow(CHESSDatabase.get_reads(ls_id,last_,now_)) == 0
end

@testset "local series: a page of reads is read through the time index" begin
    sql,params = CHESSDatabase._reads_query(ls_rid,get_last_sequence_id(),Dates.now(),2,1,true,nothing,nothing)
    plan = ls_plan(sql,params)
    @test occursin("idx_chess_reads_locationid_coalesce_instrumenttime_time",plan)
    @test !occursin("TEMP B-TREE",plan) && !occursin("SCAN Ledger",plan) && !occursin("SCAN r",plan)
    sql,params = CHESSDatabase._reads_query(ls_rid,get_last_sequence_id(),Dates.now(),nothing,0,false,ls_base,ls_base + Hour(1))
    @test !occursin("SCAN Ledger",ls_plan(sql,params))
end

@testset "get_reads hides superseded reads" begin
    # D5. The original returned the reads of every revision of a slot; the revision a later amendment replaced is now hidden.
    now0 = Dates.now()
    amended = CHESSDatabase.sql_transaction() do
        l = CHESSDatabase.replace_ledger(get_sequence_id(ls_r3))
        CHESSDatabase.upload_read(ls_r_well,Absorbance(25u"percent",ls_base + Minute(2));ledger_id=l)
        l
    end
    ls_tick()
    last_ = get_last_sequence_id(); now_ = Dates.now()
    old_rows = CHESSDatabase._get_reads_global(ls_rid,last_,now_)
    new_rows = CHESSDatabase.get_reads(ls_rid,last_,now_)
    @test nrow(old_rows) == 5                                  # old result: both revisions of the slot
    @test Set(old_rows.LedgerID) == Set([ls_r1,ls_r2,ls_r3,ls_r4,amended])
    @test nrow(new_rows) == 4                                  # new result: the current revision only
    @test Set(new_rows.LedgerID) == Set([ls_r1,ls_r2,amended,ls_r4])
    @test ls_lids(new_rows)[1:3] == [ls_r2,amended,ls_r1]
    # read before the amendment, the slot still has its first revision
    t_before = ls_ledger_time(ls_r3)
    @test Set(CHESSDatabase.get_reads(ls_rid,last_,t_before).LedgerID) == Set([ls_r1,ls_r2,ls_r3])
    # pages never see the hidden revision either
    @test ls_lids(CHESSDatabase.get_reads(ls_rid,last_,now_;limit=2,offset=1)) == [amended,ls_r1]
    @test !(ls_r3 in CHESSDatabase.get_reads(ls_rid,last_,now_;newest_first=true,limit=10).LedgerID)
    # the reconstructed location has one read per current revision
    @test length(reads(reconstruct_reads(ls_rid,last_,now_))) == 4
    # `:legacy` returns what the original returned
    old_mode = CHESSDatabase.reconstruction_mode[]
    try
        CHESSDatabase.reconstruction_mode[] = :legacy
        @test ls_canon(CHESSDatabase.get_reads(ls_rid,last_,now_)) == ls_canon(old_rows)
    finally
        CHESSDatabase.reconstruction_mode[] = old_mode
    end
end
