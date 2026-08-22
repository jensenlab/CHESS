using Test, CHESSProcessing, CHESSExperiments, RunMaps, PlateMaps, CHESSParsers, CHESSCore, CHESSLabConstants,
    DataFrames, Dates, Statistics, Unitful, GaussianProcesses

const NO_PLATES = Pair{String,PlateMap{Int}}[]

function toy_experiment(n::Int=3)
    Experiment(DataFrame(treatment=1:n))
end

@testset "combine_group" begin
    @test combine_group([1.0, 2.0, 3.0], mean; on_missing=:error) == 2.0
    @test combine_group([missing, missing], mean; on_missing=:error) === missing
    @test_throws ArgumentError combine_group([1.0, missing, 3.0], mean; on_missing=:error)
    @test combine_group([1.0, missing, 3.0], mean; on_missing=:skip) == 2.0
    @test combine_group([1.0, missing, 3.0], mean; on_missing=:propagate) === missing
    @test_throws ArgumentError combine_group([1.0], mean; on_missing=:bogus)
end

@testset "records: append_record / processing_log" begin
    experiment = toy_experiment()
    @test processing_log(experiment) == ProcessingRecord[]

    experiment2 = append_record(experiment, :aggregate, Dict(:relation => :duplicate), Dict(1 => 1.0))
    @test length(processing_log(experiment2)) == 1
    @test processing_log(experiment2)[1].operation === :aggregate
    @test processing_log(experiment2)[1].values == Dict(1 => 1.0)

    # copy-on-write: original untouched
    @test processing_log(experiment) == ProcessingRecord[]

    experiment3 = append_record(experiment2, :normalize, Dict(:relations => [:positive]), Dict(1 => 0.5); upstream=[1])
    @test length(processing_log(experiment3)) == 2
    @test processing_log(experiment3)[2].upstream == [1]
end

@testset "aggregate: basic duplicate collapse" begin
    rm = RunMap{Int}()
    link!(rm, 1, 10, :duplicate)
    link!(rm, 1, 11, :duplicate)
    add_run!(rm, 2) # no duplicates scheduled

    values = Dict{Int,Union{Missing,Float64}}(10 => 2.0, 11 => 4.0, 2 => 7.0)
    experiment, out = aggregate(toy_experiment(2), rm, NO_PLATES, values; relation=:duplicate, fn=mean)

    @test out[1] == 3.0          # mean of its duplicates
    @test out[2] == 7.0          # no duplicates -> passthrough of its own value
    @test length(processing_log(experiment)) == 1
    @test processing_log(experiment)[1].operation === :aggregate
end

@testset "aggregate: whole-group missing produces missing, not an error" begin
    rm = RunMap{Int}()
    link!(rm, 1, 10, :duplicate)
    link!(rm, 1, 11, :duplicate)

    values = Dict{Int,Union{Missing,Float64}}(10 => missing, 11 => missing)
    _, out = aggregate(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, fn=mean)
    @test out[1] === missing
end

@testset "aggregate: on_missing policies for a partially-missing group" begin
    rm = RunMap{Int}()
    link!(rm, 1, 10, :duplicate)
    link!(rm, 1, 11, :duplicate)
    values = Dict{Int,Union{Missing,Float64}}(10 => 2.0, 11 => missing)

    @test_throws ArgumentError aggregate(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, fn=mean, on_missing=:error)

    _, out_skip = aggregate(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, fn=mean, on_missing=:skip)
    @test out_skip[1] == 2.0

    _, out_prop = aggregate(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, fn=mean, on_missing=:propagate)
    @test out_prop[1] === missing
end

@testset "aggregate: anchor nodes are not run-typed -- a control can be an anchor too" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :positive)        # run 1's control
    link!(rm, 100, 101, :duplicate)     # the control's own replicates
    link!(rm, 100, 102, :duplicate)

    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 10.0, 101 => 12.0, 102 => 14.0)
    _, out = aggregate(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, fn=mean)

    @test out[100] == 13.0  # control node collapsed as an anchor, same as any other node
    @test out[1] == 5.0     # run 1 has no :duplicate edges -> passthrough
