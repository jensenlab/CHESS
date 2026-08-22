using Test, CHESSExperiments, PlateMaps, RunMaps, DataFrames, Random, CHESSCore, Unitful, CSV

#### minimal test lab for factor-parsing tests (mirrors CHESSCore/test/core_fixtures.jl's TestChemOrg)
module TestFactorLab
using CHESSCore, Unitful
@reagent water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
@reagent dmso "DMSO" Liquid 78.13u"g/mol" 1.1u"g/mL" 679
@reagent alanine "alanine" Solid 89.09u"g/mol" missing 5950
@organism SMU_UA159 "Streptococcus" "mutans" "UA159"
end
CHESSCore.register_lab(TestFactorLab)
const test_reagent_context = [CHESSCore, TestFactorLab]
const test_org_context = [CHESSCore, TestFactorLab]

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

    @test get_parameter(scheduled, :run_map) == [rm]
    @test get_parameter(scheduled, :plate_maps) == [Pair("plate1", pm)]

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

@testset "Factor types and registry" begin
    @test_throws ArgumentError ContinuousFactor(:bad_dest_test; destination = :organism)
    @test_throws ArgumentError CategoricalFactor(:bad_dest_test2; levels = () -> (:a, :b), destination = :reagent)

    atmosphere = CategoricalFactor(:atmosphere_test; levels = () -> (:aerobic, :anaerobic), blocking = true, destination = :condition)
    register_factor!(atmosphere)
    @test get_factor(:atmosphere_test) === atmosphere
    @test is_blocking(atmosphere)
    @test destination(atmosphere) == :condition
    @test factor_levels(atmosphere) == (:aerobic, :anaerobic)
    @test_throws DuplicateRegistrationError register_factor!(atmosphere)
    @test_throws KeyError get_factor(:never_registered_factor_test)

    register_factor!(ContinuousFactor(:temperature_test; blocking = true, destination = :condition))
    register_factor!(CategoricalFactor(:strain_test; levels = () -> (:SMU_UA159,), blocking = false, destination = :organism))
end

@testset "factor classification" begin
    @test factor_destination(:alanine; reagent_context = test_reagent_context) == :reagent
    @test factor_destination(:atmosphere_test; reagent_context = test_reagent_context) == :condition
    @test factor_destination(:strain_test; reagent_context = test_reagent_context) == :organism
    @test_throws ArgumentError factor_destination(:never_a_factor_or_reagent; reagent_context = test_reagent_context)

    cols = classify_columns([:alanine, :atmosphere_test, :strain_test]; reagent_context = test_reagent_context)
    @test cols.reagent == [:alanine]
    @test cols.condition == [:atmosphere_test]
    @test cols.organism == [:strain_test]
end

@testset "resolve_stock: absolute mass/volume/molarity" begin
    row = (alanine = 10.0, dmso = 5.0)
    stock, orgs = resolve_stock(row, [:alanine, :dmso], Symbol[];
        units = Dict(:alanine => "g", :dmso => "mL"), reagent_context = test_reagent_context)
    @test isempty(orgs)
    @test stock isa CHESSCore.Solution
    @test CHESSCore.quantity(stock, TestFactorLab.alanine) ≈ 10u"g"
    @test CHESSCore.quantity(stock, TestFactorLab.dmso) ≈ 5u"mL"

    row_molar = (alanine = 10.0,)
    stock_m, _ = resolve_stock(row_molar, [:alanine], Symbol[];
        units = Dict(:alanine => "mM"), reagent_context = test_reagent_context, total_volume = 200u"mL")
    @test stock_m isa CHESSCore.Mixture
    expected_mass = uconvert(u"g", 10u"mM" * 200u"mL" * 89.09u"g/mol")
    @test CHESSCore.quantity(stock_m, TestFactorLab.alanine) ≈ expected_mass
end

@testset "resolve_stock: underdetermined and solvent shortcut" begin
    row = (alanine = 5.0,)
    @test_throws ArgumentError resolve_stock(row, [:alanine], Symbol[];
        units = Dict(:alanine => "percent"), reagent_context = test_reagent_context)

    row2 = (alanine = 10.0, dmso = 20.0)
    stock2, _ = resolve_stock(row2, [:alanine, :dmso], Symbol[];
        units = Dict(:alanine => "g", :dmso => "mL"),
        reagent_context = test_reagent_context, total_volume = 200u"mL", solvent = :water)
    @test CHESSCore.quantity(stock2, TestFactorLab.dmso) ≈ 20u"mL"
    @test CHESSCore.quantity(stock2, TestFactorLab.water) ≈ 180u"mL"

    row3 = (dmso = 250.0,)
    @test_throws ArgumentError resolve_stock(row3, [:dmso], Symbol[];
        units = Dict(:dmso => "mL"), reagent_context = test_reagent_context, total_volume = 200u"mL", solvent = :water)
