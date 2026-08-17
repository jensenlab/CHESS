using Test , PlateArrays, DataFrames, JSON, Random

import PlateArrays: OccupancyError,margins,expected_LHS,neighbors, hybrid, minimax, LHS, exchange, MILP
import PlateArrays: letter_code, wellnames, alphabet_code, manhattan_distance, neighboring_ring,
    distance_score_ring, distance_score_brute, scale, distance_to_edge, partition, bound_plates,
    assign_plates, Plots
import PlateArrays: raise_platearray, lower_bitmatrix, raise_bitmatrix, TYPEKEY

using HiGHS
PlateArrays._default_optimizer[] = HiGHS.Optimizer

@testset "Construction" begin
    @test isa(PlateArray(trues(8,12),falses(8,12),falses(8,12)),PlateArray)
    @test isa(PlateArray(trues(16,24),falses(16,24),falses(16,24)),PlateArray)
    @test_throws DimensionMismatch PlateArray(trues(8,12),falses(16,24),falses(8,12))
    x=falses(8,12)
    x[1,1]=true
    @test_throws OccupancyError PlateArray(trues(8,12),x,x)
    x=trues(8,12)
    x[1,1]=false 
    y=falses(8,12)
    y[1,1]=true
    @test_throws OccupancyError PlateArray(x,y,falses(8,12))
    @test_throws OccupancyError PlateArray(x,falses(8,12),y)
    @test DataFrame(PlateArray(trues(8,12),falses(8,12),falses(8,12))) isa DataFrame
    @test PlateArray(DataFrame(PlateArray(trues(8,12),falses(8,12),falses(8,12)))) == PlateArray(trues(8,12),falses(8,12),falses(8,12))
    @test size(PlateArray(trues(8,12),falses(8,12),falses(8,12))) == size(trues(8,12))
    p = PlateArray(trues(8,12),falses(8,12),falses(8,12))
    df = DataFrame(p) 
    df.extra .= "example_extra_data"
    @test p == PlateArray(df)
    @test_throws ErrorException PlateArray(DataFrame(a=[1,2],b=[3,4]))
end

@testset "run_index" begin
    w = trues(2,2)
    p = PlateArray(w,falses(2,2),falses(2,2))
    @test all(ismissing,p.run_index)

    valid = reshape(Union{Missing,Int}[1,2,3,4],2,2)
    @test PlateArray(w,falses(2,2),falses(2,2),valid) isa PlateArray

    # a non-1-starting distinct-positive range is also valid -- this is exactly what a plate holding one
    # slice of a larger multi-plate experiment needs (see the "arrayer multi-plate run_index" testset)
    offset_range = reshape(Union{Missing,Int}[5,6,7,8],2,2)
    @test PlateArray(w,falses(2,2),falses(2,2),offset_range) isa PlateArray

    pos = falses(2,2); pos[1,1]=true
    index_on_control = reshape(Union{Missing,Int}[1,missing,2,3],2,2) # index at [1,1], now a control well
    @test_throws RunIndexError PlateArray(w,pos,falses(2,2),index_on_control)

    partial = reshape(Union{Missing,Int}[1,2,3,missing],2,2)
    @test_throws RunIndexError PlateArray(w,falses(2,2),falses(2,2),partial)

    duplicated = reshape(Union{Missing,Int}[1,1,1,1],2,2)
    @test_throws RunIndexError PlateArray(w,falses(2,2),falses(2,2),duplicated)

    non_positive = reshape(Union{Missing,Int}[0,1,2,3],2,2)
    @test_throws RunIndexError PlateArray(w,falses(2,2),falses(2,2),non_positive)

    ordered = assign_run_index(p;run_order="ordered")
    @test ordered.run_index == reshape(Union{Missing,Int}[1,2,3,4],2,2)

    random1 = assign_run_index(p;run_order="random",rng=Xoshiro(1))
    random2 = assign_run_index(p;run_order="random",rng=Xoshiro(1))
    @test random1 == random2
    @test sort(collect(skipmissing(random1.run_index))) == [1,2,3,4]

    @test_throws ArgumentError assign_run_index(p;run_order="bogus")

    explicit = assign_run_index(p;indices=[5,6,7,8])
    @test explicit.run_index == reshape(Union{Missing,Int}[5,6,7,8],2,2)
    @test_throws ArgumentError assign_run_index(p;indices=[1,2,3]) # wrong length

    indexed = assign_run_index(p)
    df = DataFrame(indexed)
    @test "run_index" in names(df)
    @test indexed == PlateArray(df)

    df_no_idx = select(df, Not(:run_index))
    reconstructed = PlateArray(df_no_idx)
    @test all(ismissing, reconstructed.run_index)

    @test json_to_platearray(platearray_to_json(indexed)) == indexed
