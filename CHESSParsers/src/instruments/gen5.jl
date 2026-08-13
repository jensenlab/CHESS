# Shared parsing engine for BioTek Gen5 .xlsx exports (Epoch2/Synergy/Cytation share one file
# layout -- the reader model is a "Reader Type:" data field, not a different file structure). Every
# *real* plate sheet is a label/value metadata header followed by one or more data blocks, each
# either an endpoint grid or a kinetic wide table -- a procedure can configure multiple "Read" steps
# (e.g. an absorbance read plus a fluorescence read with several filter sets), and Gen5 stacks each
# one's block sequentially in the same sheet. Workbooks also sometimes carry extra "pivot summary"
# sheets (one per channel, reshaped, no metadata header) that duplicate data already in the real
# plate sheet at lower fidelity (a bare read-index or fractional-minute Time column, no timestamps)
# -- those are detected and skipped.
#
# Dispatch and block parsing key on the *shape* of the data (a numeric column-index header row vs a
# "Time" header row) rather than section-title text, since which titles a given protocol includes
# varies (e.g. some endpoint exports have no "Results" label at all, and kinetic exports word the
# same thing as "Start/End Kinetic" or "Discontinuous Kinetics") and titles observed so far are not
# guaranteed to be the full set that exists.
#
# Each real data block ends in a trailing "<name>:<label>" marker, e.g. "OD600:600" (absorbance,
# label = wavelength) or "Fluor:505,536" (fluorescence, label = excitation,emission) -- some
# single-wavelength endpoint exports instead label each row with just a bare number (e.g. 500, no
# name/colon at all), which can only mean a single Absorbance wavelength. Absorbance
# vs Fluorescence is read directly off the label's shape (a comma means excitation,emission) rather
# than matched back to a declared "Read" procedure step's name, since Gen5's own naming of unnamed
# Read steps isn't consistent (a single unnamed absorbance read at 600nm is auto-named "OD600", but
# 3 unnamed absorbance reads together are auto-named "Read 1"/"Read 2"/"Read 3" -- the name alone
# doesn't reliably say what kind of read it is, but the label's own shape always does). Gen5 also
# appends a *computed* summary grid after a kinetic block (per-well curve-fit metrics like "Max V"),
# shaped like another endpoint grid but labeled e.g. "Max V [OD600:600]" -- since that doesn't match
# the raw "<name>:<label>" shape, it's recognized and skipped rather than misparsed as a channel.
# One `LabwareRead` is produced per distinct raw block label found -- one per (plate, channel), never
# one wide table spanning several channels.

const _GEN5_LABEL_RE = r"^(.+):([\d,]+)$"
const _GEN5_EXCEL_EPOCH = DateTime(1899, 12, 30)

function _gen5_findlabel(M::AbstractMatrix, label::AbstractString; from::Int=1, to::Int=size(M, 1))
    for i in from:to
        v = M[i, 1]
        v isa AbstractString && v == label && return i
    end
    return nothing
end

function _gen5_findmatch(M::AbstractMatrix, re::Regex; from::Int=1, to::Int=size(M, 1), col::Int=1)
    for i in from:to
        v = M[i, col]
        v isa AbstractString && occursin(re, v) && return i
    end
    return nothing
end

# The column-index header row of an endpoint grid, e.g. [missing, missing, 1, 2, ..., N] -- present
# in every endpoint export seen (single- and multi-wavelength alike) regardless of section titles.
function _gen5_find_endpoint_header(M::AbstractMatrix; from::Int=1)
    for i in from:size(M, 1)
        M[i, 1] isa Missing && M[i, 2] isa Missing && M[i, 3] isa Integer && M[i, 3] == 1 && return i
    end
    return nothing
end

# The Time/T°/well-columns header row of a kinetic table -- present in every kinetic export seen.
function _gen5_find_kinetic_header(M::AbstractMatrix; from::Int=1)
    for i in from:size(M, 1)
        M[i, 2] isa AbstractString && M[i, 2] == "Time" && return i
    end
    return nothing
end

# The Wavelength/well-columns header row of a spectrum-scan table -- like a kinetic table but
# indexed by wavelength instead of elapsed time, and with no T° column (well columns start right
# after the Wavelength column, not one column later).
function _gen5_find_spectrum_header(M::AbstractMatrix; from::Int=1)
    for i in from:size(M, 1)
        M[i, 2] isa AbstractString && M[i, 2] == "Wavelength" && return i
    end
    return nothing
end