end

@testset "resolve_stock: organism promotes to Culture" begin
    row = (alanine = 10.0, strain_test = "SMU_UA159")
    stock, orgs = resolve_stock(row, [:alanine], [:strain_test];
        units = Dict(:alanine => "g"), reagent_context = test_reagent_context, org_context = test_org_context)
    @test stock isa CHESSCore.Culture
    @test TestFactorLab.SMU_UA159 in CHESSCore.organisms(stock)
    @test orgs[:strain_test] == "SMU_UA159"

    row_missing = (alanine = 10.0, strain_test = missing)
    stock_no_org, orgs2 = resolve_stock(row_missing, [:alanine], [:strain_test];
        units = Dict(:alanine => "g"), reagent_context = test_reagent_context, org_context = test_org_context)
    @test stock_no_org isa CHESSCore.Mixture
    @test ismissing(orgs2[:strain_test])
end

@testset "resolve_conditions" begin
    row = (atmosphere_test = :aerobic, temperature_test = 37.0)
    conds = resolve_conditions(row, [:atmosphere_test, :temperature_test])
    @test conds[:atmosphere_test] == :aerobic
    @test conds[:temperature_test] == 37.0

    bad_row = (atmosphere_test = :nitrogen_only, temperature_test = 37.0)
    @test_throws ArgumentError resolve_conditions(bad_row, [:atmosphere_test])
end

@testset "parse_design" begin
    mktempdir() do dir
        path = joinpath(dir, "design.csv")
        write(path, "Ala (g),Strain\n10,SMU_UA159\n5,SMU_UA159\n")

        cmap = DesignColumnMap(
            columns = Dict("Ala (g)" => :alanine, "Strain" => :strain_test),
            values = Dict(:strain_test => Dict("SMU_UA159" => :SMU_UA159)),
            units = Dict(:alanine => "g"),
        )
        expt = parse_design(path; column_map = cmap, reagent_context = test_reagent_context)
        @test Set(propertynames(expt.design)) == Set([:alanine, :strain_test])
        @test expt.design.alanine == [10, 5]
        @test expt.design.strain_test == [:SMU_UA159, :SMU_UA159]
        @test get_parameter(expt, :column_map) === cmap

        bad_path = joinpath(dir, "bad.csv")
        write(bad_path, "Mystery,Ala (g)\nfoo,10\n")
        @test_throws ArgumentError parse_design(bad_path; column_map = cmap, reagent_context = test_reagent_context)
    end
end

@testset "partition_by_blocking" begin
    matrix = DataFrame(
        atmosphere_test = [:aerobic, :aerobic, :anaerobic, :anaerobic],
        temperature_test = [37.0, 37.0, 37.0, 30.0],
        strain_test = fill("SMU_UA159", 4),
    )
    experiment = Experiment(matrix)
    blocking_cols, groups = partition_by_blocking(experiment)
    @test Set(blocking_cols) == Set([:atmosphere_test, :temperature_test])
    @test length(groups) == 3 # (aerobic,37), (anaerobic,37), (anaerobic,30)
    @test sort(vcat([g.rows for g in groups]...)) == 1:4
    @test sum(length(g.rows) for g in groups) == 4

    # no blocking factors present as columns -> everything lands in one group
    plain = Experiment(DataFrame(x = 1:3))
    plain_cols, plain_groups = partition_by_blocking(plain)
    @test isempty(plain_cols)
    @test length(plain_groups) == 1
    @test only(plain_groups).rows == [1, 2, 3]
end