end

@testset "aggregate: explicit nodes keyword scopes which anchors are processed" begin
    rm = RunMap{Int}()
    link!(rm, 1, 10, :duplicate)
    link!(rm, 2, 20, :duplicate)
    values = Dict{Int,Union{Missing,Float64}}(10 => 1.0, 20 => 2.0)

    _, out = aggregate(toy_experiment(2), rm, NO_PLATES, values; relation=:duplicate, fn=mean, nodes=[1])
    @test out == Dict(1 => 1.0)
end

@testset "normalize: subtract_and_normalize against positive/negative controls" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :positive)
    link!(rm, 1, 200, :negative)

    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 10.0, 200 => 0.0)
    experiment, out = normalize(toy_experiment(1), rm, NO_PLATES, values; fn=subtract_and_normalize)

    @test out[1] == 0.5  # (5 - 0) / (10 - 0)
    @test length(processing_log(experiment)) == 1
    @test processing_log(experiment)[1].operation === :normalize
end

@testset "normalize: multiple controls per relation are combined first" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :positive)
    link!(rm, 1, 101, :positive) # two distinct positive controls
    link!(rm, 1, 200, :negative)

    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 8.0, 101 => 12.0, 200 => 0.0)
    _, out = normalize(toy_experiment(1), rm, NO_PLATES, values; fn=subtract_and_normalize)

    @test out[1] == 0.5  # (5 - 0) / (mean(8,12)=10 - 0)
end

@testset "normalize: own value missing short-circuits to missing without calling fn" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :positive)
    link!(rm, 1, 200, :negative)

    values = Dict{Int,Union{Missing,Float64}}(1 => missing, 100 => 10.0, 200 => 0.0)
    _, out = normalize(toy_experiment(1), rm, NO_PLATES, values; fn=(own, g) -> error("fn should not be called"), nodes=[1])
    @test out[1] === missing
end

@testset "normalize: a fully-missing relation group propagates missing through fn" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :positive)
    add_run!(rm, 1) # no :negative edges at all

    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 10.0)
    _, out = normalize(toy_experiment(1), rm, NO_PLATES, values; fn=subtract_and_normalize)
    @test out[1] === missing # groups[:negative] is missing -> arithmetic propagates missing
end

@testset "normalize: custom relations and a three-way fn" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :blank)

    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 2.0)
    _, out = normalize(toy_experiment(1), rm, NO_PLATES, values; relations=[:blank], fn=(own, g) -> own - g[:blank])
    @test out[1] == 3.0
end

@testset "cv_threshold" begin
    rule = cv_threshold(0.1)
    @test rule([10.0, 10.0, 10.0]) === true    # cv == 0
    @test rule([1.0, 100.0]) === false          # huge spread
    @test rule([10.0]) === missing              # need >= 2 points
    @test rule([0.0, 0.0]) === missing          # mean == 0, cv undefined
    @test rule([missing, 10.0, 10.0]) === true  # missing entries dropped first
end

@testset "flag: is a null operation on values, judgment goes only to the record" begin
    rm = RunMap{Int}()
    link!(rm, 1, 100, :duplicate)
    link!(rm, 1, 101, :duplicate)
    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 100 => 10.0, 101 => 10.4)

    experiment, out = flag(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, rule=cv_threshold(0.1), nodes=[1])

    @test out === values # returned untouched -- not even a copy
    @test length(processing_log(experiment)) == 1
    record = processing_log(experiment)[1]
    @test record.operation === :flag
    @test record.values[1] === true # judgment lives on the record, not in `out`
end

