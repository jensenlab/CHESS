# A well that only receives from the requested well is not part of the closure reconstruct_contents replays: nothing it holds can
# reach the requested well, so what it sent on or discarded is skipped. Found by the nightly equivalence run: a discard from such
# a well, which had also received transfers from wells outside the closure, found the well empty and threw. Every location is new
# (prefixed `rs`).

@testset "reconstruct_contents: a well that only receives from the requested closure" begin
    rs_a = commit_location!(build_location(Bottle1L,"rs a"))
    rs_b = commit_location!(build_location(Bottle1L,"rs b"))
    rs_c = commit_location!(build_location(Bottle1L,"rs c"))
    rs_x = commit_location!(build_location(Bottle1L,"rs x"))
    observe(rs_a[1,1],rgt"water",500u"mL")
    observe(rs_c[1,1],rgt"water",500u"mL")
    l_in   = upload(transfer!,rs_a[1,1],rs_b[1,1],100u"mL")   # into b from a well that is not an ancestor of c
    l_side = upload(transfer!,rs_c[1,1],rs_x[1,1],10u"mL")    # c's cache moves past that transfer
    l_out  = upload(discard!,rs_b[1,1],20u"mL")               # b's first row in c's closure
    l_c_b  = upload(transfer!,rs_c[1,1],rs_b[1,1],50u"mL")    # makes b part of c's closure
    seq(l) = get_sequence_id(l)
    # c's newest cache is the one at l_side, so the window opens there, after b received from a; b only receives from c
    rs_loc = reconstruct_contents(location_id(rs_c[1,1]),seq(l_c_b),Dates.now(),seq(l_side))
    @test liquids(stock(rs_loc))[rgt"water"] ≈ 440u"mL"
    rs_b_loc = reconstruct_contents(location_id(rs_b[1,1]),seq(l_c_b))
    @test liquids(stock(rs_b_loc))[rgt"water"] ≈ 130u"mL"
end