@testset "schedule_blocked_layout" begin
    matrix = DataFrame(
        atmosphere_test = [:aerobic, :aerobic, :anaerobic, :anaerobic],
        strain_test = ["SMU_UA159", "SMU_UA159", "SMU_UA159", missing],
    )
    experiment = Experiment(matrix; metadata = Dict(:positive_controls => 1, :negative_controls => 1))

    wells = trues(2, 4) # 8 wells/plate
    scheduled = schedule_blocked_layout(experiment, wells, (:positive, :negative);
        org_context = test_org_context, reagent_context = test_reagent_context)

    lay = layout(scheduled)
    @test count(lay.run) == 4
    @test sort(collect(skipmissing(lay.run_index))) == [1, 2, 3, 4]
    @test length(unique(skipmissing(lay.run_index))) == 4

    pcond = get_parameter(scheduled, :plate_conditions)
    @test length(unique(values(pcond))) == 2 # two distinct blocking groups
    @test all(haskey(cond, :atmosphere_test) for cond in values(pcond))

    wcond = get_parameter(scheduled, :well_conditions)
    @test length(wcond) == 4
    @test all(haskey(v, :strain_test) for v in values(wcond))

    row4 = only(filter(r -> !ismissing(r.run_index) && r.run_index == 4, eachrow(lay)))
    @test ismissing(wcond[(row4.labware, row4.well)][:strain_test])

    row1 = only(filter(r -> !ismissing(r.run_index) && r.run_index == 1, eachrow(lay)))
    @test wcond[(row1.labware, row1.well)][:strain_test] == "SMU_UA159"

    # an infeasible group (zero usable wells, but rows to place) errors clearly, naming the group
    huge = Experiment(DataFrame(atmosphere_test = fill(:aerobic, 20)); metadata = Dict(:positive_controls => 0, :negative_controls => 0))
    @test_throws ArgumentError schedule_blocked_layout(huge, falses(1, 1), Symbol[])
end

@testset "expand_control_templates" begin
    matrix = DataFrame(
        atmosphere_test = [:aerobic, :anaerobic, :aerobic, missing],
        temperature_test = [37.0, 37.0, 30.0, missing],
        control_role = [missing, missing, missing, :positive],
    )
    experiment = Experiment(matrix)
    expanded = expand_control_templates(experiment)
    @test nrow(expanded.design) == 6 # 3 samples + 3 expanded control copies (one per distinct combo)
    controls = filter(r -> !ismissing(r.control_role), eachrow(expanded.design))
    @test length(controls) == 3
    combos = Set((r.atmosphere_test, r.temperature_test) for r in controls)
    @test combos == Set([(:aerobic, 37.0), (:anaerobic, 37.0), (:aerobic, 30.0)])

    # a sample row missing a blocking value (no :control_role) is an error
    bad = Experiment(DataFrame(atmosphere_test = [:aerobic, missing], temperature_test = [37.0, 37.0]))
    @test_throws ArgumentError expand_control_templates(bad)

    # no control templates at all -> passthrough, unchanged
    plain = Experiment(DataFrame(atmosphere_test = [:aerobic], temperature_test = [37.0]))
    @test expand_control_templates(plain) === plain

    # a control with no wildcard cells at all is kept exactly as the one row it is
    single = Experiment(DataFrame(
        atmosphere_test = [:aerobic, :aerobic],
        temperature_test = [37.0, 37.0],
        control_role = [missing, :blank],
    ))
    @test nrow(expand_control_templates(single).design) == 2
end

@testset "schedule_blocked_layout with duplicates and real controls" begin
    matrix = DataFrame(
        atmosphere_test = [:aerobic, :aerobic, missing],
        strain_test = ["SMU_UA159", "SMU_UA159", "SMU_UA159"],
        control_role = [missing, missing, :positive],
        duplicates = [2, missing, missing],
    )
    experiment = Experiment(matrix)

    wells = trues(2, 2) # exactly 4 wells: 2 samples + 1 control + 1 duplicate well
    scheduled = schedule_blocked_layout(experiment, wells, (:positive,);
        org_context = test_org_context, reagent_context = test_reagent_context)

    lay = layout(scheduled)
    @test count(lay.run) == 3 # samples 1,2 + the expanded control row, each placed exactly once
    @test count(.!lay.run) == 1 # the one extra :duplicate well for row 1

    rms = get_parameter(scheduled, :run_map)
    @test length(rms) == 1 # one blocking group -- only :aerobic appears after expansion
    rm = only(rms)
    @test length(RunMaps.linked_runs(rm, 1; type = :duplicate)) == 1
    @test length(RunMaps.linked_runs(rm, 3; type = :positive)) == 2 # control row 3 linked to both samples

    pms = get_parameter(scheduled, :plate_maps)
    @test length(pms) == 1
end
