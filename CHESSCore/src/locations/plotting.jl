"""
    plot_well_heatmap!(plt, l::Labware; kwargs...)

Overlay a heatmap of each well's stock quantity (in µL; `Empty` wells render as zero) onto `plt`.

Extension point: the actual implementation lives in `CHESSCoreLabwarePlottingExt`, loaded
automatically once both `LabwarePlotting` and `Plots` are also `using`'d. `CHESSCore` itself has no
hard `Plots` dependency.
"""
function plot_well_heatmap! end
