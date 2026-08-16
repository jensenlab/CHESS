# Regression test for two bugs found while investigating reconstruct_contents's correctness (see
# ../src/reconstruction/reconstruct_contents.jl and siblings): every `encumbrances=true`
# reconstruction was broken outright by SQL typos, in two distinct ways --
#
#   Bug C: each reconstruction file's encumbrance-aware "cache fetcher" query re-aliases the
#   `encumbrance_subset (EncumbranceID)` CTE as `e` a second time and tried to `SELECT e.ID` --
#   but that CTE only exposes a column named `EncumbranceID`, not `ID`. Fixed in
#   get_content_caches/get_attribute_caches/get_child_caches/get_activity_caches/get_lock_caches/
#   get_parent_caches by selecting `e.EncumbranceID` instead.
#
#   Bug D: the encumbrance-aware "history" queries for activity and locks referenced columns that
#   don't exist on their source tables -- `EncumberedActivity.IsActive` (real column: `Activate`)
#   and `EncumberedLocks.IsLocked` (real column: `Lock`). Fixed in get_activity/get_locks.
#
# Nothing previously exercised `encumbrances=true` reconstruction at all, which is why these went
# unnoticed. This reuses the encumbrances build_test_database.jl already sets up on `plate1` (move,
# lock, activity), `w1`/`w2` (transfer), and `jensen_lab` (environment attribute) under
# `protocol1_id` -- see build_test_database.jl's "protocol1_id"/"enc_*" section -- rather than
# building a fresh protocol, since that fixture already covers every affected query.

@testset "encumbrances=true reconstruction runs without the Bug C/D SQL errors" begin
    # Bug C: content-cache (via w1's transfer encumbrance) and lock/activity/parent/child caches
    # (via plate1's move/lock/activity encumbrances) all go through a "cache fetcher" query.
    @test reconstruct_location(location_id(w1); encumbrances=true) isa Location
    @test reconstruct_location(location_id(plate1); encumbrances=true) isa Location

    # Bug D: plate1's lock/activity encumbrances also exercise the "history" queries
    # (get_locks/get_activity) once encumbrances are enforced up through get_encumbrance_status'
    # completion tracking -- reconstructing plate1 above already replays both without error.

    # Bug C again, environment/attribute cache path, via jensen_lab's environment encumbrance.
    @test reconstruct_location(location_id(jensen_lab); encumbrances=true) isa Location
end
