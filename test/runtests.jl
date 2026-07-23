using CHESS, Test

@testset "CHESS re-exports CHESSCore/CHESSDatabase/CHESSLabConstants" begin
    # CHESSCore's own (real) exports come through directly
    @test CHESS.LocationKind isa DataType
    @test CHESS.Liquid isa DataType

    # CHESSDatabase's exports come through directly
    @test isdefined(CHESS,:upload)

    # CHESSLabConstants intentionally exports very little (see the namespace-hygiene work in
    # earlier plans) -- its constants are reached by qualifying through the reexported submodule
    @test CHESS.CHESSLabConstants.water isa CHESSCore.Liquid
    @test CHESS.CHESSLabConstants.WP96 isa CHESSCore.LocationKind

    # the collision-safe string macros (@loc_str/@stock_str/etc.) and registry_summary are real
    # CHESSCore exports, so they come through CHESS directly too
    @test isdefined(CHESS,Symbol("@stock_str"))
    @test CHESS.registry_summary === CHESSCore.registry_summary
end

@testset "CHESS reexports Unitful -- no separate `using Unitful` needed" begin
    @test 5u"g" isa Unitful.Quantity
    @test uconvert(u"kg",5u"g") == (1//200)u"kg"
    loc = GenericLocation(nothing,"loc",CHESS.CHESSLabConstants.Room)
    @test set_attribute!(loc,CHESS.CHESSLabConstants.Temperature(20u"°C")) === nothing
end

@testset "bare `parent` works with nothing but `using CHESS` -- no AbstractTrees needed" begin
    @test parent === Base.parent # not shadowed/ambiguous against AbstractTrees.parent
    root = GenericLocation(nothing,"root",CHESS.CHESSLabConstants.Room)
    child = GenericLocation(nothing,"child",CHESS.CHESSLabConstants.Shelf)
    move_into!(root,child)
    @test parent(root) === nothing
    @test parent(child) === root
end
