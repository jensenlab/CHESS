# Parser for the BioTek Take3 Trio nucleic-acid quant accessory's .xlsx export -- structurally
# unrelated to the Gen5 plate-grid family despite sharing the same underlying Gen5 software (its
# header says "Gen5 version", not "Software Version", which is what keeps it from being misdetected
# as an ordinary Epoch2/Synergy/Cytation export of the same physical reader).
#
# Two sheet shapes, both still fitting LabwareRead's (plate, channel) -> {well, time, value} shape:
#
# - "Blank Read": a real-well-indexed table (Location/260 Raw/CV (%)/280 Raw/CV (%)/320 Raw/CV (%)),
#   plus a trailing "[AVE]" aggregate row (skipped, same as Gen5's own computed summaries).
# - "Sample Read #N": no well is recorded at all -- samples are identified only by Gen5's own
#   generic "SPL1".."SPL48" tokens, laid out as 3 "Slide" sub-blocks side by side (16 samples/slide,
#   an 8-letter x 2-position grid), each position's 4 sub-rows being raw A260, raw A280, a computed
#   260/280 ratio, and a computed ng/uL concentration. Mapping an SPL# back to where it physically
#   came from isn't information this file has -- that's the caller's job. The 3 slides are a capacity
#   split of one logical Sample Read and are merged into one set of channels per sheet, not kept as 3
#   separate ones (same principle as the Gen5 spectrum well-batch merge).
#
# The 260/280 ratio is skipped (trivially re-derivable from the two Absorbance channels already
# captured); CV (%) and "[AVE]" are skipped as aggregates. The ng/uL concentration is *not*
# re-derivable from the raw absorbance values with a fixed formula -- it's approximately
# A260 x 1000 for dsDNA, but Gen5 applies a real per-sample correction on top of that (confirmed
# directly: two samples can share the same rounded A260 yet report different concentrations), so it's
# captured as its own channel exactly as Gen5 computed and exported it, not recomputed here.

"""
    struct Take3TrioFormat <: InstrumentFormat end

Export format for the BioTek Take3 Trio nucleic-acid quant accessory's `.xlsx` export. See
[`InstrumentFormat`](@ref) and [`LabwareRead`](@ref).
"""
struct Take3TrioFormat <: InstrumentFormat end

const _TAKE3TRIO_SAMPLE_SHEET_RE = r"^Sample Read #\d+$"

_take3trio_is_plate_sheet(M::AbstractMatrix) = !isnothing(_gen5_findlabel(M, "Gen5 version"; to=min(3, size(M, 1))))

# Scans every cell (not just column 1, unlike _gen5_findlabel) for an exact string match -- used to
# locate structural header cells that aren't in column 1, like "Location" or "Slide 1".
function _take3trio_findcell(M::AbstractMatrix, value::AbstractString; from::Int=1)
    for i in from:size(M, 1), j in 1:size(M, 2)
        v = M[i, j]
        v isa AbstractString && v == value && return (i, j)
    end
    return nothing
end

function _take3trio_common_meta(M::AbstractMatrix)
    common = Dict{String,Any}("format" => Take3TrioFormat)
    for (key, label) in (
        "software_version" => "Gen5 version",
        "accessory"        => "Plate",
        "reader_type"      => "Reader Type:",
        "reader_serial"    => "Reader Serial Number:",
    )
        i = _gen5_findlabel(M, label)
        isnothing(i) || (common[key] = M[i, 2])
    end
    return common
end

function _take3trio_starttime(M::AbstractMatrix, sheetname::AbstractString)
    date_row = _gen5_findlabel(M, "Date")
    time_row = _gen5_findlabel(M, "Time")
    (isnothing(date_row) || isnothing(time_row)) && error("sheet \"$sheetname\" is missing Date/Time header fields")
    return DateTime(M[date_row, 2], M[time_row, 2])
end

