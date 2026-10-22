# Forward tracing and the well-to-container lookup. Every location is new (prefixed `ft_`) and runs
# against the shared database set up in build_test_database.jl.

ft_ids(df) = Set(df.WellID)

@testset "Containment: each well is recorded with its labware" begin
    plate = generate_location(WP96,"ft containment plate")
    w = plate[2,3]
    @test well_container(location_id(w)) == location_id(plate)
    cw = container_wells(location_id(plate))
    @test nrow(cw) == 96
    @test (location_id(w), 2, 3) in Set(zip(cw.WellID,cw.RowIdx,cw.ColIdx))
    ids = location_id.(vec(children(plate)))
    @test all(well_containers(ids) |> d -> [d[i] for i in ids] .== location_id(plate))
    @test isnothing(well_container(location_id(plate))) # a labware is not a well

    # a committed bottle too
    bottle = commit_location!(build_location(Bottle1L,"ft committed bottle"))
    @test well_container(location_id(bottle[1,1])) == location_id(bottle)

    # more ids than one SQL statement can take
    many = vcat(ids,ids,fill(-1,2000))
    @test length(well_containers(many)) == 96
end

@testset "Containment: a database without the table gains it from the caches" begin
    plate = generate_location(WP96,"ft backfill plate")
    ids = location_id.(vec(children(plate)))
    execute_db("DROP TABLE Containment")
    CHESSDatabase._ensure_containment_table!()
    @test well_container(ids[1]) == location_id(plate)
    @test nrow(container_wells(location_id(plate))) == 96
    @test (location_id(plate[2,3]), 2, 3) in Set(zip(container_wells(location_id(plate)).WellID,container_wells(location_id(plate)).RowIdx,container_wells(location_id(plate)).ColIdx))
    @test rebuild_containment!() == 0 # nothing left to fill
end

# a source bottle feeds a plate well, which feeds a second plate; another plate is fed before the source
# has anything to give
ft_src = commit_location!(build_location(Bottle1L,"ft src bottle"))
ft_plate1 = generate_location(WP96,"ft plate 1")
ft_plate2 = generate_location(WP96,"ft plate 2")
ft_early = generate_location(WP96,"ft early plate")
observe(ft_src[1,1],rgt"water",500u"mL")
ft_t1 = upload(transfer!,ft_src[1,1],ft_plate1[1,1],100u"µL")
ft_t2 = upload(transfer!,ft_plate1[1,1],ft_plate2[1,1],50u"µL")
ft_t3 = upload(transfer!,ft_src[1,1],ft_plate1[1,2],100u"µL")
ft_t4 = upload(transfer!,ft_plate1[1,2],ft_plate2[1,2],25u"µL")

@testset "trace_forward: wells reached, in order, with paths" begin
    t = trace_forward(location_id(ft_src[1,1]))
    @test ft_ids(t) == Set(location_id.([ft_src[1,1],ft_plate1[1,1],ft_plate1[1,2],ft_plate2[1,1],ft_plate2[1,2]]))
    r(w) = t[t.WellID .== location_id(w),:][1,:]
    @test r(ft_src[1,1]).Depth == 0 && ismissing(r(ft_src[1,1]).ViaWell) && ismissing(r(ft_src[1,1]).FirstLedgerID)
    @test r(ft_plate1[1,1]).Depth == 1 && r(ft_plate1[1,1]).ViaWell == location_id(ft_src[1,1])
    @test r(ft_plate1[1,1]).FirstLedgerID == ft_t1
    @test r(ft_plate2[1,1]).Depth == 2 && r(ft_plate2[1,1]).ViaWell == location_id(ft_plate1[1,1])
    @test r(ft_plate2[1,1]).ContainerID == location_id(ft_plate2)
    @test issorted(t.FirstSequenceID)

    # starting from a plate well follows only what leaves it
    t1 = trace_forward(location_id(ft_plate1[1,1]))
    @test ft_ids(t1) == Set(location_id.([ft_plate1[1,1],ft_plate2[1,1]]))

    # a labware is not a well
    @test_throws ErrorException trace_forward(location_id(ft_plate1))
