# Produces a structurally-identical but content-scrubbed copy of a real Gen5 .xlsx export, safe to
# commit as a regression fixture. Experiment/protocol paths, reader serial number, real dates, and
# barcode-style plate/sheet names are replaced with fixed placeholders. Every numeric measurement
# cell from "Procedure Details" onward -- well values, temperature readings, and (on companion pivot
# sheets) their reshaped duplicates -- is replaced with a random value scaled to roughly the same
# order of magnitude as the original (a random 0.3x-1.7x multiplier), so the output still "reads" as
# realistic Absorbance/Fluorescence-shaped data without exposing the real result. Column-index header
# rows ([missing, missing, 1, 2, ...]) are protected from that blanket scrub since the parser depends
# on their exact values. Kinetic elapsed-time cells are left untouched (a timing pattern isn't
# identifying) -- only the absolute Date/Time header is faked.
#
# Usage:
#   julia --project=CHESSParsers CHESSParsers/dev/deidentify_fixture.jl <source.xlsx> <dest.xlsx>

using CHESSParsers, XLSX, Random, Dates
import CHESSParsers: _gen5_is_plate_sheet, _gen5_findlabel, _TAKE3TRIO_SAMPLE_SHEET_RE, _take3trio_findcell

const PLACEHOLDER_DATE = Date(2020, 1, 1)
const PLACEHOLDER_TIME = Dates.Time(9, 0, 0)
const PLACEHOLDER_EXPERIMENT_PATH = "C:\\Users\\Public\\Documents\\Experiments\\deidentified.xpt"
const PLACEHOLDER_PROTOCOL_PATH = "C:\\Users\\Public\\Documents\\Protocols\\deidentified.prt"

_fuzz(rng, v::Integer) = round(Int, abs(v) * (0.3 + 1.4rand(rng)))
_fuzz(rng, v::AbstractFloat) = round(abs(v) * (0.3 + 1.4rand(rng)), digits=3)

# `M = ws[:]` is indexed relative to the sheet's used range, not absolute worksheet coordinates --
# this converts an (i,j) index into `M` to the (row,col) `ws[...]` actually needs.
_wscoord(r0, c0, i, j) = (r0 + i - 1, c0 + j - 1)

function _scrub_header!(ws, M, r0, c0)
    for (label, replacement) in (
        "Experiment File Path:" => PLACEHOLDER_EXPERIMENT_PATH,
        "Protocol File Path:"   => PLACEHOLDER_PROTOCOL_PATH,
    )
        i = _gen5_findlabel(M, label)
        isnothing(i) || (ws[_wscoord(r0, c0, i, 2)...] = replacement)
    end
    i = _gen5_findlabel(M, "Reader Serial Number:")
    if !isnothing(i)
        ws[_wscoord(r0, c0, i, 2)...] = M[i, 2] isa AbstractString ? "SIM0000A" : 99999999
    end
    i = _gen5_findlabel(M, "Date")
    isnothing(i) || (ws[_wscoord(r0, c0, i, 2)...] = PLACEHOLDER_DATE)
    i = _gen5_findlabel(M, "Time")
    isnothing(i) || (ws[_wscoord(r0, c0, i, 2)...] = PLACEHOLDER_TIME)
end

# A column-index header row (e.g. [missing, missing, 1, 2, ..., N]) -- both a real channel's and a
# computed-summary block's grid have one; both need their column numbers left untouched. Some
# endpoint exports also label each data row with a bare wavelength number (no "<name>:<label>"
# string) instead -- that trailing column is a channel label too, not a measurement, so it needs the
# same protection as the header row itself; likewise a spectrum-scan block's own Wavelength column
# (col 2 of its data rows). Protection is applied column-wide from the header row onward (not
# strictly bounded to that one block) -- broader than necessary, but harmless: over-protecting a
# structural-shaped column just leaves a few wavelength/label numbers unscrubbed, never real
# measurement data.
function _scrub_values!(ws, M, r0, c0, rng, from::Int)
    protect = falses(size(M, 1), size(M, 2))
    for i in from:size(M, 1)
        if M[i, 1] isa Missing && M[i, 2] isa Missing && M[i, 3] isa Integer && M[i, 3] == 1
            protect[i, :] .= true
            ncols = 0
            c = 3
            while c <= size(M, 2) && M[i, c] isa Number
                ncols += 1
                c += 1
            end
            labelcol = 3 + ncols
            labelcol <= size(M, 2) && (protect[i:end, labelcol] .= true)
        elseif M[i, 2] isa AbstractString && M[i, 2] == "Wavelength"
            protect[i, :] .= true
            protect[i:end, 2] .= true
        end
    end

    for i in from:size(M, 1), j in 1:size(M, 2)
        protect[i, j] && continue
        v = M[i, j]
        v isa Real || continue
        ws[_wscoord(r0, c0, i, j)...] = _fuzz(rng, v)
    end