# Location/260 Raw/280 Raw/320 Raw column offsets, skipping the CV (%) columns in between. One
# LabwareRead per wavelength found; the trailing "[AVE]" aggregate row is skipped, same as Gen5's own
# computed summary rows.
function _parse_take3trio_blank_sheet(M::AbstractMatrix, sheetname::AbstractString, common::Dict{String,Any})
    starttime = _take3trio_starttime(M, sheetname)

    loc = _take3trio_findcell(M, "Location")
    isnothing(loc) && error("sheet \"$sheetname\" has no \"Location\" header cell")
    header_row, loc_col = loc

    results = LabwareRead[]
    for (label, wavelength) in (("260 Raw", 260), ("280 Raw", 280), ("320 Raw", 320))
        match = _take3trio_findcell(M, label; from=header_row)
        isnothing(match) && continue
        _, col = match
        wells = String[]; times = DateTime[]; values = Float64[]
        for row in (header_row+1):size(M, 1)
            location = M[row, loc_col]
            (location isa AbstractString && location != "[AVE]") || continue
            v = M[row, col]
            v isa Missing && continue
            push!(wells, location)
            push!(times, starttime)
            push!(values, Float64(v))
        end
        meta = merge(copy(common), Dict{String,Any}("plate" => sheetname, "read_kind" => "Absorbance", "wavelength" => wavelength))
        push!(results, LabwareRead(meta, DataFrame(well=wells, time=times, value=values)))
    end
    return results
end

# Maps a data sub-row's trailing marker to the accumulator key it feeds, or `nothing` to skip a
# genuinely redundant/aggregate row (the 260/280 ratio). Errors on anything unrecognized rather than
# silently skipping it, since the 4-marker cycle (260/280/"260/280"/"ng/µL") is meant to be exhaustive.
function _take3trio_channel_key(marker)
    if marker isa Real
        iv = Int(marker)
        iv == 260 && return "260"
        iv == 280 && return "280"
        error("unrecognized Take3 Trio numeric sub-row marker $marker")
    elseif marker isa AbstractString
        marker == "260/280" && return nothing
        marker == "ng/µL" && return "ng/µL"
        error("unrecognized Take3 Trio sub-row marker \"$marker\"")
    else
        error("unrecognized Take3 Trio sub-row marker $(repr(marker))")
    end
end

# 3 "Slide N" sub-blocks side by side, each a (letter-row -> SPL1, SPL2 sample-position columns) x
# (260/280/"260/280"/"ng/µL" sub-row) grid. All 3 slides feed the same 3 channels (Absorbance@260,
# Absorbance@280, Concentration) -- merged, not kept as 3 separate LabwareReads, since they're a
# capacity split of one logical Sample Read, not 3 distinct channels. Each slide's SPL# tokens are
# disjoint by construction, but a `seen` guard still catches an unexpected collision loudly rather
# than silently overwriting.
function _parse_take3trio_sample_sheet(M::AbstractMatrix, sheetname::AbstractString, common::Dict{String,Any})
    starttime = _take3trio_starttime(M, sheetname)

    sampletype_row = _gen5_findlabel(M, "Sample Type")
    sample_type = isnothing(sampletype_row) ? missing : M[sampletype_row, 2]

    slide_row = nothing
    letter_cols = Int[]
    for i in 1:size(M, 1)
        for j in 1:size(M, 2)
            v = M[i, j]
            if v isa AbstractString && occursin(r"^Slide \d+$", v)
                slide_row = something(slide_row, i)
                push!(letter_cols, j)
            end
        end
        !isnothing(slide_row) && break
    end
    isnothing(slide_row) && error("sheet \"$sheetname\" has no \"Slide N\" header row")
    sort!(letter_cols)

    accum = Dict{String,NamedTuple}()
    isletter(v) = v isa AbstractString && occursin(r"^[A-Za-z]+$", v)

    for letter_col in letter_cols
        spl1_col, spl2_col, marker_col = letter_col + 1, letter_col + 2, letter_col + 3
        row = slide_row
        while row <= size(M, 1) && !isletter(M[row, letter_col])
            row += 1
        end
        while row <= size(M, 1) && isletter(M[row, letter_col])
            spl_ids = (string(M[row, spl1_col]), string(M[row, spl2_col]))
            for datarow in (row+1):(row+4)
                datarow > size(M, 1) && break
                key = _take3trio_channel_key(M[datarow, marker_col])
                isnothing(key) && continue
                entry = get!(() -> (seen=Set{String}(), well=String[], time=DateTime[], value=Float64[]), accum, key)
                for (spl_col, spl_id) in zip((spl1_col, spl2_col), spl_ids)
                    v = M[datarow, spl_col]
                    v isa Missing && continue
                    spl_id in entry.seen && error("sample \"$spl_id\" appears twice for channel \"$key\" in sheet \"$sheetname\"")
                    push!(entry.seen, spl_id)
                    push!(entry.well, spl_id)
                    push!(entry.time, starttime)
                    push!(entry.value, Float64(v))
                end
            end
            row += 5
        end
    end

    results = LabwareRead[]
    for (key, extra) in (
        ("260", Dict{String,Any}("read_kind" => "Absorbance", "wavelength" => 260)),
        ("280", Dict{String,Any}("read_kind" => "Absorbance", "wavelength" => 280)),
        ("ng/µL", Dict{String,Any}("read_kind" => "Concentration", "unit" => "ng/µL", "sample_type" => sample_type)),
    )
        haskey(accum, key) || continue
        entry = accum[key]
        meta = merge(copy(common), Dict{String,Any}("plate" => sheetname), extra)
        push!(results, LabwareRead(meta, DataFrame(well=entry.well, time=entry.time, value=entry.value)))
    end
    return results
