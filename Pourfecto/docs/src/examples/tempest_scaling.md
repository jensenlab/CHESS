```@meta
EditURL = "../../../examples/tempest_scaling/tempest_scaling.jl"
```

# Large-Scale Scheduling: 240,000 Transfers on the Tempest

This example schedules 384-well plates on the Tempest at increasing scale, up
to 30 plates (11,520 wells) and 241,920 individual transfers in a single
[`pourfecto`](@ref) call. Each point in the sweep reports the number of
transfers scheduled, the wall-clock time to produce the plan, and how closely
the plan matches the requested compositions.

Every well in the problem receives a unique dose of each of 20 reagents, so
the number of transfers is known in advance (wells × 21 sources) and grows in
direct proportion to the number of plates. This makes the problem a clean
test of how solve time scales with problem size.

```julia
using Pourfecto, CHESSCore, Gurobi, Unitful, Random, Statistics
```

## Problem

There are 20 reagents, each in its own 1 L bottle, and one 1 L bottle of
water. Each target well holds 80 µL: a dose of every reagent drawn uniformly
between 0.1 and 1.0 µL of that reagent's stock, with water making up the
remaining volume. Every dose is different, so no two wells share a recipe.

The sources are bottles, so the Tempest is the only bundled configuration
that can be used. It is the only one that aspirates from a bottle
(`:Bottle1L`, `:Bottle500mL`, `:Conical50`, and similar) and dispenses into a
384-well plate. The other configurations either cannot hold a bottle on the
deck or cannot dispense into a `:WP384`.

The function below builds the sources and `n_plates` target plates. The
random number generator is seeded so the doses are reproducible.

```julia
const N_REAGENTS = 20
const WELL_VOLUME = 80u"µL"
const DOSE_RANGE = (0.1u"µL", 1.0u"µL")

function build_problem(n_plates::Int; seed::Int=48207531)
    rng = Random.MersenneTwister(seed)

    reagents = [string_to_component("R$i", Solid) for i in 1:N_REAGENTS]
    water = string_to_component("water", Liquid)

    # Multiplying a volume by a stock rescales the stock to that volume at a
    # fixed reagent-to-water ratio. The same definition fills each source bottle
    # and doses each well.
    reagent_stocks = [100u"g" * r + 100u"mL" * water for r in reagents]

    sources = Labware[]
    for stock in reagent_stocks
        bottle = build_location(location_kinds[:Bottle1L])
        children(bottle)[1].stock = 900u"mL" * stock
        push!(sources, bottle)
    end
    water_bottle = build_location(location_kinds[:Bottle1L])
    children(water_bottle)[1].stock = 900u"mL" * water
    push!(sources, water_bottle)

    targets = Labware[]
    for _ in 1:n_plates
        plate = build_location(location_kinds[:WP384])
        for well in children(plate)
            doses = [DOSE_RANGE[1] + rand(rng) * (DOSE_RANGE[2] - DOSE_RANGE[1])
                     for _ in 1:N_REAGENTS]
            well.stock = (WELL_VOLUME - sum(doses)) * water
            for (stock, dose) in zip(reagent_stocks, doses)
                well.stock += dose * stock
            end
        end
        push!(targets, plate)
    end

    return (sources=sources, targets=targets, reagents=reagents)
end
```

## Solver and objective

This example uses two settings that matter at this scale.

**The default `"min_cost_flow"` objective.** Every other scheduling objective
(`"min_active_flow"`, `"min_config"`, and the rest) turns the scheduling
phase into a mixed-integer program, which becomes intractable at thousands of
wells. The default objective keeps scheduling a linear flow problem. See
[Time complexity](@ref pourfecto_complexity) for the structure of both
phases.

**A solver with a fast barrier QP method.** The planning phase minimizes a
sum of squared slacks regardless of the scheduling objective, so it is a
quadratic program. In testing, HiGHS did not reach optimality within a 60 s
limit per solve on a single plate. Gurobi solves the same plan to optimality
in a few seconds, as the results below show. This example passes
`Gurobi.Optimizer`, which requires a Gurobi license. Any solver that supports
quadratic objectives can be substituted.

