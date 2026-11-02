# Regression tests for `reconstruct_contents(...; encumbrances=true)` across plans (CHESS #19, #20).
#
# #19: the bootstrap of a core ancestor well without a usable cache (the ancestor's cache is older than the
# requested well's own cache, so it falls outside the replay window) used to call `reconstruct_contents`
# without `encumbrances`, which dropped the planned transfers into that ancestor; the planned draw out of
# it then withdrew from an empty well and failed with a bare `TypeError`.
#
# #20: replaying a draw out of a well that holds too little is reported as an `UnfilledDrawError`.
#
# Everything is built from raw CHESSDatabase calls on fresh locations of the shared database.

eb_room = generate_location(Room,"eb room")
eb_bottle(name) = (b = generate_location(Bottle1L,name); upload(move_into!,eb_room,b); b[1,1])
eb_seq() = get_last_sequence_id()
eb_qty(w;kw...) = quantity(stock(reconstruct_location(location_id(w);kw...)))

# A source holding 1 L (cached) and its downstream wells. Wells are created one after the other, each after the
# protocol that fills the one before it is enforced, so every well's own (empty) cache is newer than the planned
# transfers into its ancestors. `plan` is a list of (from index, to index, quantity), one protocol each.
function eb_chain(n_hops,plan)
    src = eb_bottle("eb source $n_hops")
    deposit!(src,1000u"mL"*rgt"water")
    cache(src)
    wells = [src]
    for h in 1:n_hops
        push!(wells,eb_bottle("eb hop $h of $n_hops"))
        h > length(plan) || ((i,j,q) = plan[h]; eb_protocol("eb plan $n_hops.$h",[(wells[i],wells[j],q)]))
    end
    return wells
end

function eb_protocol(name,plan)
    exp_id = upload_experiment(name,"Ben")
    p = upload_protocol(exp_id,name)
    for (src,dst,q) in plan
        encumber(p,transfer!,src,dst,q)
    end
    return p
end

@testset "encumbrances=true bootstraps ancestors with the planned transfers (CHESS #19)" begin
    A,B,Q = eb_chain(2,[(1,2,200u"mL")])
    eb_protocol("eb p2",[(B,Q,100u"mL")])
    @test eb_qty(Q;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(B;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(A;encumbrances=true) ≈ 800u"mL"
    # the cache bound does not change the answer
    @test quantity(stock(reconstruct_location(location_id(Q),eb_seq(),Dates.now(),0;encumbrances=true))) ≈ 100u"mL"
    # without encumbrances nothing planned is seen
    @test stock(reconstruct_location(location_id(Q))) isa Empty
    @test eb_qty(A) ≈ 1000u"mL"
end

@testset "encumbrances=true: two planned draws from one intermediate well" begin
    A,B,Q = eb_chain(2,[(1,2,200u"mL")])
    eb_protocol("eb p2",[(B,Q,100u"mL"),(B,Q,50u"mL")])
    @test eb_qty(Q;encumbrances=true) ≈ 150u"mL"
    @test eb_qty(B;encumbrances=true) ≈ 50u"mL"
end

@testset "encumbrances=true: a three-hop chain of planned transfers" begin
    A,B,C,Q = eb_chain(3,[(1,2,300u"mL"),(2,3,200u"mL")])
    eb_protocol("eb p3",[(C,Q,100u"mL")])
    @test eb_qty(Q;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(C;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(B;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(A;encumbrances=true) ≈ 700u"mL"
end

@testset "reconstruct_history(encumbrances=true) agrees with reconstruct_contents on the same chain" begin
    A,B,Q = eb_chain(2,[(1,2,200u"mL")])
    eb_protocol("eb p2",[(B,Q,100u"mL")])
    h = reconstruct_history(location_id(Q),:contents;from=0,encumbrances=true)
    @test quantity(h[end,:Value]) ≈ 100u"mL"
end

@testset "a draw out of an unfilled well is an UnfilledDrawError (CHESS #20)" begin
    A,B = eb_chain(1,Tuple[])
    exp1 = upload_experiment("eb unfilled 1","Ben"); p1 = upload_protocol(exp1,"eb fill")
    e1 = encumber(p1,transfer!,A,B,200u"mL")
    Q = eb_bottle("eb unfilled sink")
    exp2 = upload_experiment("eb unfilled 2","Ben"); p2 = upload_protocol(exp2,"eb draw")
    e2 = encumber(p2,transfer!,B,Q,100u"mL")
    @test eb_qty(Q;encumbrances=true) ≈ 100u"mL"

    CHESSDatabase.upload_protocol_enforcement(p1,false) # the fill is lifted, the draw is still enforced
    err = try; reconstruct_location(location_id(B);encumbrances=true); nothing; catch e; e; end
    @test err isa UnfilledDrawError
    @test err.encumbrance_id == e2
    @test err.source == location_id(B)
    @test err.destination == location_id(Q)
    @test err.quantity ≈ 100u"mL"
    @test err.available ≈ 0u"mL"
    @test CHESSDatabase.shortfall(err) ≈ 100u"mL"
    msg = sprint(showerror,err)
    @test occursin("Unfilled Draw Error",msg) && occursin("encumbrance $e2",msg) && occursin("well $(location_id(B))",msg) && occursin("well $(location_id(Q))",msg)
    # the well downstream of the lifted fill sees the same protocols as enforced, wherever its cache lies
    errq = try; reconstruct_location(location_id(Q);encumbrances=true); nothing; catch e; e; end
    @test errq isa UnfilledDrawError
    @test errq.encumbrance_id == e2
    @test errq.source == location_id(B)
    # reading without encumbrances, and the well that is filled, are unaffected
    @test eb_qty(A) ≈ 1000u"mL"
    @test eb_qty(A;encumbrances=true) ≈ 1000u"mL"
    @test stock(reconstruct_location(location_id(Q))) isa Empty
end

@testset "a planned draw larger than the well holds reports the shortfall (CHESS #20)" begin
    A,B = eb_chain(1,[(1,2,60u"mL")])
    p_extra = eb_protocol("eb second fill",[(A,B,60u"mL")])
    Q = eb_bottle("eb short sink")
    eb_protocol("eb short draw",[(B,Q,100u"mL")]) # accepted: B holds 120 mL once both fills are enforced
    @test eb_qty(B;encumbrances=true) ≈ 20u"mL"
    CHESSDatabase.upload_protocol_enforcement(p_extra,false)
    err = try; reconstruct_location(location_id(B);encumbrances=true); nothing; catch e; e; end
    @test err isa UnfilledDrawError
    @test err.available ≈ 60u"mL"
    @test CHESSDatabase.shortfall(err) ≈ 40u"mL"
end

@testset "a protocol enforced before a well's newest cache is still seen" begin
    A,B = eb_chain(1,[(1,2,200u"mL")])
    Q = eb_bottle("eb late cache sink")
    eb_protocol("eb early draw",[(B,Q,100u"mL")]) # enforced (and encumbered) ...
    cache(reconstruct_location(location_id(Q))) # ... before Q's newest cache (a fresh read: encumber changed the in-memory wells), with no enforcement change since
    @test eb_qty(Q;encumbrances=true) ≈ 100u"mL"
    @test eb_qty(B;encumbrances=true) ≈ 100u"mL"
    @test stock(reconstruct_location(location_id(Q))) isa Empty
end