@testset "flag: no linked group -> missing judgment" begin
    rm = RunMap{Int}()
    add_run!(rm, 1)
    values = Dict{Int,Union{Missing,Float64}}(1 => 5.0)

    experiment, _ = flag(toy_experiment(1), rm, NO_PLATES, values; relation=:duplicate, rule=cv_threshold(0.1))
    @test processing_log(experiment)[1].values[1] === missing
end

@testset "end-to-end: chained operations compose regardless of order" begin
    rm = RunMap{Int}()
    link!(rm, 1, 10, :duplicate)
    link!(rm, 1, 11, :duplicate)
    link!(rm, 1, 100, :positive)
    link!(rm, 1, 200, :negative)

    values = Dict{Int,Union{Missing,Float64}}(10 => 4.0, 11 => 6.0, 100 => 10.0, 200 => 0.0)

    # canonical order: aggregate -> normalize -> flag (default nodes=all, so control values
    # like 100/200 pass through aggregate untouched and remain available to normalize)
    experiment = toy_experiment(1)
    experiment, v1 = aggregate(experiment, rm, NO_PLATES, values; relation=:duplicate, fn=mean)
    experiment, v2 = normalize(experiment, rm, NO_PLATES, v1; fn=subtract_and_normalize)
    experiment, v3 = flag(experiment, rm, NO_PLATES, v2; relation=:duplicate, rule=cv_threshold(0.5))

    @test v1[1] == 5.0        # mean(4,6)
    @test v2[1] == 0.5        # (5-0)/(10-0)
    @test v3 === v2           # flag is a no-op on values
    @test length(processing_log(experiment)) == 3
    @test [r.operation for r in processing_log(experiment)] == [:aggregate, :normalize, :flag]

    # reordered/skipped: normalize fed directly from raw resolved values, aggregate skipped entirely
    raw_values = Dict{Int,Union{Missing,Float64}}(1 => 4.0, 100 => 10.0, 200 => 0.0)
    experiment2 = toy_experiment(1)
    experiment2, w1 = normalize(experiment2, rm, NO_PLATES, raw_values; fn=subtract_and_normalize, nodes=[1])
    @test w1[1] == 0.4         # (4-0)/(10-0), computed without ever calling aggregate
    @test length(processing_log(experiment2)) == 1
end

function toy_plate(occupant::AbstractMatrix)
    wells = trues(size(occupant))
    PlateMap{Int}(wells, occupant)
end

function toy_read(pairs...; read_kind="Absorbance")
    wells = String[p[1] for p in pairs]
    values = Float64[p[2] for p in pairs]
    data = DataFrame(well=wells, time=fill(DateTime(2024, 1, 1), length(wells)), value=values)
    LabwareRead(Dict{String,Any}("read_kind" => read_kind), data)
end

@testset "resolve: basic well -> node assignment" begin
    pm = toy_plate(reshape(Union{Missing,Int}[1, 2], 2, 1)) # A1 -> 1, B1 -> 2
    lr = toy_read("A1" => 1.5, "B1" => 2.5)

    experiment, out = resolve(toy_experiment(2), RunMap{Int}(), ["Plate1" => pm], ["Plate1" => lr])

    @test out[1] == 1.5
    @test out[2] == 2.5
    @test length(processing_log(experiment)) == 1
    @test processing_log(experiment)[1].operation === :resolve
end

@testset "resolve: unread node stays missing, unoccupied well is silently skipped" begin
    pm = toy_plate(reshape(Union{Missing,Int}[1, missing], 2, 1)) # A1 -> 1, B1 unoccupied
    lr = toy_read("A1" => 1.5, "B1" => 9.9) # B1's reading has nowhere to attach

    _, out = resolve(toy_experiment(1), RunMap{Int}(), ["Plate1" => pm], ["Plate1" => lr])
    @test out[1] == 1.5
    @test length(out) == 1 # only the occupied node gets a key at all
end

