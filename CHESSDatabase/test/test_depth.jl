# The `depth` keyword of reconstruct_location (src/reconstruction/reconstruct_location.jl): a depth fills the fields
# of its level and the levels below it, and the value of a field is the one of the full reconstruction.
# Every location is new (prefixed `dp_`) and runs against the shared database set up in build_test_database.jl.

dp_room = generate_location(Room,"dp room")
dp_lab = generate_location(Lab,"dp lab")
upload(move_into!,dp_lab,dp_room)
upload(move_into!,dp_lab,generate_location(Room,"dp room 2"))
dp_plate = generate_location(WP96,"dp plate")
upload(move_into!,dp_room,dp_plate)
upload(set_attribute!,dp_room,Temperature(21u"°C"))
upload(set_attribute!,dp_plate,Humidity(45u"percent"))
dp_bottle = commit_location!(build_location(Bottle1L,"dp bottle"))
observe(dp_bottle[1,1],rgt"water",500u"mL")
dp_lot = Lot("Fisher Scientific","DP1","DPLOT";quantity=1u"L")
observe(dp_bottle,dp_lot)
dp_well = dp_plate[1,1]
dp_well2 = dp_plate[1,2]
upload(transfer!,dp_bottle[1,1],dp_well,100u"µL")
upload(transfer!,dp_well,dp_well2,20u"µL")
upload(record_read!,dp_well,Absorbance(30u"percent",Dates.now() - Minute(3)))
upload(record_read!,dp_well,Absorbance(10u"percent",Dates.now() - Minute(2)))
upload(record_read!,dp_well,Absorbance(20u"percent",Dates.now() - Minute(1)))
upload(lock!,dp_plate)
upload(deactivate!,dp_well2)

dp_id(x) = location_id(x)
dp_parent_id(l) = isnothing(CHESSCore.parent(l)) ? nothing : location_id(CHESSCore.parent(l))
dp_chain(l) = (ids = Int[]; p = CHESSCore.parent(l); while !isnothing(p); push!(ids,location_id(p)); p = CHESSCore.parent(p); end; ids)

@testset "depth: each level fills its fields with the values of the full reconstruction" begin
    for loc in (dp_plate,dp_well,dp_well2,dp_bottle,dp_room)
        id = dp_id(loc)
        full = reconstruct_location(id)
        for d in 0:5
            r = reconstruct_location(id;depth=d)
            @test typeof(r) == typeof(full) && name(r) == name(full) && r.kind == full.kind
            if d >= 1
                @test dp_parent_id(r) == dp_parent_id(full)
                @test is_active(r) == is_active(full)
                loc isa Labware && @test is_locked(r) == is_locked(full)
                loc isa Labware && @test CHESSCore.lot(r) == CHESSCore.lot(full)
            else
                @test isnothing(CHESSCore.parent(r)) && is_active(r) == true
            end
            if d >= 2
                @test dp_chain(r) == dp_chain(full)
                @test attributes(r) == attributes(full)
                @test environment(r) == environment(full)
            end
            if d >= 3
                loc isa Well && @test stock(r) == stock(full)
                loc isa Labware && @test map(location_id,children(r)) == map(location_id,children(full))
                loc isa GenericLocation && @test map(location_id,children(r)) == map(location_id,children(full))
            end
            if d >= 5
                @test reads(r) == reads(full)
            else
                @test isempty(reads(r))
            end
        end
    end
    # the planted state is really there (so the equalities above compare something)
    full_plate = reconstruct_location(dp_id(dp_plate))
    @test is_locked(full_plate) && dp_chain(full_plate) == [dp_id(dp_room),dp_id(dp_lab)]
    @test !is_active(reconstruct_location(dp_id(dp_well2)))
    @test length(reads(reconstruct_location(dp_id(dp_well)))) == 3
    @test CHESSCore.lot(reconstruct_location(dp_id(dp_bottle))) == dp_lot
end

