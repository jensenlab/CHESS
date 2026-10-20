"""
    plot_heatmap!(plt, values::AbstractMatrix; colormap=cgrad([:white,:dodgerblue]), kwargs...)

Overlay a continuous-value heatmap of `values` onto `plt` (typically called after [`plot_grid!`](@ref)
so the heatmap sits inside the grid/gridline/lettered-row skeleton). Use `NaN` in `values` for cells
that should render as the colormap's zero/blank end rather than a real measurement.

Redraws the black well-grid lines on top of the heatmap fill afterward, since `heatmap!`'s opaque
per-cell coloring would otherwise paint over and hide any gridlines already drawn by `plot_grid!`.

When no `clims` is given and the finite values differ only by floating-point noise (a relative spread
of at most `1e-9`), the color range is pinned to `0 .. max` instead of being left to the backend, whose
autoscaled range is degenerate there and renders garbage (GR: `Rectangle definition is invalid`).
"""
function plot_heatmap!(plt,values::AbstractMatrix;colormap=cgrad([:white,:dodgerblue]),kwargs...)
    kwargs = _pin_degenerate_clims(values,kwargs)
    heatmap!(plt,values;color=colormap,kwargs...)
    _gridlines!(plt,size(values)...)
    return plt
end

function _pin_degenerate_clims(values,kwargs)
    haskey(kwargs,:clims) && return kwargs
    finite = filter(isfinite,[Float64(v) for v in values if v isa Real])
    isempty(finite) && return kwargs
    lo,hi = extrema(finite)
    hi - lo <= 1e-9*max(abs(hi),abs(lo),1.0) || return kwargs
    return (;kwargs...,clims=(min(0.0,lo),max(hi,floatmin())))
end