# A real plate sheet always starts with this metadata header; the per-channel "pivot summary" sheets
# Gen5 sometimes also exports alongside it don't have one.
_gen5_is_plate_sheet(M::AbstractMatrix) = !isnothing(_gen5_findlabel(M, "Software Version"; to=min(3, size(M, 1))))

"""
    _gen5_reader_type(path::AbstractString) -> Union{String,Nothing}

Return the value of the first real plate sheet's "Reader Type:" field (e.g. `"Epoch 2"`,
`"CytationC10"`), or `nothing` if `path` isn't a readable Gen5 export. Used by every Gen5-family
format's `detect`.
"""
function _gen5_reader_type(path::AbstractString)
    try
        xf = XLSX.readxlsx(path)
        for sn in XLSX.sheetnames(xf)
            M = xf[sn][:]
            _gen5_is_plate_sheet(M) || continue
            i = _gen5_findlabel(M, "Reader Type:")
            isnothing(i) || return string(M[i, 2])
        end
        return nothing
    catch
        return nothing
    end
end

function _parse_gen5_header(M::AbstractMatrix)
    header = Dict{String,Any}()
    for (key, label) in (
        "software_version" => "Software Version",
        "experiment_path"  => "Experiment File Path:",
        "protocol_path"    => "Protocol File Path:",
        "plate"            => "Plate Number",
        "date"             => "Date",
        "time"             => "Time",
        "reader_type"      => "Reader Type:",
        "reader_serial"    => "Reader Serial Number:",
    )
        i = _gen5_findlabel(M, label)
        isnothing(i) || (header[key] = M[i, 2])
    end
    return header
end

# Excel/Gen5 represents an elapsed kinetic duration as a time-of-day (Dates.Time) as long as it's
# under 24h, and switches to a DateTime once the run crosses the 24h mark (encoded as a date offset
# from Excel's epoch, 1899-12-30) -- both forms are converted to elapsed milliseconds here.
_gen5_elapsed_ms(t::Dates.Time) = Dates.value(t) ÷ 1_000_000
_gen5_elapsed_ms(t::DateTime) = Dates.value(t - _GEN5_EXCEL_EPOCH)

"""
    _gen5_channel_meta(label_cell) -> Union{Dict{String,Any},Nothing}

Parse a raw data block's trailing marker into channel metadata: `read_kind` plus either
`wavelength` or `excitation`/`emission`. Two shapes are recognized:
- a `"<name>:<label>"` string (e.g. `"OD600:600"`, `"Fluor:505,536"`) -- label is a bare integer
  (Absorbance wavelength) or a comma-separated pair (Fluorescence excitation,emission);
- a bare `Real` (e.g. `500`) -- some endpoint exports label each row with just the wavelength and no
  name/colon at all; since there's no way to spell an excitation/emission pair without a separator,
  a bare number can only mean a single Absorbance wavelength.
Returns `nothing` if `label_cell` doesn't match either shape -- the caller's job to skip such a row
rather than error, since that's how a computed summary block (not a raw channel) is recognized.
"""
function _gen5_channel_meta(label_cell::AbstractString)
    m = match(_GEN5_LABEL_RE, label_cell)
    m === nothing && return nothing
    suffix = m.captures[2]
    meta = Dict{String,Any}()
    if occursin(',', suffix)
        parts = split(suffix, ',')
        length(parts) == 2 || return nothing
        meta["read_kind"] = "Fluorescence"
        meta["excitation"] = parse(Int, parts[1])
        meta["emission"] = parse(Int, parts[2])
    else
        meta["read_kind"] = "Absorbance"
        meta["wavelength"] = parse(Int, suffix)
    end
    return meta
end
_gen5_channel_meta(label_cell::Real) = Dict{String,Any}("read_kind" => "Absorbance", "wavelength" => Int(label_cell))
_gen5_channel_meta(label_cell) = nothing

