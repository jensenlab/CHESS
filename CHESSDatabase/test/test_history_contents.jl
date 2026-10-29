# reconstruct_history(id, :contents): the stock of a well after each event on it (src/reconstruction/reconstruct_history.jl).
# The property that matters (the stock at every slot equals reconstruct_contents) is also checked on random ledgers in
# test/equivalence/test_equivalence.jl; here a planted ledger. Every location is new (prefixed `hc_`).

hc_same(a,b) = (a isa Empty && b isa Empty) || (!(a isa Empty) && !(b isa Empty) && isapprox(a,b;rtol=1e-9))
hc_stock(id,s,tm=Dates.now()) = CHESSCore.stock(reconstruct_contents(id,s,tm))
function hc_check(h,id,from,to;tm=Dates.now())
    bad = Int[]
    for s in from:to
        v = CHESSDatabase.history_value_at(h,s)
        v = ismissing(v) ? Empty() : v
        hc_same(v,hc_stock(id,s,tm)) || push!(bad,s)
    end
    return bad
end

hc_lab = generate_location(Lab,"hc lab")
hc_room = generate_location(Room,"hc room")
upload(move_into!,hc_lab,hc_room)
hc_bottleA = generate_location(Bottle1L,"hc A")
hc_bottleC = generate_location(Bottle1L,"hc C")
upload(move_into!,hc_room,hc_bottleA); upload(move_into!,hc_room,hc_bottleC)
hc_a, hc_c = hc_bottleA[1,1], hc_bottleC[1,1]
deposit!(hc_a,500u"mL"*rgt"water"); deposit!(hc_c,500u"mL"*rgt"glycerol")
cache(hc_a); cache(hc_c)
hc_plate = generate_location(WP96,"hc plate")
upload(move_into!,hc_room,hc_plate)
hc_w, hc_y, hc_x = hc_plate[1,1], hc_plate[1,2], hc_plate[1,3]
hc_s0 = get_last_sequence_id()
hc_slot = Dict{Symbol,Int}()
function hc_do(name,f,args...)
    lid = upload(f,args...)
    sleep(0.02)
    hc_slot[name] = get_sequence_id(lid)
end
hc_do(:a_w,transfer!,hc_a,hc_w,10u"µL")
hc_do(:w_y,transfer!,hc_w,hc_y,3u"µL")
hc_do(:c_w,transfer!,hc_c,hc_w,5u"µL")
hc_do(:w_x,transfer!,hc_w,hc_x,5u"µL")
hc_slot[:cache_w] = (cache(reconstruct_location(location_id(hc_w))); get_last_sequence_id())
hc_do(:a_w2,transfer!,hc_a,hc_w,2u"µL")
hc_do(:other,transfer!,hc_c,hc_y,1u"µL")      # not on W
hc_do(:w_x2,transfer!,hc_w,hc_x,4u"µL")
hc_last = get_last_sequence_id()
hc_w_id, hc_x_id, hc_y_id = location_id(hc_w), location_id(hc_x), location_id(hc_y)

@testset "history: contents of a well follow its transfers and caches" begin
    h = reconstruct_history(hc_w_id,:contents;from=hc_s0)
    @test names(h) == ["SequenceID","LedgerID","Time","Value","Unit","Origin","Event"]
    # a cache is written at the slot of the last operation, here the transfer out of W: the cache stands for that slot
    @test hc_slot[:cache_w] == hc_slot[:w_x]
    @test h.SequenceID[end-5:end] == [hc_slot[k] for k in (:a_w,:w_y,:c_w,:cache_w,:a_w2,:w_x2)]
    @test h.Event[end-5:end] == ["transfer in","transfer out","transfer in","cache","transfer in","transfer out"]
    @test all(==(hc_w_id),h.Origin)
    @test all(ismissing,h.Unit)
    @test isempty(hc_check(h,hc_w_id,hc_s0,hc_last))
    hx = reconstruct_history(hc_x_id,:contents;from=hc_s0)
    @test isempty(hc_check(hx,hc_x_id,hc_s0,hc_last))
    @test hx.Event[end-1:end] == ["transfer in","transfer in"]
    hy = reconstruct_history(hc_y_id,:contents;from=hc_s0)
    @test isempty(hc_check(hy,hc_y_id,hc_s0,hc_last))
end

@testset "history: contents from a slot in the middle, and collapse" begin
    mid = hc_slot[:c_w]
    h = reconstruct_history(hc_w_id,:contents;from=mid)
    @test h.SequenceID[1] == mid
    @test isempty(hc_check(h,hc_w_id,mid,hc_last))
    h2 = reconstruct_history(hc_w_id,:contents;from=hc_slot[:other],to=hc_slot[:other])
    @test h2.SequenceID == [hc_slot[:a_w2]]            # the state in force at `from`
    @test isempty(hc_check(h2,hc_w_id,hc_slot[:other],hc_slot[:other]))
    full = reconstruct_history(hc_w_id,:contents;from=hc_s0,collapse=false)
    @test nrow(full) >= nrow(reconstruct_history(hc_w_id,:contents;from=hc_s0))
    @test isempty(hc_check(full,hc_w_id,hc_s0,hc_last))
    @test nrow(reconstruct_history(hc_w_id,:contents;from=hc_last + 5,to=hc_last + 9)) <= 1
end

@testset "history: contents pages join up to the whole history" begin
    full = reconstruct_history(hc_w_id,:contents;from=hc_s0)
    for order in (:asc,:desc), limit in (1,2,3)
        pages = DataFrame[]; after = nothing
        while true
            pg = reconstruct_history(hc_w_id,:contents;from=hc_s0,order=order,limit=limit,after=after)
            nrow(pg) == 0 && break
            push!(pages,pg); after = pg.SequenceID[end]
            nrow(pg) < limit && break
        end
        got = reduce(vcat,pages)
        want = order === :asc ? full : full[end:-1:1,:]
        @test got.SequenceID == want.SequenceID
        @test all(hc_same(a,b) for (a,b) in zip(got.Value,want.Value))
    end
end

@testset "history: contents refusals and non-wells" begin
    @test_throws ArgumentError reconstruct_history(hc_w_id,:contents;from=hc_s0,max_closure=0)
    @test nrow(reconstruct_history(hc_w_id,:contents;from=hc_s0,max_closure=1000)) > 0
    @test_throws ArgumentError reconstruct_history(hc_w_id,:contents;effective=true)
    @test_throws ArgumentError reconstruct_history(hc_w_id,:contents;encumbrances=true)
    @test nrow(reconstruct_history(location_id(hc_room),:contents;from=hc_s0)) == 0
end
