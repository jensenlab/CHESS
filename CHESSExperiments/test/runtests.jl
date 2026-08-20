using Test, CHESSExperiments, PlateMaps, RunMaps, DataFrames, Random

"""
    mock_runmap(n_runs, n_pos, n_neg) -> RunMap

Build a `RunMap` matching what `PlateArrays.PlateArray(wells, positives, negatives)` used to represent:
`n_runs` run nodes (identified `1:n_runs`, the design-row convention `CHESSExperimentsRunMapsExt`
requires), each densely linked to `n_pos` shared `:positive` and `n_neg` shared `:negative` control nodes
-- any run is scored by its nearest control of a role, matching the old plate-wide shared-control-pool
semantics.
"""
function mock_runmap(n_runs::Int, n_pos::Int, n_neg::Int)
    rm = RunMap{Any}()
    for i in 1:n_runs
        add_run!(rm, i)
        for p in 1:n_pos
            link!(rm, i, Symbol("pos$p"), :positive)
        end
        for n in 1:n_neg
            link!(rm, i, Symbol("neg$n"), :negative)
        end
    end
    return rm
end

@testset "Experiment construction" begin
    matrix = DataFrame(carbon_source = ["glucose", "glucose", "acetate"], temperature = [30, 30, 37])
    experiment = Experiment(matrix; name = "growth_curve", metadata = Dict(:incubation_hours => 24))
    @test get_parameter(experiment, :name) == "growth_curve"
    @test experiment.design === matrix
    @test isnothing(layout(experiment))
    @test experiment.metadata[:incubation_hours] == 24

    # replication is structural: the same treatment repeated as multiple rows
    @test nrow(experiment.design) == 3
    @test count(==(("glucose", 30)), zip(experiment.design.carbon_source, experiment.design.temperature)) == 2

    unnamed = Experiment(matrix)
    @test !haskey(unnamed.metadata, :name)
end

@testset "ParameterKind registry" begin
    register_parameter!(:dummy_test_positive_controls, Int; default = 0)
    register_parameter!(:dummy_test_required_param, String)
    register_parameter!(:dummy_test_validated_param, Int; default = 1, validator = x -> x > 0)

    matrix = DataFrame(x = [1])
    expt_default = Experiment(matrix)
    @test get_parameter(expt_default, :dummy_test_positive_controls) == 0

    expt_set = Experiment(matrix; metadata = Dict(:dummy_test_positive_controls => 8))
    @test get_parameter(expt_set, :dummy_test_positive_controls) == 8

    @test_throws ArgumentError get_parameter(expt_default, :dummy_test_required_param)

    expt_wrong_type = Experiment(matrix; metadata = Dict(:dummy_test_positive_controls => "eight"))
    @test_throws ArgumentError get_parameter(expt_wrong_type, :dummy_test_positive_controls)

    expt_bad_validation = Experiment(matrix; metadata = Dict(:dummy_test_validated_param => -1))
    @test_throws ArgumentError get_parameter(expt_bad_validation, :dummy_test_validated_param)
    @test get_parameter(expt_default, :dummy_test_validated_param) == 1 # falls back to default, which passes validation trivially since absent

    @test_throws DuplicateRegistrationError register_parameter!(:dummy_test_positive_controls, Int)
    @test_throws KeyError get_parameter(expt_default, :never_registered)

    # with_parameter: copy-on-write, doesn't require prior registration
    updated = with_parameter(expt_default, :dummy_test_positive_controls, 42)
    @test get_parameter(updated, :dummy_test_positive_controls) == 42
    @test get_parameter(expt_default, :dummy_test_positive_controls) == 0 # original untouched
    updated2 = with_parameter(expt_default, :never_registered_either, "raw value")
    @test updated2.metadata[:never_registered_either] == "raw value"
end

@testset "get_parameter default handling (the bug fix)" begin
    # a DataFrame-typed parameter defaulting to `nothing` must not be type-checked against its own
    # default -- only a value actually present in metadata gets type/validator-checked
    matrix = DataFrame(x = [1])
    expt = Experiment(matrix)
    @test isnothing(get_parameter(expt, :layout)) # :layout is registered by CHESSExperiments itself
    @test isnothing(layout(expt))