end


wells=trues(8,12)
wells[1:4,1].=false
wells[:,12].=false

pos=falses(8,12)
pos[2,2]=true
pos[3,8]=true
pos[5,1]=true
pos[4,6]=true
pos[5,5]=true
pos[6,3]=true
pos[6,8]=true
pos[7,4]=true
neg=falses(8,12)
neg[2,4]=true
neg[3,5]=true
neg[4,2]=true
neg[4,8]=true
neg[5,2]=true
neg[6,6]=true
neg[8,7]=true
neg[4,10]=true

plate=PlateArray(wells,pos,neg)

@testset "ScoringTests" begin
    
    @test margins(wells) == ([10, 10, 10, 10, 11, 11, 11, 11], [4, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0])
    @test LHS(plate) ≈ 18.31746031746031
    @test neighbors(4,4,8,12) ==  [(3, 4),(5, 4),(4, 5),(4, 3)]
    @test minimax(plate) ==322
    @test hybrid(plate;lambda=0.5) ≈ LHS(plate)/2 + minimax(plate)/2
    @test hybrid(plate;lambda=0) ≈ LHS(plate)
    @test hybrid(plate; lambda=1) ≈ minimax(plate)
    
end

@testset "place_controls" begin
    pc_default = place_controls(trues(8,12),8,8)
    @test pc_default isa PlateArray
    @test sort(collect(skipmissing(pc_default.run_index))) == collect(1:80)
    @test place_controls(trues(8,12),8,8,solver="MILP",timelimit=10) isa PlateArray
    @test place_controls(trues(8,12),8,8,objective="LHS") isa PlateArray
    @test place_controls(trues(8,12),8,8,objective="minimax") isa PlateArray
    @test place_controls(plate) isa PlateArray
    @test place_controls(trues(8,12), Experiment(0,8,8)) isa PlateArray

    pc_random = place_controls(trues(8,12),8,8;restarts=1,iterations=50,run_order="random",rng=Xoshiro(1))
    @test sort(collect(skipmissing(pc_random.run_index))) == collect(1:80)
    @test_throws ArgumentError place_controls(trues(8,12),8,8;run_order="bogus")
end

@testset "Experiment" begin
    e = Experiment(10,2,2)
    @test e isa Experiment
    @test e isa Expt
    @test (e.runs, e.positive_controls, e.negative_controls) == (10,2,2)
    @test_throws DomainError Experiment(-1,2,2)
    @test_throws DomainError Experiment(10,-1,2)
    @test_throws DomainError Experiment(10,2,-1)
end

@testset "utils" begin
    rp = random_platearray(trues(8,12),8,8)
    @test rp isa PlateArray
    @test sum(rp.positives) == 8
    @test sum(rp.negatives) == 8
    @test active_indices(trues(2,2)) == [1,2,3,4]
    w = trues(2,2)
    w[1,1] = false
    @test active_indices(w) == [2,3,4]
    @test runs(plate) == (plate.wells .&& .!plate.positives .&& .!plate.negatives)
    @test sum(runs(plate)) == 68
    @test letter_code(1) == "A"
    @test letter_code(26) == "Z"
    @test letter_code(27) == "AA"
    @test alphabet_code(1) == "A"
    wn = wellnames(plate)
    @test size(wn) == size(plate.wells)
    @test wn[1,1] == "A1"
end

