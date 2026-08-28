"""
    plot_heatmap!(plt, values::AbstractMatrix; colormap=cgrad([:white,:dodgerblue]), kwargs...)

Overlay a continuous-value heatmap of `values` onto `plt` (typically called after [`plot_grid!`](@ref)
so the heatmap sits inside the grid/gridline/lettered-row skeleton). Use `NaN` in `values` for cells
that should render as the colormap's zero/blank end rather than a real measurement.
"""
function plot_heatmap!(plt,values::AbstractMatrix;colormap=cgrad([:white,:dodgerblue]),kwargs...)
    heatmap!(plt,values;color=colormap,kwargs...)
    return plt
end