end

@testset "QCMethod registry" begin
    struct DummyMethod2 <: QCMethod
        value::Int
    end

    @test register_qc_method!(:dummy_test_method_2, DummyMethod2) === DummyMethod2
    @test qc_method(:dummy_test_method_2) === DummyMethod2
    @test :dummy_test_method_2 in qc_methods()
    @test_throws DuplicateRegistrationError register_qc_method!(:dummy_test_method_2, DummyMethod2)
end

@testset "schedule_layout (via RunMaps/PlateMaps extension)" begin
    matrix = DataFrame(carbon_source = ["glucose", "acetate"])
    experiment = Experiment(matrix; name = "scheduling_test", metadata = Dict(:positive_controls => 1, :negative_controls => 1))

    wells = trues(2, 2)
    rm = mock_runmap(2, 1, 1)
    pm = only(schedule_platemap(wells, rm, (:positive, :negative)))

    scheduled = schedule_layout(experiment, pm, rm; labware = "plate1")
    @test get_parameter(scheduled, :name) == get_parameter(experiment, :name)
    @test scheduled.design === experiment.design
    @test !isnothing(layout(scheduled))

    lay = layout(scheduled)
    @test Set(Symbol.(names(lay))) == Set(CHESSExperiments.LAYOUT_COLUMNS)
    @test count(lay.run) == 2
    @test sort(collect(skipmissing(lay.run_index))) == [1, 2]
    @test all(lay.labware .== "plate1")
    @test all(ismissing, lay.location_id)
    @test all(d -> d isa Dict{Symbol,Any} && isempty(d), lay.metadata)

    bad_experiment = Experiment(DataFrame(x = [1, 2, 3]); name = "mismatched")
    @test_throws ArgumentError schedule_layout(bad_experiment, pm, rm)
end

@testset "run_index tracks node identity regardless of well placement" begin
    # replaces an earlier PlateArrays-era regression test for run_order="random" -- there's no separate
    # ordering to get wrong anymore, since a well's run_index *is* whichever design-row node landed on
    # it. This just confirms that invariant holds across different placements of the same RunMap.
    matrix = DataFrame(x = 1:6)
    experiment = Experiment(matrix; name = "placement_test")

    wells = trues(2, 3)
    rm = mock_runmap(6, 0, 0)

    scheduled_a = schedule_layout(experiment, only(schedule_platemap(wells, rm, Symbol[]; rng = Xoshiro(1))), rm)
    scheduled_b = schedule_layout(experiment, only(schedule_platemap(wells, rm, Symbol[]; rng = Xoshiro(2))), rm)

    for scheduled in (scheduled_a, scheduled_b)
        lay = layout(scheduled)
        @test sort(collect(skipmissing(lay.run_index))) == collect(1:6)
    end
end

@testset "schedule_layout across multiple plates" begin
    # unlike mock_runmap's single shared control pool (one giant connected component, can't split --
    # components are atomic), a real multi-plate schedule needs each plate's own dedicated controls, since
    # a physical control well can't be shared across separate physical plates. schedule_uniform_controls
    # gives every capacity-bounded group (here, capped at one plate's well count) its own controls, so the
    # resulting components are naturally small enough to distribute across plates.
    matrix = DataFrame(x = 1:10)
    experiment = Experiment(matrix; name = "multiplate_test", metadata = Dict(:positive_controls => 1, :negative_controls => 1))

    wells = trues(2, 4) # 8 wells/plate; capped groups force a split across >=2 plates
    rm = RunMaps.schedule_uniform_controls(collect(1:10), Dict(:positive => 1, :negative => 1), 8)

    scheduled = schedule_layout(experiment, rm, wells, (:positive, :negative);
        labware_names = nothing, plate_solver = "greedy")
    lay = layout(scheduled)
    @test count(lay.run) == 10
    @test sort(collect(skipmissing(lay.run_index))) == collect(1:10)
    @test length(unique(skipmissing(lay.run_index))) == 10 # no duplicates across plates

    @test_throws ArgumentError schedule_layout(experiment, Pair{Missing,PlateMap}[], rm)
end