end

@testset "trace_forward: only transfers after the material arrived are followed" begin
    # z holds water of its own and gives some to q before it receives anything from the source
    z, q, r = ft_early[1,1], ft_early[1,2], ft_early[1,3]
    observe(z,rgt"water",100u"µL")
    upload(transfer!,z,q,10u"µL")
    upload(transfer!,ft_src[1,1],z,30u"µL")
    upload(transfer!,z,r,20u"µL")
    t = trace_forward(location_id(ft_src[1,1]))
    @test location_id(r) in ft_ids(t)
    @test !(location_id(q) in ft_ids(t))
    # from the start of z's own history both are reached
    @test ft_ids(trace_forward(location_id(z))) == Set(location_id.([z,q,r]))
    # from_sequence moves the start: after the last transfer, nothing leaves z
    @test ft_ids(trace_forward(location_id(z);from_sequence=get_last_sequence_id()+1)) == Set([location_id(z)])
end

@testset "trace_forward: containers and runs" begin
    exp_id = upload_experiment("ft experiment","ft user")
    upload_run(Run(ft_plate2,exp_id,Int[],Int[]))
    t = trace_forward(location_id(ft_src[1,1]))
    fc = forward_containers(t)
    @test Set(fc.ContainerID) == Set(location_id.([ft_src,ft_plate1,ft_plate2,ft_early]))
    @test fc[fc.ContainerID .== location_id(ft_plate2),:WellCount] == [2]
    runs = forward_runs(t)
    @test nrow(runs) == 1 && runs.LocationID == [location_id(ft_plate2)] && runs.ExperimentID == [exp_id]
    @test nrow(forward_runs(location_id(ft_plate1[1,1]))) == 1 # the same through a well id
    @test nrow(forward_runs(location_id(ft_src[1,1]);)) == 1
end

@testset "trace_forward: from a lot" begin
    lot = Lot("FT Supplier","FT-1","FT-LOT-A")
    @test isempty(trace_forward(lot)) # no labware has it yet
    observe(ft_src,lot)
    t = trace_forward(lot)
    @test location_id(ft_plate2[1,1]) in ft_ids(t)
    @test t[t.WellID .== location_id(ft_src[1,1]),:Depth] == [0]
    # as of a sequence before the lot was observed the lot has no labware
    @test isempty(trace_forward(lot,get_last_sequence_id()-1))
    # a later observation of another lot takes the labware out of the first lot
    observe(ft_src,Lot("FT Supplier","FT-1","FT-LOT-B"))
    @test isempty(trace_forward(lot))
    @test !isempty(trace_forward(Lot("FT Supplier","FT-1","FT-LOT-B")))
    @test !isempty(trace_forward(lot,get_last_sequence_id()-1))
end

@testset "trace_forward follows amendments to the ledger" begin
    src = ft_src[1,1]
    before_time = Dates.now()
    sleep(0.05)
    before_seq = get_last_sequence_id()
    # redirect t4: plate1[1,2] now feeds plate2[1,3] instead of plate2[1,2]
    seq4 = get_sequence_id(ft_t4)
    update(transfer!,ft_plate1[1,2],ft_plate2[1,3],25u"µL";replace=seq4)
    t = trace_forward(location_id(src))
    @test location_id(ft_plate2[1,3]) in ft_ids(t)
    @test !(location_id(ft_plate2[1,2]) in ft_ids(t))
    # the history as the database recorded it before the fix still gives the old list
    old = trace_forward(location_id(src),before_seq,before_time)
    @test location_id(ft_plate2[1,2]) in ft_ids(old)
    @test !(location_id(ft_plate2[1,3]) in ft_ids(old))

    # a missed transfer, inserted before t2, adds its destination
    seq2 = get_sequence_id(ft_t2)
    update(transfer!,ft_plate1[1,1],ft_plate2[2,1],10u"µL";insert=seq2)
    @test location_id(ft_plate2[2,1]) in ft_ids(trace_forward(location_id(src)))
    @test !(location_id(ft_plate2[2,1]) in ft_ids(trace_forward(location_id(src),seq2-1)))
end