@testset "exchange solver branches" begin
    @test exchange(trues(8,12),8,8;objective=minimax,minimize=true,restarts=1,iterations=50) isa PlateArray
    @test exchange(trues(8,12),8,8;objective=minimax,minimize=false,restarts=1,iterations=50) isa PlateArray
    @test exchange(trues(8,12),8,8;objective=LHS,minimize=true,restarts=1,iterations=50) isa PlateArray
    @test exchange(trues(8,12),8,8;objective=hybrid,minimize=true,restarts=1,iterations=50) isa PlateArray
    @test exchange(trues(8,12),8,8;objective=hybrid,minimize=true,restarts=1,iterations=50,lambda=0.25) isa PlateArray
end

@testset "MILP solver branches" begin
    @test MILP(trues(4,4),2,2;objective=minimax,minimize=true,timelimit=10) isa PlateArray
    @test MILP(trues(4,4),2,2;objective=minimax,minimize=false,timelimit=10) isa PlateArray
    @test_throws ArgumentError MILP(trues(4,4),2,2;objective=x->0,timelimit=10)
end

@testset "objectives internals" begin
    e_p_rows,e_p_cols,e_n_rows,e_n_cols = expected_LHS(plate)
    @test length(e_p_rows) == 8
    @test length(e_p_cols) == 12
    @test length(e_n_rows) == 8
    @test length(e_n_cols) == 12
    @test manhattan_distance((0,0),(3,4)) == 7
    @test neighboring_ring(4,4,0,8,12) == [(4,4)]
    @test Set(neighboring_ring(4,4,1,8,12)) == Set([(4,4),(3,4),(5,4),(4,5),(4,3)])
    @test distance_score_brute(plate) == minimax(plate)
    @test distance_score_ring(plate) isa Real
    @test scale(5,0,10) == 0.5
    no_pos = PlateArray(plate.wells,falses(8,12),plate.negatives)
    no_neg = PlateArray(plate.wells,plate.positives,falses(8,12))
    @test distance_score_brute(no_pos) isa Real
    @test distance_score_brute(no_neg) isa Real
end

@testset "partition" begin
    w = trues(4,4)
    parts = partition(w,4,4)
    @test length(parts) == 2
    @test all(size(p) == size(w) for p in parts)
    @test sum(sum(p) for p in parts) == 8
    @test all(all(p .<= w) for p in parts)
    @test maximum(distance_to_edge(3,3)) == 1
    @test_throws ArgumentError partition(trues(2,2),3,3)
end

@testset "assign_plates and bound_plates" begin
    wells = trues(4,6)
    expts = (Experiment(10,2,2), Experiment(8,2,2))
    @test bound_plates(wells,expts...) isa Int
    @test bound_plates(wells,expts...) >= 1
    assignment = assign_plates(wells,expts...)
    @test size(assignment,1) == length(expts)
    @test all(assignment .>= 0)
    @test sum(assignment) >= sum(e.runs for e in expts)
    @test_throws ArgumentError bound_plates(trues(4,6), Experiment(5,12,12))
end

@testset "arrayer" begin
    wells = trues(4,6)
    e1 = Experiment(6,2,2)
    e2 = Experiment(4,2,2)
    arrays = arrayer(wells,e1,e2)
    @test size(arrays,1) == 2
    @test all(pa -> pa isa PlateArray, arrays)
    @test all(pa -> size(pa) == size(wells), arrays)
    @test sum(sum(runs(pa)) for pa in arrays) == e1.runs + e2.runs
    for pa in arrays
        n = sum(runs(pa))
        if n > 0
            @test sort(collect(skipmissing(pa.run_index))) == collect(1:n)
        else
            @test all(ismissing,pa.run_index)
        end
    end

    # a small third experiment that doesn't need every plate, to exercise the
    # zero-assignment (experiment absent from a given plate) branch
    e3 = Experiment(2,1,1)
    arrays3 = arrayer(wells,e1,e2,e3)
    @test size(arrays3,1) == 3
    @test sum(sum(runs(pa)) for pa in arrays3) == e1.runs + e2.runs + e3.runs