@testset "resolve: orphan nodes (unregistered in run_map) still resolve" begin
    pm = toy_plate(reshape(Union{Missing,Int}[1, 42], 2, 1)) # 42 is never registered in run_map
    lr = toy_read("A1" => 1.5, "B1" => 3.5)
    rm = RunMap{Int}()
    add_run!(rm, 1) # 42 deliberately not added

    _, out = resolve(toy_experiment(1), rm, ["Plate1" => pm], ["Plate1" => lr])
    @test out[42] == 3.5 # resolve never filters on run_map -- E's resolution
end

@testset "resolve: multiple plates via labeled pairs" begin
    pm1 = toy_plate(reshape(Union{Missing,Int}[1], 1, 1))
    pm2 = toy_plate(reshape(Union{Missing,Int}[2], 1, 1))
    lr1 = toy_read("A1" => 1.1)
    lr2 = toy_read("A1" => 2.2) # same well label, different plate -- must not collide

    _, out = resolve(toy_experiment(2), RunMap{Int}(), ["Plate1" => pm1, "Plate2" => pm2], ["Plate1" => lr1, "Plate2" => lr2])
    @test out[1] == 1.1
    @test out[2] == 2.2
end

@testset "resolve: errors" begin
    pm = toy_plate(reshape(Union{Missing,Int}[1, 2], 2, 1))
    lr = toy_read("A1" => 1.5, "B1" => 2.5)

    @test_throws ArgumentError resolve(toy_experiment(2), RunMap{Int}(), ["Plate1" => pm], ["NoSuchPlate" => lr])

    kinetic = toy_read("A1" => 1.0, "A1" => 2.0) # two rows for the same well
    @test_throws ArgumentError resolve(toy_experiment(2), RunMap{Int}(), ["Plate1" => pm], ["Plate1" => kinetic])

    # two distinct reads both claiming well A1
    lr_dup1 = toy_read("A1" => 1.0)
    lr_dup2 = toy_read("A1" => 2.0)
    @test_throws ArgumentError resolve(toy_experiment(2), RunMap{Int}(), ["Plate1" => pm], ["Plate1" => lr_dup1, "Plate1" => lr_dup2])
end

@testset "full six-operation pipeline: resolve -> aggregate -> normalize -> correct -> flag -> merge" begin
    # A 4x4 plate: run 1 has duplicate wells 5/6; controls at the corners; runs 2-3 unreplicated.
    occ = Matrix{Union{Missing,Int}}(missing, 4, 4)
    occ[1, 1] = 1  # A1: run 1
    occ[2, 1] = 5  # B1: run 1's duplicate
    occ[3, 1] = 6  # C1: run 1's duplicate
    occ[4, 1] = 2  # D1: run 2
    occ[1, 4] = 3  # A4: run 3
    occ[1, 2] = 100 # A2: negative control
    occ[4, 4] = 101 # D4: negative control
    occ[4, 2] = 200 # D2: positive control
    occ[1, 3] = 201 # A3: positive control
    pm = toy_plate(occ)

    rm = RunMap{Int}()
    link!(rm, 1, 5, :duplicate)
    link!(rm, 1, 6, :duplicate)
    add_run!(rm, 2)
    add_run!(rm, 3)
    link!(rm, 1, 100, :negative)
    link!(rm, 2, 100, :negative)
    link!(rm, 3, 101, :negative)
    link!(rm, 1, 200, :positive)
    link!(rm, 2, 200, :positive)
    link!(rm, 3, 201, :positive)

    lr = toy_read(
        "A1" => 5.0, "B1" => 5.2, "C1" => 4.8, "D1" => 6.0, "A4" => 7.0,
        "A2" => 1.0, "D4" => 1.1, "D2" => 10.0, "A3" => 9.9,
    )

    experiment = toy_experiment(3)
    experiment, resolved = resolve(experiment, rm, ["Plate1" => pm], ["Plate1" => lr])
    experiment, aggregated = aggregate(experiment, rm, ["Plate1" => pm], resolved; relation=:duplicate, fn=mean)
    experiment, corrected = correct(experiment, rm, ["Plate1" => pm], aggregated; method=GPCorrection())
    experiment, normalized = normalize(experiment, rm, ["Plate1" => pm], corrected; fn=subtract_and_normalize)
    experiment, _ = flag(experiment, rm, ["Plate1" => pm], resolved; relation=:duplicate, rule=cv_threshold(0.5))
    result = merge(experiment, rm, ["Plate1" => pm], :normalized => normalized)

    @test aggregated[1] == 5.0 # mean(5.0, 5.2, 4.8)
    @test aggregated[2] == 6.0 # run 2 has no duplicates -> passthrough
    @test all(v -> !ismissing(v) && isfinite(v), (corrected[1], corrected[2], corrected[3]))
    @test !ismissing(normalized[1]) && !ismissing(normalized[2]) && !ismissing(normalized[3])
    @test length(processing_log(experiment)) == 5 # resolve, aggregate, correct, normalize, flag
    @test [r.operation for r in processing_log(experiment)] == [:resolve, :aggregate, :correct, :normalize, :flag]

    @test nrow(result) == 3
    @test result.run_index == [1, 2, 3]
    @test all(!ismissing, result.normalized)
    flag_col = only(filter(n -> startswith(string(n), "flag_"), names(result)))
    @test !ismissing(result[!, flag_col][1]) # run 1's duplicate group (5.0,5.2,4.8) got judged