# An endpoint grid: row-letter x column-number, with one or more consecutive rows per well-letter --
# one row per configured wavelength (just one for a single-wavelength read, many for a multi-
# wavelength "sweep"). The letter itself only appears in the first such row; later rows repeat the
# letter's block via a blank col2, so `current_letter` carries forward and the loop's real
# end-of-grid signal is the trailing marker cell going missing entirely, not col2 being blank. Rows
# whose marker doesn't parse as a raw channel (see `_gen5_channel_meta`) are skipped, not errored --
# that's how a trailing computed-summary grid (e.g. "Max V [...]") is recognized and ignored. Rows
# are grouped by their distinct marker (channel) and returned as one (metadata, data) pair per
# channel, plus the row to resume scanning from for any further blocks in the sheet.
function _parse_gen5_endpoint_block(M::AbstractMatrix, row_header::Int, starttime::DateTime)
    cols = Int[]
    c = 3
    while c <= size(M, 2) && M[row_header, c] isa Number
        push!(cols, Int(M[row_header, c]))
        c += 1
    end
    ncols = length(cols)
    ncols == 0 && error("could not read the endpoint grid's column numbers")
    labelcol = 3 + ncols

    channel_order = String[]
    channel_meta = Dict{String,Dict{String,Any}}()
    channel_wells = Dict{String,Vector{String}}()
    channel_times = Dict{String,Vector{DateTime}}()
    channel_values = Dict{String,Vector{Float64}}()

    row = row_header + 1
    current_letter = nothing
    while row <= size(M, 1)
        label_cell = labelcol <= size(M, 2) ? M[row, labelcol] : missing
        (label_cell isa AbstractString || label_cell isa Real) || break
        key = string(label_cell) # a bare Real (e.g. 500) and a "<name>:<label>" string are both valid keys

        letter_cell = M[row, 2]
        letter_cell isa AbstractString && occursin(r"^[A-Za-z]+$", letter_cell) && (current_letter = letter_cell)
        current_letter === nothing && break

        meta = get(channel_meta, key, nothing)
        if meta === nothing
            meta = _gen5_channel_meta(label_cell)
            if meta === nothing
                row += 1
                continue # not a raw channel marker (e.g. a computed summary metric) -- skip, don't group
            end
            channel_meta[key] = meta
            push!(channel_order, key)
            channel_wells[key] = String[]
            channel_times[key] = DateTime[]
            channel_values[key] = Float64[]
        end
        wells, times, values = channel_wells[key], channel_times[key], channel_values[key]
        for (j, colnum) in enumerate(cols)
            v = M[row, 2+j]
            v isa Missing && continue
            push!(wells, string(current_letter, colnum))
            push!(times, starttime)
            push!(values, Float64(v))
        end
        row += 1
    end

    blocks = [(channel_meta[k], DataFrame(well=channel_wells[k], time=channel_times[k], value=channel_values[k])) for k in channel_order]
    return blocks, row
end

# A kinetic wide table: one block label -> one channel, so no grouping is needed the way the
# endpoint grid needs it. Returns the (metadata, data) pair plus the row to resume scanning from.
function _parse_gen5_kinetic_block(M::AbstractMatrix, row_label::Int, row_header::Int, starttime::DateTime)
    label_cell = M[row_label, 1]
    meta = _gen5_channel_meta(label_cell)
    meta === nothing && error("kinetic block label \"$label_cell\" doesn't match the expected \"<name>:<label>\" shape")

    wellcols = Int[]
    wells = String[]
    c = 4
    while c <= size(M, 2) && M[row_header, c] isa AbstractString
        push!(wellcols, c)
        push!(wells, M[row_header, c])
        c += 1
    end

    out_well = String[]; out_time = DateTime[]; out_val = Float64[]
    row = row_header + 1
    while row <= size(M, 1) && (M[row, 2] isa Dates.Time || M[row, 2] isa DateTime)
        t = starttime + Millisecond(_gen5_elapsed_ms(M[row, 2]))
        for (well, col) in zip(wells, wellcols)
            v = M[row, col]
            v isa Missing && continue
            push!(out_well, well)
            push!(out_time, t)
            push!(out_val, Float64(v))
        end
        row += 1
    end
    return meta, DataFrame(well=out_well, time=out_time, value=out_val), row
end

# A spectrum scan: every row is already one full-plate reading at one wavelength (no elapsed time,
# no temperature), so it naturally splits into one (metadata, data) pair per wavelength -- unlike a
# kinetic block (one label -> one channel) or an endpoint grid (letter-rows grouped by label). A
# 384-well plate is sometimes read across several consecutive spectrum sub-blocks in the same sheet
# (the same wavelength axis repeated for a different, non-overlapping well subset, e.g. wells A1-D24
# then E1-H24, ...) rather than one wide table -- those need to end up as ONE `LabwareRead` per
# wavelength (not one per sub-block), so this mutates a per-sheet `accum` (keyed by wavelength,
# shared across every spectrum sub-block `_parse_gen5_sheet` discovers) instead of returning its own
# results. A well appearing twice for the same wavelength (`accum`'s wells-seen set catches this)
# means these sub-blocks are *not* a clean well-batch split of one plate -- merging would be
# guessing, so that's an error rather than a silent overwrite or a silently-unmerged duplicate.
function _parse_gen5_spectrum_block!(accum::Dict{Int,NamedTuple}, M::AbstractMatrix, row_header::Int, starttime::DateTime, sheetname::AbstractString)
    wellcols = Int[]
    wells = String[]
    c = 3
    while c <= size(M, 2) && M[row_header, c] isa AbstractString
        push!(wellcols, c)
        push!(wells, M[row_header, c])
        c += 1
    end

    row = row_header + 1
    while row <= size(M, 1) && M[row, 2] isa Integer
        wavelength = Int(M[row, 2])
        entry = get!(accum, wavelength) do
            (seen=Set{String}(), well=String[], time=DateTime[], value=Float64[])
        end
        for (well, col) in zip(wells, wellcols)
            v = M[row, col]
            v isa Missing && continue
            well in entry.seen && error("well \"$well\" appears twice for wavelength $wavelength in sheet \"$sheetname\" -- these sub-blocks don't look like a well-batch split of one plate")
            push!(entry.seen, well)
            push!(entry.well, well)
            push!(entry.time, starttime)
            push!(entry.value, Float64(v))
        end
        row += 1
    end
    return row
