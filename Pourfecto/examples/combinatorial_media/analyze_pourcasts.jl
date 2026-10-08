# Planned-vs-target accuracy check for the combinatorial-media example.
#
# Usage (from the CHESS repo root, after running combinatorial_media.jl):
#   julia --project=Pourfecto Pourfecto/examples/combinatorial_media/analyze_pourcasts.jl
#
# Loads every pourcast saved to pourcasts/*.json and compares each target well's planned stock
# (planned_stocks) against its requested stock (target_stocks), component by component. No solver
# is needed. Components are compared through quantity(stock, component), which returns zero for an
# absent component, rather than isapprox(::Stock, ::Stock), which fails outright whenever two stocks
# carry different component sets.
#
# A present component hits its target when isapprox(planned, target; rtol=1e-3), the tolerance used
# by test/test_problems/combinatorial_media.jl. A component the target leaves out must be planned
# at exactly zero. Water is reported separately because the example deprioritizes it, but it still
# counts toward all_targets_hit.

using Pourfecto, CHESSCore, Unitful, DataFrames, CSV

const RTOL = 1e-3

display_unit(::CHESSCore.Solid) = u"mg"
display_unit(::CHESSCore.Liquid) = u"µL"
display_unit(::CHESSCore.Organism) = u"OD*mL"

hits_target(planned, target) = iszero(target) ? iszero(planned) : isapprox(planned, target; rtol=RTOL)

function compare_stocks(scenario::AbstractString, pc::Pourcast)
    planned = planned_stocks(pc)
    requested = target_stocks(pc)
    comps = union(all_components(requested), all_components(planned))
    rows = NamedTuple[]
    for t in eachindex(requested)
        for c in comps
            u = display_unit(c)
            p = ustrip(u, quantity(planned[t], c))
            r = ustrip(u, quantity(requested[t], c))
            push!(rows, (
                scenario=scenario,
                well=t,
                component=component_to_string(c),
                unit=string(u),
                planned=p,
                target=r,
                rel_error=iszero(r) ? (iszero(p) ? 0.0 : Inf) : abs(p - r) / r,
                hit=hits_target(p, r),
            ))
        end
    end
    return DataFrame(rows)
end

function summarize(detail::DataFrame)
    return combine(groupby(detail, :scenario)) do d
        water = d[d.component .== "water", :]
        reagents = d[d.component .!= "water", :]
        (
            n_wells=length(unique(d.well)),
            reagent_checks=nrow(reagents),
            reagent_misses=count(!, reagents.hit),
            max_reagent_rel_error=maximum(reagents.rel_error),
            water_misses=count(!, water.hit),
            max_water_rel_error=maximum(water.rel_error),
            all_targets_hit=all(d.hit),
        )
    end
end

pourcast_dir = joinpath(@__DIR__, "pourcasts")
paths = sort(filter(endswith(".json"), readdir(pourcast_dir; join=true)))
isempty(paths) && error("No pourcasts found in $pourcast_dir; run combinatorial_media.jl first.")

detail = DataFrame()
for path in paths
    scenario = splitext(basename(path))[1]
    pc = json_to_pourcast(read(path, String))
    append!(detail, compare_stocks(scenario, pc))
end

summary = summarize(detail)
show(stdout, MIME"text/plain"(), summary; allcols=true)
println()

println("\nLargest relative errors per scenario:")
for d in groupby(detail, :scenario)
    worst = first(sort(d, :rel_error; rev=true), 5)
    show(stdout, MIME"text/plain"(), worst[:, [:scenario, :well, :component, :unit, :planned, :target, :rel_error]]; allcols=true)
    println()
end

CSV.write(joinpath(@__DIR__, "combinatorial_media_accuracy.csv"), summary)