end

@testset "CHESSProcessingCoreExt: resolve from CHESSCore.Labware" begin
    plate = build_location(loc"WP96") # 8x12
    lr = toy_read("A1" => 0.123, "A2" => 0.456; read_kind="Absorbance")
    record_reads!(plate, lr)

    pm = toy_plate(let occ = Matrix{Union{Missing,Int}}(missing, 8, 12)
        occ[1, 1] = 1 # A1
        occ
    end)

    experiment, out = resolve(toy_experiment(1), RunMap{Int}(), ["main" => pm], ["main" => plate]; read_kind=:Absorbance)

    @test Unitful.ustrip(out[1]) == 0.123
    @test length(processing_log(experiment)) == 1
    @test processing_log(experiment)[1].params[:read_kind] === :Absorbance
end

@testset "CHESSProcessingGPExt: GPCorrection" begin
    # 4x4 plate: corners are controls (1,4 = negative; 13,16 = positive), the rest are "run" wells.
    occ = reshape(Union{Missing,Int}[1:16;], 4, 4)
    pm = toy_plate(occ)
    rm = RunMap{Int}()
    link!(rm, 0, 1, :negative)
    link!(rm, 0, 4, :negative)
    link!(rm, 0, 13, :positive)
    link!(rm, 0, 16, :positive)

    raw = Dict{Int,Union{Missing,Float64}}(
        1 => 1.0, 4 => 1.2, 13 => 9.8, 16 => 10.2, # controls, mild noise so std != 0
        [i => 3.0 + 0.1 * i for i in 2:15 if i ∉ (4, 13)]...,
    )

    experiment, out = correct(toy_experiment(1), rm, ["Plate1" => pm], raw; method=GPCorrection())

    @test length(out) == 16
    @test all(v -> !ismissing(v) && isfinite(v), values(out))
    @test length(processing_log(experiment)) == 1
    @test processing_log(experiment)[1].operation === :correct

    @testset "nodes keyword excludes an occupant from the fit and the output" begin
        _, out_scoped = correct(toy_experiment(1), rm, ["Plate1" => pm], raw; method=GPCorrection(), nodes=filter(!=(7), collect(1:16)))
        @test out_scoped[7] === missing
        @test !ismissing(out_scoped[1])
    end

    @testset "a missing raw value is excluded, not an error" begin
        raw2 = copy(raw)
        raw2[7] = missing
        _, out2 = correct(toy_experiment(1), rm, ["Plate1" => pm], raw2; method=GPCorrection())
        @test out2[7] === missing
        @test !ismissing(out2[1])
    end

    @testset "missing role_masks entry throws" begin
        @test_throws ArgumentError correct(toy_experiment(1), rm, ["Plate1" => pm], raw; method=GPCorrection(), relations=[:positive])
    end