end

function _parse_gen5_sheet(M::AbstractMatrix, sheetname::AbstractString, common::Dict{String,Any}, header::Dict)
    starttime = DateTime(header["date"], header["time"])

    row_procedure = _gen5_findlabel(M, "Procedure Details")
    from = something(row_procedure, 1)

    blocks = Tuple{Dict{String,Any},DataFrame}[]
    spectrum_accum = Dict{Int,NamedTuple}()
    while true
        row_endpoint_header = _gen5_find_endpoint_header(M; from=from)
        row_kinetic_header = _gen5_find_kinetic_header(M; from=from)
        row_spectrum_header = _gen5_find_spectrum_header(M; from=from)
        candidates = filter(!isnothing, (row_endpoint_header, row_kinetic_header, row_spectrum_header))
        isempty(candidates) && break
        first_row = minimum(candidates)

        if row_endpoint_header == first_row
            newblocks, nextrow = _parse_gen5_endpoint_block(M, row_endpoint_header, starttime)
            append!(blocks, newblocks)
            from = nextrow
        elseif row_spectrum_header == first_row
            from = _parse_gen5_spectrum_block!(spectrum_accum, M, row_spectrum_header, starttime, sheetname)
        else
            row_label = _gen5_findmatch(M, _GEN5_LABEL_RE; from=from, to=row_kinetic_header, col=1)
            isnothing(row_label) && error("sheet \"$sheetname\" has a kinetic header but no \"<name>:<label>\" block label before it")
            meta, df, nextrow = _parse_gen5_kinetic_block(M, row_label, row_kinetic_header, starttime)
            push!(blocks, (meta, df))
            from = nextrow
        end
    end
    for (wavelength, entry) in spectrum_accum
        meta = Dict{String,Any}("read_kind" => "Absorbance", "wavelength" => wavelength)
        push!(blocks, (meta, DataFrame(well=entry.well, time=entry.time, value=entry.value)))
    end
    isempty(blocks) && error("sheet \"$sheetname\" has no recognized endpoint/kinetic/spectrum block")

    plate = sheetname
    return [LabwareRead(merge(copy(common), Dict{String,Any}("plate" => plate), meta), df) for (meta, df) in blocks]
end

"""
    _parse_gen5_workbook(T::Type{<:InstrumentFormat}, path::AbstractString) -> Vector{LabwareRead}

Parse every real plate sheet (skipping any companion pivot/summary sheets) of a Gen5 .xlsx export at
`path` into one [`LabwareRead`](@ref) per (plate, channel), each tagged with `metadata["format"] = T`.
Shared by [`Epoch2Format`](@ref), [`SynergyFormat`](@ref), and [`CytationFormat`](@ref).
"""
function _parse_gen5_workbook(T::Type{<:InstrumentFormat}, path::AbstractString)
    xf = XLSX.readxlsx(path)
    sheetnames = XLSX.sheetnames(xf)
    isempty(sheetnames) && error("\"$path\" has no sheets")

    common = Dict{String,Any}("format" => T)
    common_set = false
    results = LabwareRead[]
    for sn in sheetnames
        M = xf[sn][:]
        _gen5_is_plate_sheet(M) || continue
        header = _parse_gen5_header(M)
        if !common_set
            for k in ("reader_type", "reader_serial", "software_version", "experiment_path", "protocol_path")
                haskey(header, k) && (common[k] = header[k])
            end
            common_set = true
        end
        append!(results, _parse_gen5_sheet(M, sn, common, header))
    end
    isempty(results) && error("\"$path\" has no plate sheets")
    return results
end
