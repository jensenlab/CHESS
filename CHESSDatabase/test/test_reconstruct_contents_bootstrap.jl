# Regression test for a `reconstruct_contents` bootstrap bug: reconstructing a well used to crash
# (or, in busier scenarios, silently return the wrong stock) whenever an ancestor location's real
# cached content was recorded *earlier* than the target well's own creation-time cache checkpoint --
# see `fetch_content_cache` in ../src/reconstruction/reconstruct_contents.jl.
#
# Runs against the shared database/connection `build_test_database.jl` already set up (new locations
# here get fresh IDs via `generate_location`, so no collision with that file's fixtures) -- same
# pattern `test_cache_repair.jl` uses.

rcb_lab = generate_location(Lab,"rcb lab")
rcb_room = generate_location(Room,"rcb room")
upload(move_into!,rcb_lab,rcb_room)

rcb_bottle = generate_location(Bottle1L,"rcb source bottle")
upload(move_into!,rcb_room,rcb_bottle)
rcb_source_well = rcb_bottle[1,1]
deposit!(rcb_source_well,500u"mL"*rgt"water",1)
cache(rcb_source_well)  # cached NOW, before the target well below is ever created

# The target well is created (and auto-cached as Empty by `generate_location`) strictly *after*
# `rcb_source_well`'s real cache above -- the exact ordering that used to make the source's real
# content invisible to `reconstruct_contents`'s ancestor bootstrap.
rcb_plate = generate_location(WP96,"rcb target plate")
upload(move_into!,rcb_room,rcb_plate)
rcb_target_well = rcb_plate[1,1]

upload(transfer!,rcb_source_well,rcb_target_well,50u"µL")  # WP96's Well200 sockets cap at 200 µL

@testset "reconstruct_contents bootstraps an ancestor cached before the target existed" begin
    rcb_result = reconstruct_location(location_id(rcb_target_well))
    rcb_stock = stock(rcb_result)
    @test !(rcb_stock isa Empty)
    @test quantity(rcb_stock) ≈ 50u"µL"
end