end

@testset "merge" begin
    @testset "joins design with labeled values, keyed by run_index" begin
        experiment = toy_experiment(3) # design rows -> nodes 1,2,3
        rm = RunMap{Int}()
        add_run!(rm, 1)
        add_run!(rm, 2)
        add_run!(rm, 3)

        normalized = Dict{Int,Union{Missing,Float64}}(1 => 0.5, 2 => 0.7, 3 => missing)
        aggregated = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 2 => 6.0, 3 => 7.0)

        result = merge(experiment, rm, NO_PLATES, :normalized => normalized, :aggregated => aggregated)

        @test nrow(result) == 3
        @test result.run_index == [1, 2, 3]
        @test result.normalized[1] == 0.5
        @test result.normalized[3] === missing
        @test result.aggregated == [5.0, 6.0, 7.0]
    end

    @testset "a values Dict missing a design row's key becomes missing, not an error" begin
        experiment = toy_experiment(2)
        rm = RunMap{Int}()
        add_run!(rm, 1)
        add_run!(rm, 2)
        partial = Dict{Int,Union{Missing,Float64}}(1 => 9.9) # node 2 absent entirely

        result = merge(experiment, rm, NO_PLATES, :partial => partial)
        @test result.partial[1] == 9.9
        @test result.partial[2] === missing
    end

    @testset "flag records are pulled back from the log, one column per call" begin
        experiment = toy_experiment(2)
        rm = RunMap{Int}()
        link!(rm, 1, 10, :duplicate)
        link!(rm, 1, 11, :duplicate)
        add_run!(rm, 2)

        values = Dict{Int,Union{Missing,Float64}}(1 => 5.0, 2 => 6.0, 10 => 5.0, 11 => 5.1)

        experiment, _ = flag(experiment, rm, NO_PLATES, values; relation=:duplicate, rule=cv_threshold(0.2))
        experiment, _ = flag(experiment, rm, NO_PLATES, values; relation=:duplicate, rule=cv_threshold(0.001)) # a second, stricter call

        result = merge(experiment, rm, NO_PLATES, :raw => values)

        flag_cols = filter(n -> startswith(string(n), "flag_"), names(result))
        @test length(flag_cols) == 2 # two distinct columns, one per flag call
        @test length(unique(flag_cols)) == 2

        col1, col2 = Symbol.(sort(flag_cols))
        @test result[!, col1][1] === true   # cv_threshold(0.2): duplicates 5.0/5.1 pass
        @test result[!, col2][1] === false  # cv_threshold(0.001): same duplicates fail a tight threshold
    end

    @testset "no labeled values -- run_index and any flag columns still present" begin
        experiment = toy_experiment(2)
        rm = RunMap{Int}()
        add_run!(rm, 1)
        add_run!(rm, 2)
        result = merge(experiment, rm, NO_PLATES)
        @test result.run_index == [1, 2]
        @test ncol(result) == ncol(toy_experiment(2).design) + 1 # just design + run_index
    end
end

@testset "CHESSProcessingCoreExt: more than one matching read throws" begin
    plate = build_location(loc"WP96")
    lr = toy_read("A1" => 0.1; read_kind="Absorbance")
    record_reads!(plate, lr)
    record_reads!(plate, toy_read("A1" => 0.2; read_kind="Absorbance")) # second Absorbance read on the same well

    pm = toy_plate(let occ = Matrix{Union{Missing,Int}}(missing, 8, 12)
        occ[1, 1] = 1
        occ
    end)

    @test_throws ArgumentError resolve(toy_experiment(1), RunMap{Int}(), ["main" => pm], ["main" => plate]; read_kind=:Absorbance)
end
