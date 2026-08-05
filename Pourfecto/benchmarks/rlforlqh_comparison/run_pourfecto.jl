# Run Pourfecto against the same canonical instances used by run_greedy.py / run_beam_search.py.
#
# Usage (from the CHESS repo root):
#   julia --project=Pourfecto Pourfecto/benchmarks/rlforlqh_comparison/run_pourfecto.jl \
#       [instances_dir] [results_csv] [solver_timelimit_seconds]
#
# Uses SCIP (free, open-source, handles the indicator constraints min_active_flow needs -- see
# Pourfecto/docs/src/manual/pourfecto_method.md's solver comparison table) rather than Pourfecto's
# Gurobi default, since Gurobi requires a commercial or academic license this benchmark shouldn't
# assume is present. Swap `optimizer=SCIP.Optimizer` for `optimizer=Gurobi.Optimizer` below if one is
# available -- it should only change wall-clock time, not the plan found.
#
# single_channel restricts scheduling to one well-to-well pipetting operation at a time, matching
# rlforlqh's one-tip-at-a-time action model (see examples/checkerboard/checkerboard.jl for the same
# config used to force a single-operation-per-transfer schedule). objective="min_active_flow"
# minimizes the count of nonzero scheduled operations (Pourfecto/src/pourfecto_algorithms/objectives.jl:37)
# -- the same quantity greedy.py and beam_search_lib.py report as "n_transfers".

using Pourfecto, SCIP, CSV, DataFrames

include(joinpath(@__DIR__, "to_pourfecto_labware.jl"))

function manhattan(a::Tuple{Int,Int}, b::Tuple{Int,Int})
    return abs(a[1] - b[1]) + abs(a[2] - b[2])
end

function run_one(path::AbstractString, instance_id::AbstractString, solver_timelimit::Real)
    built = instance_to_labware(path; instance_id=instance_id)

    t0 = time()
    pc = try
        pourfecto(
            [built.source], [built.target], ["single_channel"];
            objective="min_active_flow",
            priority=built.priority,
            optimizer=SCIP.Optimizer,
            solver_timelimit=solver_timelimit,
            quiet=true,
        )
    catch e
        return (success=false, n_transfers=missing, distance=missing,
                wall_time_s=time() - t0, error=sprint(showerror, e))
    end
    elapsed = time() - t0

    V = transfers(pc)
    tol = 1e-3
    active = findall(v -> v > tol, V)
    n_transfers = length(active)
    distance = sum(manhattan(built.positions[idx[1]], built.positions[idx[2]]) for idx in active; init=0)

    slk = slacks(pc)
    success = all(abs.(slk) .<= 1e-2)  # priority-0 reagents should have ~zero slack when feasible

    return (success=success, n_transfers=n_transfers, distance=distance,
            wall_time_s=elapsed, error="")
end

function main()
    instances_dir = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "instances")
    out_csv = length(ARGS) >= 2 ? ARGS[2] : joinpath(@__DIR__, "results", "pourfecto.csv")
    solver_timelimit = length(ARGS) >= 3 ? parse(Float64, ARGS[3]) : 60.0

    mkpath(dirname(out_csv))
    paths = sort(filter(f -> endswith(f, ".json"), readdir(instances_dir; join=true)))

    rows = NamedTuple[]
    for path in paths
        name = splitext(basename(path))[1]
        instance, n, k = load_instance(path)
        total_units = sum(c["amount"] for c in instance["init"])

        result = run_one(path, name, solver_timelimit)
        println("$name: success=$(result.success) transfers=$(result.n_transfers) " *
                "distance=$(result.distance) time=$(round(result.wall_time_s, digits=3))s " *
                (isempty(result.error) ? "" : "error=$(result.error)"))

        push!(rows, (solver="pourfecto", instance=name, grid_n=n, n_types=k,
                      total_units=total_units, success=result.success,
                      n_transfers=result.n_transfers, distance=result.distance,
                      wall_time_s=round(result.wall_time_s, digits=6), error=result.error))
    end

    CSV.write(out_csv, DataFrame(rows))
    println("wrote $out_csv")
end

main()