end

# Companion pivot/summary sheets: row 1 is a header (well names), column 1 is a read-index/elapsed
# time -- neither is sensitive. Every other cell is a reshaped duplicate of real measurement data.
function _scrub_pivot_sheet!(ws, M, r0, c0, rng)
    for i in 2:size(M, 1), j in 2:size(M, 2)
        v = M[i, j]
        v isa Real || continue
        ws[_wscoord(r0, c0, i, j)...] = _fuzz(rng, v)
    end
end

# Take3 Trio sheets ("Blank Read"/"Sample Read #N") don't have the "Software Version"/"Procedure
# Details" structure the generic Gen5 scrub relies on, so they get their own pair of scrub functions.
# Blank Read: fuzz every Real cell after the "Location" header row except the Location column itself
# (a real well ID, not a measurement). Sample Read: fuzz only the two SPL#-value columns of each
# slide, never the marker column immediately after them (bare 260/280 Reals there are structural --
# they select which channel a row feeds, the same role a Gen5 endpoint block's column-index header or
# bare-wavelength label column plays) or the letter/SPL# columns (strings, not measurements).
function _take3trio_scrub_blank_sheet!(ws, M, r0, c0, rng)
    _scrub_header!(ws, M, r0, c0)
    loc = _take3trio_findcell(M, "Location")
    isnothing(loc) && return
    header_row, loc_col = loc
    for i in (header_row+1):size(M, 1), j in 1:size(M, 2)
        j == loc_col && continue
        v = M[i, j]
        v isa Real || continue
        ws[_wscoord(r0, c0, i, j)...] = _fuzz(rng, v)
    end
end

function _take3trio_scrub_sample_sheet!(ws, M, r0, c0, rng)
    _scrub_header!(ws, M, r0, c0)
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
    isnothing(slide_row) && return
    for letter_col in letter_cols, j in (letter_col+1):(letter_col+2), i in (slide_row+1):size(M, 1)
        v = M[i, j]
        v isa Real || continue
        ws[_wscoord(r0, c0, i, j)...] = _fuzz(rng, v)
    end
end

function _synthetic_plate_name(original::AbstractString, idx::Int)
    occursin(r"^Plate \d+( - Sheet\d*)?$", original) && return original # already generic Gen5 default
    return "SIM" * lpad(string(idx), 5, '0')
end

"""
    deidentify_fixture(src::AbstractString, dest::AbstractString) -> String

Write a de-identified copy of the Gen5 export at `src` to `dest`, safe to commit. See module
docstring above for exactly what's scrubbed vs. preserved. Returns `dest`.
"""
function deidentify_fixture(src::AbstractString, dest::AbstractString)
    mkpath(dirname(dest))
    cp(src, dest; force=true)
    rng = MersenneTwister(hash(basename(src)))
    plate_counter = 0

    XLSX.openxlsx(dest; mode="rw") do xf
        for sn in XLSX.sheetnames(xf)
            ws = xf[sn]
            M = ws[:]
            d = XLSX.get_dimension(ws)
            r0, c0 = d.start.row_number, d.start.column_number

            if sn == "Blank Read"
                _take3trio_scrub_blank_sheet!(ws, M, r0, c0, rng)
                continue
            elseif occursin(_TAKE3TRIO_SAMPLE_SHEET_RE, sn)
                _take3trio_scrub_sample_sheet!(ws, M, r0, c0, rng)
                continue
            end

            if !_gen5_is_plate_sheet(M)
                _scrub_pivot_sheet!(ws, M, r0, c0, rng)
                continue
            end
            plate_counter += 1

            _scrub_header!(ws, M, r0, c0)
            row_procedure = _gen5_findlabel(M, "Procedure Details")
            _scrub_values!(ws, M, r0, c0, rng, something(row_procedure, 1))

            newname = _synthetic_plate_name(sn, plate_counter)
            newname == sn || XLSX.rename!(ws, newname)
        end
    end
    return dest
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: julia deidentify_fixture.jl <source.xlsx> <dest.xlsx>")
    out = deidentify_fixture(ARGS[1], ARGS[2])
    println("wrote ", out)
end
