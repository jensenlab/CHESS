## Well-name <-> grid-position helpers.
##
## Deliberately not moved to CHESSCore: CHESSCore's own name generator (`plate_namer`, used by
## `build_location`) wraps past column 26 by *repeating* a single letter (..., Y, Z, AA, BB, CC, ...)
## rather than incrementing a two-letter code (..., Y, Z, AA, AB, AC, ...) the way `plate_alphabet`
## does here. No labware kind Pourfecto uses has more than 16 rows, so the difference is latent, but
## the two are not equivalent in general -- keeping this implementation local avoids silently
## changing well-naming behavior for any future >26-row labware kind.
##
## The labware kinds Pourfecto used to define locally via `@labware` (WP96, WP384, DeepWP96,
## DeepReservoir, DeepWellColumn, DeepWellRow, brPCR96, Bottle1L/500mL/250mL, Conical50/15) are now
## all registered as CHESSCore `LocationKind`s in CHESSLabConstants (`location_kinds[:WP96]`, etc.) --
## see `build_location`/`location_kinds`, used at labware-construction call sites instead of the old
## `generate(T, name)` factory this file used to define. `stocks`/`add_stock!` moved to
## `CHESSCore.Labware` (`CHESSCore/src/locations/Labware.jl`) since they were generic
## labware-filling conveniences with no JLIMS/Pourfecto-specific logic; `length(lw::Labware)` was
## dropped outright since `CHESSCore.Labware` already defines it.

const plate_alphabet = vcat(["$l" for l in 'A':'Z' ],["A$l" for l in 'A':'Z'])


function well_to_cartesian(well::AbstractString)
    strs= String.(split(well, r"(?<=\d)(?=\D)|(?<=\D)(?=\d)"))

    if  length(strs) != 2
        throw(ArgumentError("well name: $well not in expected format, eg. A1, H12"))
    end
    letter_idx = findfirst(x-> x == strs[1], plate_alphabet)
    if isnothing(letter_idx)
        throw(DomainError("Well row not within supplied plate row alphabet"))
    end
    number_idx = parse(Int64,strs[2])
    return CartesianIndex(letter_idx,number_idx)
end


function cartesian_to_well(idx::CartesianIndex)
    return "$(plate_alphabet[idx[1]])$(idx[2])"
end
