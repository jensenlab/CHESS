# Scaling sweep for the combinatorial-media problem (see generate_problem.jl and README.md).
#
# Usage (from the CHESS repo root):
#   julia --project=Pourfecto Pourfecto/benchmarks/combinatorial_media_scaling/run_benchmark.jl \
#       [results_csv] [solver_timelimit_seconds]
#
# Sweeps n_plates in [1, 2, 5, 10, 20, 30] (384-well WP384 plates), the last point reaching
# ~230,000 individual reagent transfers. Uses the default "min_cost_flow" scheduling objective (not
# one of the MILP objectives -- see docs/src/manual/pourfecto_method.md), but note that Pourfecto's
# *planning* phase always minimizes a sum-of-squared-slacks objective regardless of the `objective`
# keyword -- so every pourfecto() call solves a QP, not a plain LP, in that phase. HiGHS solves QPs
# with an active-set method that scales poorly here: it hadn't reached optimality after hitting a
# 60s-per-solve cap twice on just 1 plate (384 wells, 255s wall time, sub-optimal). Gurobi's barrier
# QP solver handles the same problem in ~9s to full optimality, and scales sub-linearly with problem
# size in testing (5x the plates was only ~1.8x the time) -- so this benchmark defaults to Gurobi.
# If no Gurobi license is available, swap in HiGHS.Optimizer below, but expect it to be dramatically
# slower and possibly time-limited even at small plate counts (see README.md).

using Pourfecto, CHESSCore, Gurobi, CSV, DataFrames, Statistics

include(joinpath(@__DIR__, "generate_problem.jl"))

function assess_accuracy(pc, reagents)
    planned = planned_stocks(pc)
    requested = target_stocks(pc)
    abs_errors = Float64[]
    for t in eachindex(planned)
        for r in reagents
            planned_qty = ustrip(u"g", quantity(planned[t], r))
            requested_qty = ustrip(u"g", quantity(requested[t], r))
            push!(abs_errors, abs(planned_qty - requested_qty))
        end
    end
    return (mean_abs_error_g=mean(abs_errors), max_abs_error_g=maximum(abs_errors))
end

function run_one(n_plates::Int, solver_timelimit::Real)
    built = build_problem(n_plates)

    pc, elapsed = @timed pourfecto(
        built.source_labware, built.target_plates, ["tempest"];
        priority=built.priority,
        optimizer=Gurobi.Optimizer,
        solver_timelimit=solver_timelimit,
        quiet=true,
    )

    V = transfers(pc)
    tol = 1e-3
    n_transfers = count(v -> v > tol, V)

    acc = assess_accuracy(pc, built.reagents)

    n_wells = 384 * n_plates

    return (n_plates=n_plates, n_wells=n_wells, n_transfers=n_transfers,
            wall_time_s=round(elapsed, digits=3),
            mean_abs_error_g=acc.mean_abs_error_g, max_abs_error_g=acc.max_abs_error_g)
end

function main()
    out_csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "results", "scaling_results.csv")
    solver_timelimit = length(ARGS) >= 2 ? parse(Float64, ARGS[2]) : 300.0

    mkpath(dirname(out_csv))

    sweep = [1, 2, 5, 10, 20, 30]
    rows = NamedTuple[]
    for n_plates in sweep
        result = run_one(n_plates, solver_timelimit)
        println("n_plates=$(result.n_plates) n_wells=$(result.n_wells) " *
                "n_transfers=$(result.n_transfers) time=$(result.wall_time_s)s " *
                "mean_abs_error=$(result.mean_abs_error_g)g max_abs_error=$(result.max_abs_error_g)g")
        push!(rows, result)
    end

    CSV.write(out_csv, DataFrame(rows))
    println("wrote $out_csv")
end

main()