end

@testset "arrayer multi-plate run_index" begin
    # a single experiment too big for one plate (10 runs + 2 controls on an 8-well plate) forces
    # assign_plates to split it across >=2 plates -- each plate must carry a distinct slice of
    # 1:total_runs, not its own independent 1:N restarting from 1 (the bug that was reported)
    wells = trues(2,4)
    e = Experiment(10,1,1)

    arrays = arrayer(wells,e)
    all_indices = Int[]
    for pa in arrays
        n = sum(runs(pa))
        vals = collect(skipmissing(pa.run_index))
        @test length(vals) == n
        append!(all_indices,vals)
    end
    @test sort(all_indices) == collect(1:e.runs)
    @test length(unique(all_indices)) == length(all_indices) # no duplicates across plates
    @test size(arrays,2) >= 2 # confirms the split actually happened

    arrays_random = arrayer(wells,e;run_order="random",rng=Xoshiro(1))
    all_random = Int[]
    for pa in arrays_random
        append!(all_random,collect(skipmissing(pa.run_index)))
    end
    @test sort(all_random) == collect(1:e.runs)
    @test length(unique(all_random)) == length(all_random)
end

@testset "visualization" begin
    @test plot(plate) isa Plots.Plot
    @test_throws ErrorException plot(plate;k=1.5)

    w1 = falses(2,5); w1[:,1:2] .= true # column 5 stays inactive on both designs
    w2 = falses(2,5); w2[:,3:4] .= true
    pos1 = falses(2,5); pos1[1,1] = true
    neg1 = falses(2,5); neg1[2,1] = true
    pos2 = falses(2,5); pos2[1,3] = true
    neg2 = falses(2,5); neg2[2,3] = true
    d1 = PlateArray(w1,pos1,neg1)
    d2 = PlateArray(w2,pos2,neg2)
    designs = [d1,d2]
    @test plot(designs) isa Plots.Plot
    @test_throws ErrorException plot([d1, PlateArray(trues(2,2),falses(2,2),falses(2,2))]) # mismatched shapes
    @test_throws ErrorException plot([d1,d1]) # overlapping designs
    @test_throws ErrorException plot(designs; runs=["blue"]) # not enough colors

    designs_matrix = [d1 d1; d2 d2]
    plots = plot(designs_matrix)
    @test length(plots) == size(designs_matrix,2)
    @test all(p -> p isa Plots.Plot, plots)
end

@testset "JSON interface" begin
    @test json_to_platearray(platearray_to_json(plate)) == plate

    m = trues(2,3); m[1,2] = false
    @test raise_bitmatrix(JSON.parse(JSON.json(lower_bitmatrix(m)))) == m

    bad = JSON.parse(JSON.json(Dict(TYPEKEY=>"NotABitMatrix","size"=>[2,2],"data"=>[true,false,true,false])))
    @test_throws ErrorException raise_bitmatrix(bad)

    bad_pa = JSON.parse(JSON.json(Dict(TYPEKEY=>"NotAPlateArray")))
    @test_throws ErrorException raise_platearray(bad_pa)

    pos_json = lower_bitmatrix(plate.positives)
    overlapping = JSON.parse(JSON.json(Dict(TYPEKEY=>"PlateArray",
        "wells"=>lower_bitmatrix(plate.wells), "positives"=>pos_json, "negatives"=>pos_json)))
    @test_throws OccupancyError raise_platearray(overlapping)
end

@testset "Reproducibility" begin
    @test random_platearray(trues(8,12),8,8;rng=Xoshiro(1)) == random_platearray(trues(8,12),8,8;rng=Xoshiro(1))

    @test exchange(trues(8,12),8,8;restarts=1,iterations=50,rng=Xoshiro(1)) ==
          exchange(trues(8,12),8,8;restarts=1,iterations=50,rng=Xoshiro(1))

    @test MILP(trues(4,4),2,2;objective=hybrid,timelimit=10,rng=Xoshiro(1)) ==
          MILP(trues(4,4),2,2;objective=hybrid,timelimit=10,rng=Xoshiro(1))
end


