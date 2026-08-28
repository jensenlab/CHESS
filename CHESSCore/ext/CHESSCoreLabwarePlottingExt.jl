"""
    CHESSCoreLabwarePlottingExt

Adds the canonical base plot for [`CHESSCore.Labware`](@ref) -- a grid, gridlines, lettered rows, and
a title, built on `LabwarePlotting`'s shared primitives -- and an overlay for visualizing each well's
stock quantity. Loads only when both `LabwarePlotting` and `Plots` are also `using`'d; `CHESSCore`'s
base package has no hard dependency on either.

Downstream packages with their own `Labware`-decorating needs (e.g. `Pourfecto`'s non-wellplate
marker shapes, well-highlighting) build on `plot(l::Labware)` here rather than redefining it.
"""
module CHESSCoreLabwarePlottingExt

using CHESSCore, LabwarePlotting, Plots, Unitful

function Plots.plot(l::Labware; kwargs...)
    R, C = shape(l)
    return LabwarePlotting.plot_grid(trues(R,C); title=name(l), kwargs...)
end

function CHESSCore.plot_well_heatmap!(plt, l::Labware; kwargs...)
    stocks = stock.(children(l))
    quants = map(s -> s isa Empty ? 0 : ustrip(uconvert(u"µL",quantity(s))), stocks)
    LabwarePlotting.plot_heatmap!(plt, quants; kwargs...)
    return plt
end

end # module CHESSCoreLabwarePlottingExt
