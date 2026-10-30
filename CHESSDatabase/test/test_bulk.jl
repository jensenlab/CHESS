# Large requests (src/reconstruction/bulk.jl): the plan, the bulk transfer closure and the time-respecting repair set.
# Every location is new (prefixed `bk`).

import CHESSDatabase: get_transfer_ancestors, get_transfer_descendents, _get_transfer_ancestors_global, _get_transfer_descendents_global,
    _repair_set, get_locks, _get_locks_global, get_activity, _get_activity_global, get_last_movement_as_child, _get_last_movement_as_child_global,
    get_environment_attributes, _get_environment_attributes_global, get_content_observations, _get_content_observations_global,
    LOCAL_KEY_LIMIT, BULK_FRACTION

bk_canon(x::DataFrame) = (names(x),sort!([join(string.(Tuple(r)),"\u1f") for r in eachrow(x)]))

# run `f` with the bulk path forced (every request is over the key limit and over the fraction)
function bk_forced(f;limit=0,fraction=-1.0)
    old = (LOCAL_KEY_LIMIT[],BULK_FRACTION[])
    LOCAL_KEY_LIMIT[] = limit; BULK_FRACTION[] = fraction
    try f() finally LOCAL_KEY_LIMIT[],BULK_FRACTION[] = old end
end

bk_src = commit_location!(build_location(Bottle1L,"bk bottle"))
observe(bk_src[1,1],rgt"water",900u"mL")
bk_plate = generate_location(WP96,"bk plate")
bk_w = [bk_plate[1,k] for k in 1:6]
bk_id(x) = location_id(x)
bk_s = bk_src[1,1]
bk_l1 = upload(transfer!,bk_s,bk_w[1],100u"µL")
bk_l2 = upload(transfer!,bk_w[1],bk_w[2],30u"µL")
bk_l3 = upload(transfer!,bk_w[2],bk_w[3],10u"µL")
bk_l4 = upload(discard!,bk_w[1],5u"µL")
bk_l5 = upload(transfer!,bk_w[3],bk_w[4],2u"µL")
bk_l6 = upload(transfer!,bk_s,bk_w[5],50u"µL")
update(transfer!,bk_w[1],bk_w[2],40u"µL";replace=get_sequence_id(bk_l2)) # an amendment: the old revision stays in the ledger
bk_l7 = upload(transfer!,bk_w[2],bk_w[1],1u"µL")                          # a cycle

@testset "bulk: plan_reconstruction" begin
    p = plan_reconstruction([bk_id(bk_w[1])])
    @test keys(p) == (:path,:kind,:rows,:ledger_rows,:fraction)
    @test p.kind == :transfers && p.rows == 5 && p.ledger_rows == get_last_ledger_id()
    @test p.fraction ≈ p.rows/p.ledger_rows   # 5: the estimate counts the superseded revision of the amended transfer too
    @test plan_reconstruction([bk_id(bk_w[1])];fraction=0.0).path === :global
    @test plan_reconstruction([bk_id(bk_w[1])];fraction=1.0).path === :local
    @test plan_reconstruction(Int[]).path === :global           # no filter
    @test plan_reconstruction([bk_id(bk_w[6])]).rows == 0       # a well with no transfers
    for kind in (:environment,:observations,:movements,:locks,:activity,:reads)
        @test plan_reconstruction([bk_id(bk_w[1])];kind=kind).kind == kind
    end
    @test_throws ArgumentError plan_reconstruction([1];kind=:nonsense)
    # the default fraction and the key limit are what the plan says
    @test BULK_FRACTION[] == 0.01
    @test plan_reconstruction([bk_id(bk_w[1])]).path === :global   # 5 rows of a ledger this small are over 1%
end

@testset "bulk: the bulk transfer closure equals the local closure and the original" begin
    now_ = Dates.now(); last_ = get_last_sequence_id()
    sets = ([bk_id(bk_w[4])],[bk_id(bk_w[2]),bk_id(bk_w[5])],[bk_id(bk_s)],[bk_id(bk_w[6])],[bk_id(bk_w[1]),bk_id(bk_w[3]),bk_id(bk_w[4])])
    windows = ((0,last_),(get_sequence_id(bk_l3),last_),(0,get_sequence_id(bk_l3)))
    for locs in sets, (a,b) in windows
        local_anc = get_transfer_ancestors(locs,a,b,now_)
        bulk_anc = bk_forced(() -> get_transfer_ancestors(locs,a,b,now_))
        @test bk_canon(bulk_anc) == bk_canon(local_anc)
        @test isequal(bulk_anc,local_anc)                      # same rows in the same order
        @test bk_canon(bulk_anc) == bk_canon(_get_transfer_ancestors_global(locs,a,b,now_))
        local_desc = get_transfer_descendents(locs,a,b,now_)
        bulk_desc = bk_forced(() -> get_transfer_descendents(locs,a,b,now_))
        @test isequal(bulk_desc,local_desc)
        @test bk_canon(bulk_desc) == bk_canon(_get_transfer_descendents_global(locs,a,b,now_))
    end
    # a time before the amendment sees the old revision
    early = get_transfer_ancestors([bk_id(bk_w[2])],0,last_,DateTime(2000))
    @test isequal(bk_forced(() -> get_transfer_ancestors([bk_id(bk_w[2])],0,last_,DateTime(2000))),early)
    # the request takes the bulk path when the plan says so and the local path otherwise
    @test bk_forced(() -> CHESSDatabase._use_global(false,[bk_id(bk_w[1])];kind=:transfers))
    @test !CHESSDatabase._use_global(false,[bk_id(bk_w[1])];kind=:transfers)
    @test CHESSDatabase._use_global(true,[bk_id(bk_w[1])];kind=:transfers)    # planned operations: the original
    # more keys than the limit but few rows: still read key first
    @test !bk_forced(() -> CHESSDatabase._use_global(false,[bk_id(bk_w[6])];kind=:transfers);fraction=0.5)
