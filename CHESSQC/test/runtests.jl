using Test, CHESSQC, CHESSExperiments, CHESSCore, CHESSDatabase, DataFrames, Random, Unitful, RunMaps, PlateMaps

Random.seed!(123345)

@location_kind TestWell200 Symbol[] nothing nothing 200u"µL" nothing nothing
@location_kind TestQCPlate Symbol[] (4, 4) :TestWell200 nothing nothing nothing

"""
    mock_runmap(n_runs, n_pos, n_neg) -> RunMap

`n_runs` run nodes (identified `1:n_runs`), each densely linked to `n_pos` shared `:positive` and
`n_neg` shared `:negative` control nodes -- matches what `PlateArrays.PlateArray(wells, positives,
negatives)` used to represent (a plate-wide shared control pool, any run scored by its nearest control of
a role).
"""
function mock_runmap(n_runs, n_pos, n_neg)
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

function mock_experiment_and_data(R, C; n_pos=2, n_neg=2, labware=missing)
    n_runs = R * C - n_pos - n_neg
    matrix = DataFrame(x = 1:n_runs)
    experiment = Experiment(matrix; name = "mock_experiment")

    rm = mock_runmap(n_runs, n_pos, n_neg)
    pm = only(schedule_platemap(trues(R, C), rm, (:positive, :negative)))

    scheduled = schedule_layout(experiment, pm, rm; labware)
    lay = layout(scheduled)

    data = zeros(R, C)
    for i in 1:nrow(lay)
        r, c = lay.row[i], lay.col[i]
        data[r, c] = if lay.positive[i]
            rand(1.3:0.01:1.7)
        elseif lay.negative[i]
            rand(0.05:0.01:0.2)
        else
            rand(0.25:0.01:1.6)
        end
    end
    return scheduled, data
end

@testset "data_correction dispatches on QCMethod / Symbol" begin
    experiment, data = mock_experiment_and_data(8, 12; n_pos=8, n_neg=8)
    lay = layout(experiment)

    corrected_gp = data_correction(data, lay, GPCorrection())
    @test size(corrected_gp) == size(data)
    @test corrected_gp isa Matrix{Float64}

    corrected_gp_by_name = data_correction(data, lay, :gp_correction)
    @test corrected_gp_by_name == corrected_gp

    corrected_sn = data_correction(data, lay, SubtractNormalize())
    @test size(corrected_sn) == size(data)

    corrected_sn_by_name = data_correction(data, lay, :subtract_and_normalize)
    @test corrected_sn_by_name == corrected_sn

    bad_data = zeros(2, 2)
    @test_throws ErrorException data_correction(bad_data, lay, GPCorrection())
end

@testset "control_summary" begin
    experiment, data = mock_experiment_and_data(8, 12; n_pos=8, n_neg=8)
    df = control_summary(data, layout(experiment))
    @test nrow(df) == 3
    @test Set(df.type) == Set(["runs", "positive controls", "negative controls"])
end

@testset "layout's positive/negative columns match control_bitmatrix" begin
    experiment, data = mock_experiment_and_data(8, 12; n_pos=8, n_neg=8)
    lay = layout(experiment)

    pos_mask = CHESSQC.control_bitmatrix(lay, :positive)
    neg_mask = CHESSQC.control_bitmatrix(lay, :negative)
    @test count(pos_mask) == 8
    @test count(neg_mask) == 8
    @test !any(pos_mask .& neg_mask) # no well is both

    corrected = data_correction(data, lay, GPCorrection())
    @test size(corrected) == size(data)
end

@testset "multi-plate layouts are rejected, not silently mishandled" begin
    experiment1, data1 = mock_experiment_and_data(4, 4; n_pos=1, n_neg=1, labware="plate1")
    experiment2, data2 = mock_experiment_and_data(4, 4; n_pos=1, n_neg=1, labware="plate2")
    multiplate_layout = vcat(layout(experiment1), layout(experiment2))
    combined_data = data1 # size matches, content doesn't matter -- this must error before touching data

    @test length(unique(multiplate_layout.labware)) == 2
    @test_throws ErrorException data_correction(combined_data, multiplate_layout, GPCorrection())
    @test_throws ErrorException control_summary(combined_data, multiplate_layout)

    # grouping by labware first, as the caller is expected to, works fine
    single = multiplate_layout[multiplate_layout.labware.=="plate1", :]
    @test size(data_correction(data1, single, GPCorrection())) == size(data1)
end

@testset "CHESSCore adapter (to_plate_matrix / record_qc_reads!)" begin
    Absorbance = CHESSCore.ReadKind(:TestAbsorbance, u"OD", nothing)
    CHESSCore.read_kinds[:TestAbsorbance] = Absorbance

    dbpath = tempname() * ".db"
    create_db(dbpath)
    connect_SQLite(dbpath)

    R, C = 4, 4
    labware = generate_location(TestQCPlate) # DB-backed, so wells get real committed location_ids
    experiment, data = mock_experiment_and_data(R, C; n_pos=2, n_neg=2, labware = name(labware))
    lay = layout(experiment)

    for i in 1:nrow(lay)
        well = labware[lay.row[i], lay.col[i]]
        record_read!(well, CHESSCore.Read(Absorbance, data[lay.row[i], lay.col[i]] * u"OD"))
    end

    pulled_data = to_plate_matrix(labware, lay, :TestAbsorbance)
    @test pulled_data ≈ data
    @test all(!ismissing, lay.location_id) # opportunistically fused during to_plate_matrix

    corrected = data_correction(pulled_data, lay, GPCorrection())
    record_qc_reads!(labware, corrected, lay, :TestAbsorbance, GPCorrection())

    for i in 1:nrow(lay)
        @test lay.metadata[i][Symbol("chessqc.correction_method")] == string(GPCorrection)
    end
    @test length(CHESSCore.reads(labware[lay.row[1], lay.col[1]])) == 2 # raw read + QC-corrected read, never overwritten
end
