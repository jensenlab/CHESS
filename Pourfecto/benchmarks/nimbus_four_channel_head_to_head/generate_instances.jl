# Synthetic transfer designs for the single- vs 4-channel Nimbus benchmark (see README.md). No
# solver: each design is an (n reagents x 96 wells) volume matrix, 30 uL wherever a reagent goes.

using Pourfecto, CHESSCore, DataFrames, Random

const SCHEMES = [:uniform50, :split25_75, :random10_90]
const TRANSFER_VOLUME = 30.0 # uL per (reagent, well) transfer
const N_WELLS = 96 # one DeepWP96 target plate

"""
    reagent_probabilities(scheme, n, rng) -> Vector{Float64}

Per-reagent probability of being dispensed into any given well:
- `:uniform50`: every reagent 0.5.
- `:split25_75`: the first half of the reagents (rounded up) 0.25, the rest 0.75.
- `:random10_90`: each reagent its own probability, uniform on [0.1, 0.9].
"""
function reagent_probabilities(scheme::Symbol, n::Int, rng::AbstractRNG)
    scheme === :uniform50 && return fill(0.5, n)
    scheme === :split25_75 && return [i <= cld(n, 2) ? 0.25 : 0.75 for i in 1:n]
    scheme === :random10_90 && return 0.1 .+ 0.8 .* rand(rng, n)
    throw(ArgumentError("unknown scheme $scheme, expected one of $SCHEMES"))
end

"""
    generate_design(scheme, n, seed) -> DataFrame

`n x N_WELLS` design: row `i` is reagent `i`, and each well independently gets `TRANSFER_VOLUME` of
reagent `i` with that reagent's probability. Seeded per `(scheme, n, seed)`, so every instance is
reproducible and schemes don't share draws.
"""
function generate_design(scheme::Symbol, n::Int, seed::Int)
    rng = MersenneTwister(10_000 * findfirst(==(scheme), SCHEMES) + 100 * n + seed)
    p = reagent_probabilities(scheme, n, rng)
    design = DataFrame(zeros(n, N_WELLS), :auto)
    for i in 1:n, w in 1:N_WELLS
        rand(rng) < p[i] && (design[i, w] = TRANSFER_VOLUME)
    end
    return design
end

"""
    build_labware(tag, n) -> (sources, targets)

`n` 50 mL conicals and one 96-well deep-well plate, with names unique to `tag` (labware names must
be unique within a slotting).
"""
function build_labware(tag::AbstractString, n::Int)
    sources = Labware[build_location(location_kinds[:Conical50], "$(tag)_reagent$i") for i in 1:n]
    targets = Labware[build_location(location_kinds[:DeepWP96], "$(tag)_plate")]
    return sources, targets
end
