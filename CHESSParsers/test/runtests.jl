using Test, CHESSParsers, CHESSCore, CHESSLabConstants, DataFrames, Dates, Unitful, XLSX

import CHESSParsers: format_registry, detect, parse_raw

# A minimal mock InstrumentFormat, standing in for a real BioTek format until fixtures land (mirrors
# how Pourfecto's register_instrument! docstring defines a throwaway ExInstrument for its doctest).
struct MockFormat <: CHESSParsers.InstrumentFormat end

CHESSParsers.detect(::Type{MockFormat}, path::AbstractString) = endswith(path, ".mock")

function CHESSParsers.parse_raw(::Type{MockFormat}, path::AbstractString; kwargs...)
    data = DataFrame(
        well = ["A1", "A2"],
        value = [0.123, 0.456],
        time = [DateTime(2026, 1, 1, 12, 0, 0), DateTime(2026, 1, 1, 12, 0, 0)],
    )
    meta = Dict{String,Any}("format" => MockFormat, "source" => path, "read_kind" => "Absorbance")
    return [LabwareRead(meta, data)]
end

@testset "CHESSParsers" begin

    @testset "registry" begin
        register_format!(MockFormat; name="mock")
        @test format_registry["mock"] === MockFormat
        @test_throws ErrorException register_format!(MockFormat; name="mock")
        @test register_format!(MockFormat; name="mock", override=true) === MockFormat
    end

    mktemp() do path, io
        mockpath = path * ".mock"
        write(mockpath, "not real BioTek data")

        @testset "detect_format" begin
            @test detect_format(mockpath) === MockFormat
            @test detect_format(path) === nothing # no .mock extension
        end

        @testset "parse_instrument_file dispatch" begin
            lrs_auto = parse_instrument_file(mockpath)
            @test lrs_auto isa Vector{LabwareRead}
            @test only(lrs_auto).data == only(parse_instrument_file(mockpath; format=MockFormat)).data
            @test only(lrs_auto).data == only(parse_instrument_file(mockpath; format="mock")).data
            @test_throws ErrorException parse_instrument_file(path) # can't auto-detect
            @test_throws ErrorException parse_instrument_file(mockpath; format="not_a_format")
        end

        @testset "dataframe interface" begin
            lr = only(parse_instrument_file(mockpath))
            @test DataFrame(lr) === lr.data
            @test DataFrame(lr).well == ["A1", "A2"]
        end

        @testset "json interface" begin
            lr = only(parse_instrument_file(mockpath))
            j = labwareread_to_json(lr)
            @test j isa String
            lr2 = json_to_labwareread(j)
            @test lr2.metadata["format"] == "MockFormat"
            @test lr2.metadata["source"] == mockpath
            @test lr2.metadata["read_kind"] == "Absorbance"
            @test DataFrame(lr2).well == lr.data.well
            @test DataFrame(lr2).value == lr.data.value
        end

        @testset "chess interface" begin
            plate = build_location(loc"WP96")
            lrs = parse_instrument_file(mockpath)
            record_reads!(plate, lrs) # Vector{LabwareRead} convenience method
            a1_reads = CHESSCore.reads(plate["A1"])
            @test length(a1_reads) == 1
            @test CHESSCore.quantity(a1_reads[1]) == 0.123u"OD"
            @test read_time(a1_reads[1]) == DateTime(2026, 1, 1, 12, 0, 0)

            plate2 = build_location(loc"WP96")
            record_reads!(plate2, only(lrs)) # singular method still works directly
            @test CHESSCore.quantity(only(CHESSCore.reads(plate2["A1"]))) == 0.123u"OD"
        end
    end

    # Every fixture below is a de-identified copy of a real BioTek export (see
    # dev/deidentify_fixture.jl and the package README's "Contributing a fixture" section) --
    # committed and safe to run in CI, unlike the real files that generated them (which live only in
    # a local, gitignored data/ and are never checked in). Expected values here are the de-identified
    # copies' own (deterministic, seeded-random) values, not the real experimental results.
    fixturedir = joinpath(@__DIR__, "fixtures")

    @testset "Gen5: single_plate_single_read.xlsx (Epoch2, endpoint)" begin
        lr = only(parse_instrument_file(joinpath(fixturedir, "single_plate_single_read.xlsx")))
        @test lr.metadata["format"] === Epoch2Format
        @test lr.metadata["reader_type"] == "Epoch 2"
        @test lr.metadata["read_kind"] == "Absorbance"
        @test lr.metadata["wavelength"] == 600
        @test lr.metadata["plate"] == "Plate 1 - Sheet1"
        df = DataFrame(lr)
        @test names(df) == ["well", "time", "value"]
        @test nrow(df) == 96
        @test only(df.value[df.well.=="A1"]) == 1.036
        @test only(df.value[df.well.=="H12"]) == 0.617
        @test only(df.time[df.well.=="A1"]) == DateTime(2020, 1, 1, 9, 0, 0)

        plate = build_location(loc"WP96")
        record_reads!(plate, lr)
        @test CHESSCore.quantity(only(CHESSCore.reads(plate["A1"]))) == 1.036u"OD"

        j = labwareread_to_json(lr)
        lr2 = json_to_labwareread(j)
        @test lr2.metadata["format"] == "Epoch2Format"
        @test DataFrame(lr2).value == df.value
    end

    @testset "Gen5: single_plate_timeseries.xlsx (Epoch2, kinetic)" begin
        lrs = parse_instrument_file(joinpath(fixturedir, "single_plate_timeseries.xlsx"); format=Epoch2Format)
        # This file has a trailing computed curve-fit summary grid after its kinetic block
        # ("Max V [OD600:600]", ...) -- it must not surface as a second, spurious channel.
        @test length(lrs) == 1
        lr = only(lrs)
        @test lr.metadata["wavelength"] == 600
        df = DataFrame(lr)
        @test nrow(df) == 96 * 97 # 96 wells x 97 timepoints, no masked wells in this file
        a1 = sort(df[df.well.=="A1", :], :time)
        @test nrow(a1) == 97
        @test issorted(a1.time)
        @test a1.value[1] == 0.148
        @test a1.time[1] == DateTime(2020, 1, 1, 9, 0, 14)
    end

    @testset "Gen5: multi_plate_single_read.xlsx (Epoch2, multi-plate endpoint)" begin
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_plate_single_read.xlsx"))
        @test length(lrs) == 4 # one LabwareRead per plate (single channel each)
        @test sort([lr.metadata["plate"] for lr in lrs]) == ["SIM0000$i" for i in 1:4]
        @test all(lr -> nrow(lr.data) == 96, lrs)
        p1 = only(filter(lr -> lr.metadata["plate"] == "SIM00001", lrs))
        @test only(p1.data.value[p1.data.well.=="A1"]) == 0.683
    end

    @testset "Gen5: multi_plate_timeseries.xlsx (Cytation, multi-plate kinetic)" begin
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_plate_timeseries.xlsx"))
        @test length(lrs) == 8 # one LabwareRead per plate (single channel each)
        @test all(lr -> lr.metadata["format"] === CytationFormat, lrs)
        @test all(lr -> lr.metadata["reader_type"] == "CytationC10", lrs)
        @test sort([lr.metadata["plate"] for lr in lrs]) == ["Plate $i - Sheet1" for i in 1:8]
        @test all(lr -> nrow(lr.data) <= 9312, lrs) # some wells masked/missing
    end

    @testset "Gen5: multi_plate_kinetic_cytation5.xlsx (Cytation5, multi-plate kinetic, regression)" begin
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_plate_kinetic_cytation5.xlsx"))
        @test length(lrs) == 8
        @test all(lr -> lr.metadata["format"] === CytationFormat, lrs)
        @test all(lr -> lr.metadata["reader_type"] == "Cytation5", lrs)
        @test sort([lr.metadata["plate"] for lr in lrs]) == ["SIM0000$i" for i in 1:8]
        @test all(lr -> lr.metadata["read_kind"] == "Absorbance", lrs)
    end

    @testset "Gen5: multi_wavelength_sweep_endpoint.xlsx (Epoch2, multi-wavelength sweep endpoint)" begin
        # This file has no "Results" label and packs 15 wavelength sub-rows per well-letter --
        # exercises structural (header-shape) dispatch and the endpoint block splitting by channel.
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_wavelength_sweep_endpoint.xlsx"))
        @test length(lrs) == 15 # one LabwareRead per wavelength, all on the same (only) plate
        @test all(lr -> lr.metadata["plate"] == "SIM00001", lrs)
        @test all(lr -> lr.metadata["read_kind"] == "Absorbance", lrs)
        @test sort([lr.metadata["wavelength"] for lr in lrs]) ==
              [380, 390, 420, 460, 480, 490, 500, 540, 550, 580, 600, 610, 620, 660, 690]
        @test all(lr -> nrow(lr.data) == 16 * 24, lrs) # 16 letters x 24 columns, no missing wells

        ch380 = only(filter(lr -> lr.metadata["wavelength"] == 380, lrs))
        @test only(ch380.data.value[ch380.data.well.=="A1"]) == 1.284
        ch690 = only(filter(lr -> lr.metadata["wavelength"] == 690, lrs))
        @test only(ch690.data.value[ch690.data.well.=="P24"]) == 0.192
    end

    @testset "Gen5: multi_channel_kinetic.xlsx (Cytation5, multi-channel kinetic)" begin
        # One plate, three configured Read steps (OD600 absorbance + 2 fluorescence filter sets)
        # stacked sequentially in the sheet, plus 3 companion pivot-summary sheets that must be
        # skipped (not treated as extra plates).
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_channel_kinetic.xlsx"))
        @test length(lrs) == 3 # exactly 3 channels, no spurious entries from the pivot sheets
        @test all(lr -> lr.metadata["plate"] == "Plate 1 - Sheet1", lrs)
        @test all(lr -> lr.metadata["reader_type"] == "Cytation5", lrs)

        od = only(filter(lr -> lr.metadata["read_kind"] == "Absorbance", lrs))
        @test od.metadata["wavelength"] == 600
        a1_od = sort(od.data[od.data.well.=="A1", :], :time)
        @test a1_od.value[1] == 0.077

        fluor = filter(lr -> lr.metadata["read_kind"] == "Fluorescence", lrs)
        @test length(fluor) == 2
        mng = only(filter(lr -> lr.metadata["excitation"] == 505, fluor))
        @test mng.metadata["emission"] == 536
        a1_mng = sort(mng.data[mng.data.well.=="A1", :], :time)
        @test a1_mng.value[1] == 1500.0
        msc = only(filter(lr -> lr.metadata["excitation"] == 564, fluor))
        @test msc.metadata["emission"] == 602
        a1_msc = sort(msc.data[msc.data.well.=="A1", :], :time)
        @test a1_msc.value[1] == 5.0
    end

    @testset "Gen5: multi_channel_kinetic_biospa.xlsx (Cytation5, multi-plate multi-channel kinetic)" begin
        lrs = parse_instrument_file(joinpath(fixturedir, "multi_channel_kinetic_biospa.xlsx"))
        @test length(lrs) == 3 # single real plate sheet x 3 channels; Sheet1/2/3 pivots skipped
        @test all(lr -> lr.metadata["plate"] == "Plate 1 - Sheet1", lrs)
        kinds = [(lr.metadata["read_kind"], get(lr.metadata, "excitation", nothing)) for lr in lrs]
        @test ("Absorbance", nothing) in kinds
        @test ("Fluorescence", 505) in kinds
        @test ("Fluorescence", 564) in kinds
    end

    @testset "Gen5: bare_wavelength_endpoint.xlsx (Epoch2, bare-numeric endpoint label)" begin
        # Some single-wavelength endpoint exports label each row with just the wavelength as a raw
        # number (e.g. 500), not a "<name>:<wavelength>" string -- exercises _gen5_channel_meta's
        # Real method. This plate also has partially-masked columns (only 19 of 24 filled).
        lrs = parse_instrument_file(joinpath(fixturedir, "bare_wavelength_endpoint.xlsx"))
        @test length(lrs) == 2 # one LabwareRead per plate (single channel each)
        @test all(lr -> lr.metadata["read_kind"] == "Absorbance", lrs)
        @test all(lr -> lr.metadata["wavelength"] == 500, lrs)
        @test sort([lr.metadata["plate"] for lr in lrs]) == ["Plate 1 - Sheet1", "Plate 3 - Sheet1"]
        @test all(lr -> nrow(lr.data) == 16 * 19, lrs) # 16 letters x 19 filled columns (5 masked)

        p1 = only(filter(lr -> lr.metadata["plate"] == "Plate 1 - Sheet1", lrs))
        @test only(p1.data.value[p1.data.well.=="A1"]) == 0.038
        @test only(p1.data.value[p1.data.well.=="H12"]) == 0.026
        @test isempty(p1.data.value[p1.data.well.=="A20"]) # column 20 is masked/missing
    end

    @testset "Gen5: absorbance_spectrum.xlsx (Epoch2, absorbance spectrum scan)" begin
        # A wavelength sweep across the whole plate (300-700nm, step 10nm) rather than an endpoint
        # or kinetic read -- a "Wavelength"/well wide table with no elapsed-time or temperature
        # column. This 384-well plate is split across 4 sequential, disjoint well-batch sub-blocks
        # (96 wells each, repeating the same wavelength axis) that must be merged into one
        # LabwareRead per wavelength (not one per sub-block), plus a trailing computed
        # "Mean Max OD [...]" summary grid that must not surface as a channel.
        lrs = parse_instrument_file(joinpath(fixturedir, "absorbance_spectrum.xlsx"))
        @test length(lrs) == 41 # one LabwareRead per wavelength, sub-blocks merged
        @test all(lr -> lr.metadata["read_kind"] == "Absorbance", lrs)
        @test sort(unique(lr.metadata["wavelength"] for lr in lrs)) == collect(300:10:700)
        @test all(lr -> nrow(lr.data) == 384, lrs) # full plate, merged across well-batches
        @test sum(nrow(lr.data) for lr in lrs) == 384 * 41 # full plate x every wavelength, no gaps

        ch300 = only(filter(lr -> lr.metadata["wavelength"] == 300, lrs))
        @test all(w -> w in ch300.data.well, ["A1", "E1", "I1", "M1"]) # one representative well from each former sub-block
        @test only(ch300.data.value[ch300.data.well.=="A1"]) == 1.551
    end

    @testset "Gen5: spectrum sub-block well collision is an error, not a silent merge" begin
        # Two "Wavelength" sub-blocks that both report a value for the same well at the same
        # wavelength aren't a clean well-batch split of one plate -- merging them would be guessing,
        # so this must error rather than silently overwrite or silently duplicate. No committed
        # fixture demonstrates this naturally (every real file has disjoint splits), so it's built
        # as a small synthetic workbook here, mirroring how MockFormat stands in for a real file.
        mktemp() do path, io
            xlsxpath = path * ".xlsx"
            XLSX.openxlsx(xlsxpath; mode="w") do xf
                ws = xf[1]
                XLSX.rename!(ws, "Plate 1 - Sheet1")
                ws["A1"] = "Software Version"; ws["B1"] = "3.10.06"
                ws["A2"] = "Reader Type:"; ws["B2"] = "Epoch 2"
                ws["A3"] = "Plate Number"; ws["B3"] = "Plate 1"
                ws["A4"] = "Date"; ws["B4"] = Date(2020, 1, 1)
                ws["A5"] = "Time"; ws["B5"] = Dates.Time(9, 0, 0)
                ws["A6"] = "Procedure Details"
                ws["A7"] = "Read"; ws["B7"] = "Spectrum Read"
                ws["B8"] = "Absorbance Spectrum"
                ws["A9"] = "Spectrum Read:Spectrum"
                ws["B10"] = "Wavelength"; ws["C10"] = "A1"; ws["D10"] = "A2"
                ws["B11"] = 300; ws["C11"] = 0.5; ws["D11"] = 0.6
                ws["A13"] = "Spectrum Read:Spectrum" # a second sub-block re-reporting well A1 at 300nm
                ws["B14"] = "Wavelength"; ws["C14"] = "A1"; ws["D14"] = "A3"
                ws["B15"] = 300; ws["C15"] = 0.9; ws["D15"] = 0.7
            end
            @test_throws ErrorException parse_instrument_file(xlsxpath; format=Epoch2Format)
        end
    end

end