Water is deprioritized relative to the reagents, so the plan matches the
reagent doses exactly and absorbs any rounding in the total volume with
water.

```julia
priority = PriorityDict("water" => typemax(UInt64))
```

## Running one point

A single point builds the problem, calls [`pourfecto`](@ref) restricted to
the `"tempest"` configuration, and times the call. The number of transfers is
the count of nonzero entries in [`transfers`](@ref).

```julia
function run_point(n_plates::Int; solver_timelimit=300)
    problem = build_problem(n_plates)

    pc, elapsed = @timed pourfecto(
        problem.sources, problem.targets, ["tempest"];
        priority=priority,
        optimizer=Gurobi.Optimizer,
        solver_timelimit=solver_timelimit,
        quiet=true,
    )

    n_transfers = count(v -> v > 1e-3, transfers(pc))
    return (pc=pc, reagents=problem.reagents, n_transfers=n_transfers, seconds=elapsed)
end
```

## Measuring accuracy

Accuracy compares what the plan delivers, [`planned_stocks`](@ref), with what
was requested, [`target_stocks`](@ref). The error for each well and reagent
is the absolute difference in mass. Water is excluded because it is
deprioritized.

```julia
function reagent_errors(pc, reagents)
    planned = planned_stocks(pc)
    requested = target_stocks(pc)
    errors = [abs(ustrip(u"g", quantity(planned[t], r)) - ustrip(u"g", quantity(requested[t], r)))
              for t in eachindex(planned) for r in reagents]
    return (mean=mean(errors), max=maximum(errors))
end
```

## Running the sweep

The first call to `pourfecto` includes Julia compilation and solver startup,
which are one-time costs unrelated to problem size. An untimed call on a
single plate absorbs them before the sweep begins.

```julia
run_point(1)

for n_plates in [1, 2, 5, 10, 20, 30]
    result = run_point(n_plates)
    errors = reagent_errors(result.pc, result.reagents)
    println("$n_plates plates: $(result.n_transfers) transfers, ",
            "$(round(result.seconds, digits=1)) s, ",
            "max error $(errors.max) g")
end
```

## Results

The table below shows one run on an Apple M3 (8 cores, 16 GB) with Julia
1.12.4 and Gurobi 1.9.2 (Gurobi.jl). Every solve, in both the planning and
scheduling phases, reached optimality well inside the 300 s limit. The raw
data is in `tempest_scaling_results.csv` alongside this example.

| Plates | Wells  | Transfers | Wall time (s) | Mean error (g) | Max error (g) |
|-------:|-------:|----------:|--------------:|---------------:|--------------:|
| 1      | 384    | 8,064     | 4.7           | 2.48e-5        | 5.00e-5       |
| 2      | 768    | 16,128    | 9.0           | 2.50e-5        | 5.00e-5       |
| 5      | 1,920  | 40,320    | 22.0          | 2.50e-5        | 5.00e-5       |
| 10     | 3,840  | 80,640    | 44.4          | 2.50e-5        | 5.00e-5       |
| 20     | 7,680  | 161,280   | 92.0          | 2.50e-5        | 5.00e-5       |
| 30     | 11,520 | 241,920   | 148.0         | 2.50e-5        | 5.00e-5       |

Three observations follow from the table.

- **Transfers are exactly dense.** The transfer count equals the number of
  wells times 21 at every point. Each well needs a nonzero amount of every
  reagent and of water, and the plan schedules exactly those transfers.
- **Wall time grows roughly linearly with problem size.** Going from 1 to 30
  plates multiplies the number of wells by 30 and the wall time by about 32.
  The cost is between 4.5 and 4.9 s per plate, or roughly 12 to 13 ms per
  well, at every scale from 2 plates upward.
- **Accuracy does not change with scale.** The mean and maximum errors
  stay at about 2.5e-5 g and 5.0e-5 g across the whole sweep. This is a
  fixed error scale of the solver rather than a shortfall that grows with the
  number of wells.

Wall time depends on the machine and solver version, so the absolute numbers
will differ elsewhere. The scaling behavior is the result to expect.

The full benchmark, including the script that produced these numbers, is in
`Pourfecto/benchmarks/combinatorial_media_scaling` in the repository.

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