end

@testset "bulk: many keys read in chunks agree with the original queries" begin
    room = generate_location(Room,"bk room")
    rooms = [room; [generate_location(Room,"bk room $i") for i in 1:3]]
    upload(set_attribute!,room,Temperature(20u"°C"))
    upload(lock!,room)
    upload(deactivate!,rooms[2])
    upload(move_into!,room,rooms[3])
    observe(bk_w[1],rgt"water",1u"µL")
    ids = [bk_id(r) for r in rooms]
    now_ = Dates.now(); last_ = get_last_sequence_id()
    # one chunk per key and no fallback to the whole-ledger queries
    old = (LOCAL_KEY_LIMIT[],BULK_FRACTION[])
    LOCAL_KEY_LIMIT[] = 1; BULK_FRACTION[] = 1.0     # on a ledger this small every request owns more than the default 1%
    try
        @test bk_canon(get_locks(ids,0,last_,now_)) == bk_canon(_get_locks_global(ids,0,last_,now_))
        @test bk_canon(get_activity(ids,0,last_,now_)) == bk_canon(_get_activity_global(ids,0,last_,now_))
        @test bk_canon(get_last_movement_as_child(ids,0,last_,now_)) == bk_canon(_get_last_movement_as_child_global(ids,0,last_,now_))
        @test bk_canon(get_environment_attributes(ids,0,last_,now_)) == bk_canon(_get_environment_attributes_global(ids,0,last_,now_))
        wells = [bk_id(bk_w[1]),bk_id(bk_w[2])]
        @test bk_canon(get_content_observations(wells,0,last_,now_)) == bk_canon(_get_content_observations_global(wells,0,last_,now_))
        @test !CHESSDatabase._use_global(false,ids;kind=:locks)
    finally
        LOCAL_KEY_LIMIT[],BULK_FRACTION[] = old
    end
end

@testset "bulk: the repair set follows the transfers in time" begin
    a = generate_location(Bottle1L,"bk rep a")[1,1]; b = generate_location(Bottle1L,"bk rep b")[1,1]
    c = generate_location(Bottle1L,"bk rep c")[1,1]; d = generate_location(Bottle1L,"bk rep d")[1,1]
    ids(x) = bk_id.(x)
    observe(a,rgt"water",100u"mL")
    observe(c,rgt"water",50u"mL")
    t3 = upload(transfer!,a,b,10u"mL")     # the slot that is amended: A changes from here on
    t4 = upload(transfer!,c,d,5u"mL")      # before A's material reaches C: D does not carry it
    t5 = upload(transfer!,a,c,5u"mL")
    s3 = get_sequence_id(t3)
    set = _repair_set([bk_id(a)],s3)
    structural = _repair_set([bk_id(a)],s3;time_respecting=false)
    @test Set(set) == Set(ids([a,b,c]))                       # B and C receive from A after the change
    @test Set(structural) == Set(ids([a,b,c,d]))              # the structural closure also reaches D, through a transfer out of C before A's reaches it
    @test Set(set) ⊆ Set(structural)
    # a cache of every well, then the amendment repairs them (time respecting by default)
    water(w) = get(liquids(stock(reconstruct_contents(bk_id(w)))),rgt"water",0u"mL")
    for w in (a,b,c,d); CHESSDatabase.cache_contents(reconstruct_contents(bk_id(w)),get_last_ledger_id()) end
    update(transfer!,a,b,30u"mL";replace=s3)
    @test water(b) ≈ 30u"mL" && water(a) ≈ 65u"mL" && water(c) ≈ 50u"mL" && water(d) ≈ 5u"mL"
    # the repair returns the number of caches it rewrote
    @test CHESSDatabase.repair_content_caches([bk_id(a)],s3) isa Integer
    @test CHESSDatabase.repair_content_caches([bk_id(a)],s3;time_respecting=false) isa Integer
    @test water(b) ≈ 30u"mL" && water(a) ≈ 65u"mL" && water(c) ≈ 50u"mL" && water(d) ≈ 5u"mL"
end
