## Well-name <-> grid-position helpers.
##
## Row lettering is `LabwarePlotting.letter_code` (bijective base-26: A..Z, AA, AB, ..., AZ, BA, ...),
## the scheme shared across the CHESS ecosystem's plate/grid plotting. This is deliberately distinct
## from `CHESSCore.plate_namer` (used by `build_location` for default naming), which wraps past column
## 26 by *repeating* a single letter (..., Y, Z, AA, BB, CC, ...) -- the two are not equivalent in
## general, so `well_to_cartesian`/`cartesian_to_well` (row/column <-> well-name conversion for actual
## well lookups) intentionally use `letter_code`, not `plate_namer`.
##
## The labware kinds Pourfecto used to define locally via `@labware` (WP96, WP384, DeepWP96,
## DeepReservoir, DeepWellColumn, DeepWellRow, brPCR96, Bottle1L/500mL/250mL, Conical50/15) are now
## all registered as CHESSCore `LocationKind`s in CHESSLabConstants (`location_kinds[:WP96]`, etc.) --
## see `build_location`/`location_kinds`, used at labware-construction call sites instead of the old
## `generate(T, name)` factory this file used to define. `stocks`/`add_stock!` moved to
## `CHESSCore.Labware` (`CHESSCore/src/locations/Labware.jl`) since they were generic
## labware-filling conveniences with no JLIMS/Pourfecto-specific logic; `length(lw::Labware)` was
## dropped outright since `CHESSCore.Labware` already defines it.

"""
    letter_code_to_int(s::AbstractString) -> Int

Inverse of `LabwarePlotting.letter_code`: decode a bijective base-26 row label ("A" -> 1, "Z" -> 26,
"AA" -> 27, ...) back to its row index. Local to Pourfecto since `well_to_cartesian` is currently the
only caller needing the inverse direction.
"""
function letter_code_to_int(s::AbstractString)
    n = 0
    for ch in s
        ('A' <= ch <= 'Z') || throw(DomainError(s,"well row letters must be A-Z"))
        n = n*26 + (Int(ch)-Int('A')+1)
    end
    return n
end

function well_to_cartesian(well::AbstractString)
    strs= String.(split(well, r"(?<=\d)(?=\D)|(?<=\D)(?=\d)"))

    if  length(strs) != 2
        throw(ArgumentError("well name: $well not in expected format, eg. A1, H12"))
    end
    letter_idx = letter_code_to_int(strs[1])
    number_idx = parse(Int64,strs[2])
    return CartesianIndex(letter_idx,number_idx)
end


function cartesian_to_well(idx::CartesianIndex)
    return "$(letter_code(idx[1]))$(idx[2])"
end