@testset "depth: lower depths leave the higher fields at their defaults" begin
    d1 = reconstruct_location(dp_id(dp_plate);depth=1)
    @test CHESSCore.parent(d1) isa Location && isempty(CHESSCore.attributes(d1))   # the parent is a shell: no chain, no attributes
    @test isnothing(CHESSCore.parent(CHESSCore.parent(d1)))
    @test is_locked(d1)
    d0 = reconstruct_location(dp_id(dp_plate);depth=0)
    @test !is_locked(d0)
    d2 = reconstruct_location(dp_id(dp_well);depth=2)
    @test stock(d2) isa CHESSCore.Empty
    @test stock(reconstruct_location(dp_id(dp_well);depth=3)) == stock(reconstruct_location(dp_id(dp_well)))
end

@testset "depth: old callers are unchanged" begin
    x = reconstruct_location(dp_id(dp_well))
    @test x isa Well                                       # no tuple without report=true
    @test reconstruct_location!(reconstruct_location(dp_id(dp_well);depth=0),get_last_sequence_id(),Dates.now()) === nothing
    @test reconstruct_locations([dp_id(dp_well),dp_id(dp_plate)]) isa Vector{Location}
    loc = CHESSCore.Well(dp_id(dp_well),name(dp_well),dp_well.kind)
    reconstruct_location!(loc)
    @test stock(loc) == stock(x) && reads(loc) == reads(x)
end

@testset "depth: report" begin
    loc,rep = reconstruct_location(dp_id(dp_well);depth=3,report=true)
    @test loc isa Well && rep isa ReconstructionReport
    @test rep.depth_requested == 3 && rep.depth_reached == 3 && isempty(rep.truncated) && isnothing(rep.closure_rows)
    @test reconstruct_location(dp_id(dp_well);report=true)[2].depth_requested == :legacy
    @test reconstruct_location!(loc;depth=1,report=true) isa ReconstructionReport
    @test reconstruct_location(dp_id(dp_well);depth=4,report=true)[2].notes[1] |> x -> occursin("lineage",x)
    @test_throws ArgumentError reconstruct_location(dp_id(dp_well);depth=6)
    @test_throws ArgumentError reconstruct_location(dp_id(dp_well);depth=-1)
    @test_throws ArgumentError reconstruct_location(dp_id(dp_well);depth=:deep)
end

@testset "depth: budgets cut work and the report says so" begin
    full = reconstruct_location(dp_id(dp_well2))
    # the closure of well 2 is its own transfer and that of the well before it (and the bottle): 2 or more rows
    loc,rep = reconstruct_location(dp_id(dp_well2);depth=3,max_closure=1,report=true)
    @test rep.closure_rows >= 2 && rep.truncated == [:contents] && rep.depth_reached == 2 && rep.depth_requested == 3
    @test stock(loc) isa CHESSCore.Empty
    loc,rep = reconstruct_location(dp_id(dp_well2);depth=3,max_closure=100,report=true)
    @test rep.truncated == [:contents] ? false : stock(loc) == stock(full) && rep.depth_reached == 3
    # reads: the newest ones, in time order
    loc,rep = reconstruct_location(dp_id(dp_well);reads_limit=2,report=true)
    allr = reads(reconstruct_location(dp_id(dp_well)))
    @test rep.truncated == [:reads] && reads(loc) == allr[end-1:end] && rep.depth_reached == 5
    loc,rep = reconstruct_location(dp_id(dp_well);reads_limit=3,report=true)
    @test isempty(rep.truncated) && reads(loc) == allr
    # children of a generic location
    loc,rep = reconstruct_location(dp_id(dp_lab);depth=3,children_limit=0,report=true)
    @test isempty(children(loc)) && rep.truncated == [:children] && rep.depth_reached == 2
    loc,rep = reconstruct_location(dp_id(dp_lab);depth=3,children_limit=1,report=true)
    @test length(children(loc)) == 1 && rep.truncated == [:children]
    loc,rep = reconstruct_location(dp_id(dp_lab);depth=3,children_limit=2,report=true)
    @test length(children(loc)) == 2 && isempty(rep.truncated) && rep.depth_reached == 3
end
