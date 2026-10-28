# push_location! (src/reconstruction/reconstruction_utils.jl) keeps each location's history sorted by SequenceID, which
# find_most_recent_location binary-searches. A recursive reconstruct_contents bootstraps a location at an earlier
# sequence point after its caller recorded a stub for it at a later one.

@testset "push_location! keeps each history sorted" begin
    index = Dict{Integer,Vector{Tuple{Integer,Location}}}()
    well = generate_location(WP96,"order plate")[1,1]
    stub,boot,later = deepcopy(well),deepcopy(well),deepcopy(well)
    CHESSDatabase.push_location!(index,43,26,stub)
    CHESSDatabase.push_location!(index,43,20,boot)        # older than the last entry
    @test map(first,index[43]) == [20,26]
    @test CHESSDatabase.find_most_recent_location(index,43,25) === boot       # was nothing: the vector was [26, 20]
    @test CHESSDatabase.find_most_recent_location(index,43,26) === stub
    @test isnothing(CHESSDatabase.find_most_recent_location(index,43,19))
    CHESSDatabase.push_location!(index,43,26,later)       # equal sequence: after the entries already there
    @test CHESSDatabase.find_most_recent_location(index,43,26) === later
    @test CHESSDatabase.find_most_recent_location(index,43) === later
    CHESSDatabase.push_location!(index,43,30,stub)        # the usual append
    @test map(first,index[43]) == [20,26,26,30]
end
