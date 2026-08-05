# Scatterplot of measured vs. predicted pH for every entry in the empirical measurement library
# (CHESSLabConstants/test/empirical_measurements.jl). Run from this directory:
#   julia --project=. plot_ph_accuracy.jl
# Produces ph_prediction_accuracy.png alongside this script.

import Pkg
Pkg.instantiate()

using CHESSCore, CHESSLabConstants, Unitful, Test, Plots

include(joinpath(@__DIR__,"..","test","empirical_measurements.jl"))

panel_of(notes) = first(split(notes," -- "))

measured = Float64[]
predicted = Float64[]
panel = String[]
for m in EMPIRICAL_MEASUREMENTS
    push!(measured,m.measured_pH)
    push!(predicted,CHESSCore.pH(m.stock;get(m,:ph_kwargs,(;))...))
    push!(panel,panel_of(m.notes))
end

lo,hi = 0.0,14.0
plt = plot(
    [lo,hi],[lo,hi];
    label="predicted = measured",linestyle=:dash,color=:gray,
    xlabel="Measured pH",ylabel="Predicted pH",
    title="CHESSCore pH prediction accuracy\n($(length(measured)) empirical measurements)",
    titlefontsize=12,
    xlims=(lo,hi),ylims=(lo,hi),aspect_ratio=:equal,
    legend=:topleft,size=(750,780),margin=5Plots.mm,
)
for group in unique(panel)
    idx = panel.==group
    scatter!(plt,measured[idx],predicted[idx];label=group,markersize=5,markerstrokewidth=0.5)
end

outfile = joinpath(@__DIR__,"ph_prediction_accuracy.png")
savefig(plt,outfile)
println("Saved $outfile")

errors = predicted.-measured
println("Mean absolute error: ",round(sum(abs.(errors))/length(errors),digits=3))
println("Max absolute error: ",round(maximum(abs.(errors)),digits=3))
