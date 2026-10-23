# A reagent's stored Type must not depend on which names the writing process has loaded into Main.
@testset "reagent Type is independent of Main" begin
    script = """
    using CHESSDatabase, CHESSLabConstants, Unitful
    import CHESSCore
    path = joinpath(mktempdir(), "lab.db"); create_db(path); connect_SQLite(path)
    bottle = generate_location(CHESSLabConstants.Bottle1L, "b")
    observe(bottle[1,1], CHESSLabConstants.HCl, 0.5u"L")
    types = CHESSDatabase.query_db("SELECT Type FROM Reagents")[:,1]
    @assert !isempty(types) && all(t -> !occursin('.', t), types) types
    reconstruct_location(CHESSCore.location_id(bottle[1,1]))
    """
    proj = dirname(Base.active_project())
    @test success(run(ignorestatus(`$(Base.julia_cmd()) --project=$proj -e $script`)))
end
