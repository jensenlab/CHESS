# Synthetic destination-well instances for the naive-vs-distance-aware batching benchmark. No
# solver, no real labware needed -- just DispenseItems on an 8x12 grid (DeepWP96's shape, the plate
# size most Nimbus protocols target).

using Pourfecto: DispenseItem
using Random

const GRID_R = 8
const GRID_C = 12
const WELL_VOLUME = 200.0 # uL per active destination well

"""
    block_dims(n, R, C) -> (bh, bw)

Smallest `(bh,bw)` rectangle with `bh*bw >= n`, `bh<=R`, `bw<=C`, roughly square.
"""
function block_dims(n::Int, R::Int, C::Int)
    bh = clamp(round(Int, sqrt(n)), 1, R)
    bw = clamp(cld(n, bh), 1, C)
    while bh * bw < n && bh < R
        bh += 1
    end
    while bh * bw < n && bw < C
        bw += 1
    end
    return bh, bw
end

"""
    generate_instance(pattern::Symbol, density::Real, seed::Int) -> Vector{DispenseItem}

Build `round(density*GRID_R*GRID_C)` active destination wells (each `WELL_VOLUME` uL) on the
`GRID_R x GRID_C` grid, placed according to `pattern`:

- `:uniform_random` -- a random subset of wells (uses `seed`).
- `:clustered_block` -- a contiguous, roughly-square block of wells, randomly positioned within
  the grid (uses `seed` for placement only, not selection).
- `:row_fill` -- the first `n` wells in row-major order from the top-left corner (deterministic,
  `seed` unused).
"""
function generate_instance(pattern::Symbol, density::Real, seed::Int)
    n = round(Int, density * GRID_R * GRID_C)
    n = clamp(n, 1, GRID_R * GRID_C)
    rng = MersenneTwister(seed)

    positions = if pattern === :uniform_random
        linear = randperm(rng, GRID_R * GRID_C)[1:n]
        [CartesianIndices((GRID_R, GRID_C))[l] for l in linear]
    elseif pattern === :clustered_block
        bh, bw = block_dims(n, GRID_R, GRID_C)
        row0 = rand(rng, 1:(GRID_R - bh + 1))
        col0 = rand(rng, 1:(GRID_C - bw + 1))
        block = [CartesianIndex(row0 + r, col0 + c) for r in 0:bh-1 for c in 0:bw-1]
        block[1:n]
    elseif pattern === :row_fill
        all_positions = [CartesianIndex(r, c) for r in 1:GRID_R for c in 1:GRID_C]
        all_positions[1:n]
    else
        throw(ArgumentError("unknown pattern $pattern, expected :uniform_random, :clustered_block, or :row_fill"))
    end

    return [DispenseItem(i, positions[i], WELL_VOLUME) for i in eachindex(positions)]
end
