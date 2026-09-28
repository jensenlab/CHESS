#include("./build_test_database.jl")

# Local variables here are named `cr_*` (not the bare `a`/`b`/`c`/`x` used in the original combined
# runtests.jl) to avoid colliding with core_runtests.jl's top-level `a`/`b`/`c`/`d`/`e` Stock
# fixtures -- this file now runs after those are already defined (see test/runtests.jl), whereas in
# the original single-file suite it ran before they existed.

cr_a=reconstruct_location(27,53)

cr_b=reconstruct_location(25,53)
update( transfer!,cr_a,cr_b,1u"g"; ledger_id= replace_ledger(54))


cache(cr_a)
cache(cr_b)

cr_a=reconstruct_location(27,53)

cr_b=reconstruct_location(25,53)

update( transfer!,cr_a,cr_b,7u"g"; ledger_id= insert_ledger(54))



## Movement cache repair
cr_a=reconstruct_location(5,16)

cr_b=reconstruct_location(2,16)

update( move_into!,cr_b,cr_a; ledger_id= replace_ledger(17))

cr_x=reconstruct_location(5)

cache(cr_x)
cr_a=reconstruct_location(5,16)

cr_c=reconstruct_location(3,16)

update( move_into!,cr_c,cr_a; ledger_id= replace_ledger(17))


## Lock Cache repair

update( lock!,cr_a; ledger_id= insert_ledger(41))

update( deactivate!,cr_a; ledger_id= insert_ledger(42) )
update( activate!,cr_a; ledger_id= replace_ledger(42))
cr_x=reconstruct_location(9)
cache(cr_x)
update( set_attribute!,cr_a,Temperature(42u"°C"); ledger_id= insert_ledger(11))
update( set_attribute!,cr_a,Temperature(200u"°C"); ledger_id= replace_ledger(11))
@testset "activity repair only rewrites caches that changed" begin
    room = generate_location(Room,"activity repair room")
    id = location_id(room)
    lock_activity_rows() = nrow(query_db("SELECT 1 FROM CachedLockActivity WHERE LocationID = ?",(id,)))
    off_ledger = upload(deactivate!,room)
    on_ledger = upload(activate!,room)
    cache(reconstruct_location(id)) # active, as of on_ledger

    # a change before the deactivate/activate pair leaves the cached state alone, so no rewrite
    before = lock_activity_rows()
    s1 = get_sequence_id(off_ledger)
    update(deactivate!,reconstruct_location(id,s1-1);ledger_id=insert_ledger(s1))
    @test lock_activity_rows() == before
    @test is_active(reconstruct_activity(id))

    # replacing the activate! with a deactivate! does change it
    s2 = get_sequence_id(on_ledger)
    update(deactivate!,reconstruct_location(id,s2-1);ledger_id=replace_ledger(s2))
    @test !is_active(reconstruct_activity(id))
end
