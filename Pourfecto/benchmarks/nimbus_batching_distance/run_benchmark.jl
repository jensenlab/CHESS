# Naive-vs-distance-aware batching benchmark for the Nimbus compiler (see README.md).
#
# Usage (from the CHESS repo root):
#   julia --project=Pourfecto Pourfecto/benchmarks/nimbus_batching_distance/run_benchmark.jl \
#       [results_csv]
#
# Unlike the other benchmarks in this folder, this one exercises only the compile-stage batching
# logic (Pourfecto.cluster_batches/order_greedy/order_exact, src/compiler/batching.jl) directly on
# synthetic DispenseItems -- no pourfecto() solve, no Gurobi/SCIP/HiGHS license needed. It sweeps
# two axes per instance: clustering (naive first-fit vs. the real distance-aware cluster_batches)
# and within-batch ordering (:greedy vs. :exact), scoring each of the four combinations by total
# intra-batch consecutive-dispense grid distance -- exactly what order_greedy/order_exact optimize.

using Pourfecto, Unitful, CSV, DataFrames

include(joinpath(@__DIR__, "naive_batching.jl"))
include(joinpath(@__DIR__, "generate_instances.jl"))

const CAPACITY = ustrip(u"µL", dispense_channels(head(configurations["nimbus"]))[1].capacity)

function total_distance(batches::Vector{Vector{DispenseItem}}, method::Symbol)
    total = 0.0
    for batch in batches
        ordered = order_batch(batch, method)
        for i in 1:length(ordered)-1
            total += grid_distance(ordered[i].position, ordered[i+1].position)
        end
    end
    return total
end

function run_one(pattern::Symbol, density::Real, seed::Int)
    items = generate_instance(pattern, density, seed)

    naive = naive_cluster_batches(items, CAPACITY)
    default = cluster_batches(items, CAPACITY)

    naive_greedy = total_distance(naive, :greedy)
    naive_exact = total_distance(naive, :exact)
    default_greedy = total_distance(default, :greedy)
    default_exact = total_distance(default, :exact)

    pct_improve(baseline, improved) = baseline == 0 ? 0.0 : round(100 * (baseline - improved) / baseline, digits=1)

    return (
        pattern=pattern, density=density, seed=seed, n_items=length(items),
        naive_n_batches=length(naive), default_n_batches=length(default),
        naive_greedy_distance=round(naive_greedy, digits=2),
        naive_exact_distance=round(naive_exact, digits=2),
        default_greedy_distance=round(default_greedy, digits=2),
        default_exact_distance=round(default_exact, digits=2),
        clustering_improvement_pct=pct_improve(naive_greedy, default_greedy), # naive:greedy -> default:greedy
        ordering_improvement_pct=pct_improve(default_greedy, default_exact), # default:greedy -> default:exact
    )
end

function main()
    out_csv = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "results", "distance_results.csv")
    mkpath(dirname(out_csv))

    densities = [0.1, 0.25, 0.5, 0.75, 1.0]
    patterns_with_seeds = [
        (:uniform_random, [1, 2, 3]),
        (:clustered_block, [1, 2, 3]), # seed only shifts block placement
        (:row_fill, [1]), # deterministic, seed unused
    ]

    rows = NamedTuple[]
    for (pattern, seeds) in patterns_with_seeds, density in densities, seed in seeds
        result = run_one(pattern, density, seed)
        println("pattern=$(result.pattern) density=$(result.density) seed=$(result.seed) " *
                "n_items=$(result.n_items) naive_batches=$(result.naive_n_batches) " *
                "default_batches=$(result.default_n_batches) " *
                "clustering_improvement=$(result.clustering_improvement_pct)% " *
                "ordering_improvement=$(result.ordering_improvement_pct)%")
        push!(rows, result)
    end

    CSV.write(out_csv, DataFrame(rows))
    println("wrote $out_csv")
end

main()