end

"""
    parse_raw(::Type{Take3TrioFormat}, path::AbstractString; kwargs...) -> Vector{LabwareRead}

Parse a Take3 Trio nucleic-acid quant `.xlsx` export into one [`LabwareRead`](@ref) per (sheet,
channel): `Absorbance`@260/280/320 for the `"Blank Read"` sheet (real well IDs), and
`Absorbance`@260/280 plus `Concentration` (ng/µL) for each `"Sample Read #N"` sheet (Gen5 `SPL#`
sample tokens, not real wells -- mapping a sample back to its physical source plate/well is the
caller's responsibility, not something this file records).
"""
function parse_raw(::Type{Take3TrioFormat}, path::AbstractString; kwargs...)
    xf = XLSX.readxlsx(path)
    sheetnames = XLSX.sheetnames(xf)

    # Only "Blank Read" carries the full "Gen5 version"/"Reader Type:"/etc. metadata header --
    # "Sample Read #N" sheets have their own Date/Time/Sample Type fields but not that header, so
    # `common` is sourced from whichever sheet in the workbook has it, not gated per sheet.
    common = nothing
    for sn in sheetnames
        M = xf[sn][:]
        _take3trio_is_plate_sheet(M) && (common = _take3trio_common_meta(M); break)
    end
    isnothing(common) && error("\"$path\" has no sheet with a \"Gen5 version\" header -- not a Take3 Trio export")

    results = LabwareRead[]
    for sn in sheetnames
        M = xf[sn][:]
        if sn == "Blank Read"
            append!(results, _parse_take3trio_blank_sheet(M, sn, common))
        elseif occursin(_TAKE3TRIO_SAMPLE_SHEET_RE, sn)
            append!(results, _parse_take3trio_sample_sheet(M, sn, common))
        end
    end
    isempty(results) && error("\"$path\" has no recognized Take3 Trio sheets (\"Blank Read\" / \"Sample Read #N\")")
    return results
end

function detect(::Type{Take3TrioFormat}, path::AbstractString)
    endswith(lowercase(path), ".xlsx") || return false
    try
        xf = XLSX.readxlsx(path)
        sheetnames = XLSX.sheetnames(xf)
        any(sn -> sn == "Blank Read" || occursin(_TAKE3TRIO_SAMPLE_SHEET_RE, sn), sheetnames) || return false
        return any(sn -> _take3trio_is_plate_sheet(xf[sn][:]), sheetnames)
    catch
        return false
    end
end

register_format!(Take3TrioFormat; name="take3trio")
