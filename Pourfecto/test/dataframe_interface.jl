srcs1_vc = CSV.read("test_stocks/sources1_vc.csv",DataFrame)
srcs1_vc_units = CSV.read("test_stocks/sources1_vc_units.csv",DataFrame)
srcs1_q = CSV.read("test_stocks/sources1_q.csv",DataFrame)
srcs1_q_units = CSV.read("test_stocks/sources1_q_units.csv",DataFrame)

tgts1_vc = CSV.read("test_stocks/targets1_vc.csv",DataFrame)
tgts1_vc_units = CSV.read("test_stocks/targets1_vc_units.csv",DataFrame)


srcs1_lvc = CSV.read("test_stocks/sources1_lvc.csv",DataFrame) 
srcs1_lvc_units = CSV.read("test_stocks/sources1_lvc_units.csv",DataFrame)

@testset "DataFrame Interface" begin


    @testset "Stock Conversion" begin
        @test vc_to_stock(srcs1_vc,srcs1_vc_units) == df_to_stock(srcs1_vc,srcs1_vc_units) # check that df to stock recognizes vc format 
        @test q_to_stock(srcs1_q,srcs1_q_units) == df_to_stock(srcs1_q,srcs1_q_units) # check that df to stock recognizes q format 
        @test_throws Exception q_to_stock(srcs1_vc,srcs1_vc_units)
        @test_throws Exception vc_to_stock(srcs1_q,srcs1_q_units)
        @test all(isapprox.(q_to_stock(vc_to_q(srcs1_vc,srcs1_vc_units)...),vc_to_stock(srcs1_vc,srcs1_vc_units)))
        @test all(isapprox.(vc_to_stock(q_to_vc(srcs1_q,srcs1_q_units)...),q_to_stock(srcs1_q,srcs1_q_units)))
    end


    @testset "Well Conversion" begin 
        @test well_to_cartesian("A1") == CartesianIndex(1,1)
        @test well_to_cartesian("J16") == CartesianIndex(10,16)
        @test well_to_cartesian("ZY10") == CartesianIndex(701,10) # bijective base-26 row naming is unbounded -- "ZY" (701) is a valid row now, unlike the old 52-row-capped scheme
        @test_throws DomainError well_to_cartesian("a1") # lowercase row letters are still rejected
        @test_throws ArgumentError well_to_cartesian("1")
        @test_throws ArgumentError well_to_cartesian("")
        @test cartesian_to_well(CartesianIndex(1,1)) == "A1"
        @test cartesian_to_well(CartesianIndex(10,16)) == "J16"
        @test ("E5" |> well_to_cartesian |> cartesian_to_well) == "E5"
    end 


    @testset "Labware Conversion" begin
        @test df_to_labware(srcs1_lvc,srcs1_lvc_units) isa Vector{<:Labware} 
        @test labware_to_df(df_to_labware(srcs1_lvc,srcs1_lvc_units)) isa Tuple{DataFrame,DataFrame}
    end 

end
