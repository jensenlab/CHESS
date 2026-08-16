# Reconstruction-time scaling, broken out by operation type.
#
# Usage (from the CHESS repo root):
#   julia --project=CHESSDatabase CHESSDatabase/benchmarks/reconstruction_scaling/run_benchmark.jl \
#       [results_csv]
#
# Measures `reconstruct_location` wall time (setup excluded) as a location's operation history
# grows, for four scenarios:
#   - transfer : a single linear transfer chain (bottle -> w1 -> w2 -> ... -> target), isolating
#                transfer-ancestor *chain depth* -- see ChainState in ../common/lab_simulator.jl for
#                why this is expected to be the worst case (a recursive CTE walks this chain
#                backward on every reconstruction).
#   - move     : one plate repeatedly toggled between two shelves.
#   - read     : repeated reads recorded on one assay well.
#   - env      : repeated `Temperature` changes on a rotating ancestor of one assay well.
#   - realistic: a ~100-labware lab (20 bottles, 60 intermediate plates, 20 assay plates) driven by
#                a weighted mix of all four operation types approximating a real day, swept toward
#                the ~100,000 operations/day estimate.
#
# Each scenario keeps one growing ledger across its sweep (extending it by the gap between
# consecutive sweep points, not rebuilding from scratch), so the reported `wall_time_s` reflects
# reconstructing a location out of a ledger that has genuinely accumulated that many prior
# operations -- matching how CHESSDatabase is actually used.

using CHESSCore, CHESSDatabase, CHESSLabConstants, Random, CSV, DataFrames, Dates

include(joinpath(@__DIR__, "..", "common", "lab_simulator.jl"))

const SCRATCH_DIR = mktempdir()
const WALL_TIME_CAP_S = 60.0  # stop growing a sweep once a single reconstruction exceeds this

time_reconstruction(target) = (@elapsed reconstruct_location(location_id(target)))

"""
    run_isolation_sweep(op_type::Symbol, sizes::Vector{Int}; seed=1)

Grow one ledger for `op_type` (:transfer, :move, :read, or :env) through the cumulative operation
counts in `sizes`, timing `reconstruct_location` on the relevant target after each point. Stops
early (returning the rows collected so far) once a reconstruction exceeds `WALL_TIME_CAP_S`.
"""
function run_isolation_sweep(op_type::Symbol, sizes::Vector{Int}; seed::Int=1)
    dbfile = joinpath(SCRATCH_DIR, "iso_$(op_type).db")
    fresh_db(dbfile)
    rng = MersenneTwister(seed)
    rows = NamedTuple[]

    if op_type == :transfer
        state = start_transfer_chain(maximum(sizes))
        n_prev = 0
        for n in sizes
            target = extend_chain!(state, n - n_prev)
            n_prev = n
            t = time_reconstruction(target)
            push!(rows, (scenario="transfer", n_operations=n, wall_time_s=round(t, digits=4),
                target_description="chain well $n of $n"))
            println("transfer n=$n wall_time=$(round(t,digits=4))s"); flush(stdout)
            t > WALL_TIME_CAP_S && break
        end
    else
        lab = build_realistic_lab(n_bottles=5, n_intermediate_plates=3, n_assay_plates=2)
        weights = op_type == :move ? (transfer=0.0, move=1.0, read=0.0, env=0.0) :
                  op_type == :read ? (transfer=0.0, move=0.0, read=1.0, env=0.0) :
                  (transfer=0.0, move=0.0, read=0.0, env=1.0)
        target = op_type == :move ? lab.mobile_plate : lab.assay_wells[1]
        n_prev = 0
        for n in sizes
            run_operations!(rng, lab, n - n_prev; weights=weights)
            n_prev = n
            t = time_reconstruction(target)
            push!(rows, (scenario=String(op_type), n_operations=n, wall_time_s=round(t, digits=4),
                target_description="fixed $(op_type) target after $n operations"))
            println("$op_type n=$n wall_time=$(round(t,digits=4))s"); flush(stdout)
            t > WALL_TIME_CAP_S && break
        end
    end
    return rows
end

"""
    run_realistic_sweep(sizes::Vector{Int}; seed=1)

Grow one ~100-labware lab through `sizes` cumulative operations (a transfer-heavy mix approximating
a real day: 70% transfer, 15% move, 10% read, 5% env), timing reconstruction of both a representative
assay well and the whole lab root after each point.
"""
function run_realistic_sweep(sizes::Vector{Int}; seed::Int=1)
    dbfile = joinpath(SCRATCH_DIR, "realistic.db")
    fresh_db(dbfile)
    rng = MersenneTwister(seed)
    lab = build_realistic_lab()
    weights = (transfer=0.70, move=0.15, read=0.10, env=0.05)
    well_target = lab.assay_wells[1]
    root_target = lab.lab
    rows = NamedTuple[]
    n_prev = 0
    well_capped = false
    root_capped = false
    for n in sizes
        run_operations!(rng, lab, n - n_prev; weights=weights)
        n_prev = n
        t_well = well_capped ? missing : time_reconstruction(well_target)
        t_root = root_capped ? missing : time_reconstruction(root_target)
        push!(rows, (scenario="realistic_well", n_operations=n,
            wall_time_s=ismissing(t_well) ? missing : round(t_well, digits=4),
            target_description="fixed assay well after $n mixed operations"))
        push!(rows, (scenario="realistic_root", n_operations=n,
            wall_time_s=ismissing(t_root) ? missing : round(t_root, digits=4),
            target_description="lab root after $n mixed operations"))
        println("realistic n=$n well_time=$(t_well)s root_time=$(t_root)s"); flush(stdout)
        !ismissing(t_well) && t_well > WALL_TIME_CAP_S && (well_capped = true)
        !ismissing(t_root) && t_root > WALL_TIME_CAP_S && (root_capped = true)
        well_capped && root_capped && break
    end
    return rows
end

function main()
    out_csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "results", "reconstruction_scaling.csv")
    mkpath(dirname(out_csv))

    isolation_sizes = [10, 50, 100, 500, 1000, 2500, 5000, 10000]
    realistic_sizes = [100, 1000, 5000, 10000, 25000, 50000, 100000]

    rows = NamedTuple[]
    for op_type in (:transfer, :move, :read, :env)
        append!(rows, run_isolation_sweep(op_type, isolation_sizes))
    end
    append!(rows, run_realistic_sweep(realistic_sizes))

    df = DataFrame(rows)
    CSV.write(out_csv, df)
    println("wrote $out_csv")
end

main()
