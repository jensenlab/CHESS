"""
    plot_plate_data(run_map::RunMap, plate_maps::AbstractVector{<:Pair}, values::AbstractDict;
                     relations=[:positive, :negative], nodes=nothing) -> Dict{String,Plots.Plot}

Per-plate heatmap of `values` over each plate's wells -- the restored, generalized successor to
`CHESSQC.plot_plate_data` (a bare `heatmap`), now drawn inside the shared grid/gridline/lettered-row
skeleton. One plot per plate with at least one resolvable well, keyed by the `plate_maps` label
(stringified).

Extension point: the actual implementation lives in `CHESSProcessingPlottingExt`, loaded
automatically once `LabwarePlotting` is also `using`'d. `CHESSProcessing`'s base package has no
`Plots`/`LabwarePlotting` dependency.
"""
function plot_plate_data end

"""
    plot_control_data(run_map::RunMap, plate_maps::AbstractVector{<:Pair}, values::AbstractDict;
                       relations=[:positive, :negative], nodes=nothing) -> Dict{String,Plots.Plot}

Per-plate categorical scatter of `values` by role (`relations...` plus `:run` for wells present but
not in any relation's mask) -- the restored, generalized successor to `CHESSQC.plot_control_data`
(hardcoded to exactly `run`/`positive control`/`negative control`), now supporting an arbitrary
relation set and colored via [`LabwarePlotting.role_palette`](@ref) for consistency with every other
role-colored plot in the CHESS ecosystem.

Extension point: see [`plot_plate_data`](@ref).
"""
function plot_control_data end
