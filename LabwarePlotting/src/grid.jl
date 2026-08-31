"""
    plot_grid!(plt::Plots.Plot, active::AbstractMatrix{Bool};
               fillcolors::Union{Nothing,AbstractMatrix}=nothing,
               haloframe::Union{Nothing,AbstractMatrix}=nothing,
               halo_inset::Real=0.6, kwargs...) -> Plots.Plot

Draw the shared "grid of wells" skeleton onto `plt`: axis limits sized to `active`'s shape, an
optional per-cell flat-color fill (`fillcolors`, same shape as `active`), black gridlines, and the
standard orientation/labeling styling (flipped y-axis, bijective-base-26 lettered rows via
[`letter_code`](@ref), numbered columns mirrored to the top, no default ticks/legend/grid). Any
additional `kwargs` are forwarded to the final `plot!` styling call (e.g. `title`).

`haloframe` (same shape as `active`, only meaningful together with `fillcolors`) overlays a "halo"
frame on specific cells: any cell whose `haloframe` entry is not `nothing`/`missing` gets a full-cell
square in that color, then a smaller inset square (`halo_inset` fraction of the cell, default `0.6`)
drawn back in that cell's own `fillcolors` color -- so the halo color reads as a border/frame around
the cell's underlying color rather than replacing it outright. Cells with a `nothing`/`missing`
`haloframe` entry are unaffected, reproducing plain `fillcolors`-only rendering exactly. Useful for
distinguishing a fixed, semantically-important category (e.g. positive/negative controls) from an
underlying categorical grouping (e.g. which separable group/component a well belongs to) without
losing either piece of information in one plot.

This is the one skeleton every plate/grid plot in the CHESS ecosystem shares -- only the per-cell
color source (a flat lookup, a role-based lookup, or nothing at all) differs between callers.
"""
function plot_grid!(plt::Plots.Plot,active::AbstractMatrix{Bool};
                     fillcolors::Union{Nothing,AbstractMatrix}=nothing,
                     haloframe::Union{Nothing,AbstractMatrix}=nothing,
                     halo_inset::Real=0.6,kwargs...)
    R,C = size(active)
    xlims!(plt,(0.5,C+0.5)); ylims!(plt,(0.5,R+0.5))
    if fillcolors !== nothing
        for I in CartesianIndices(active)
            r,c = Tuple(I)
            plot!(plt,rectangle(c-0.5,r-0.5,1,1),fillcolor=fillcolors[I])
            halo = haloframe === nothing ? nothing : haloframe[I]
            if halo !== nothing && !ismissing(halo)
                plot!(plt,rectangle(c-0.5,r-0.5,1,1),fillcolor=halo)
                offset = (1-halo_inset)/2
                plot!(plt,rectangle(c-0.5+offset,r-0.5+offset,halo_inset,halo_inset),
                      fillcolor=fillcolors[I],linewidth=0)
            end
        end
    end
    _gridlines!(plt,R,C)
    plot!(plt;legend=false,grid=false,yflip=true,yticks=(collect(1:R),letter_code.(1:R)),
          ytickdirection=:none,xticks=collect(1:C),xmirror=true,xtickdirection=:none,kwargs...)
    return plt
end

"""
    _gridlines!(plt, R, C)

Draw the black well-grid lines for an `R`x`C` grid onto `plt`. Factored out of [`plot_grid!`](@ref) so
[`plot_heatmap!`](@ref) can redraw them on top of a heatmap fill, which would otherwise paint over and
hide them.
"""
function _gridlines!(plt,R,C)
    for line in collect(0:R) .+ 0.5
        hline!(plt,[line],color="black")
    end
    for line in collect(0:C) .+ 0.5
        vline!(plt,[line],color="black")
    end
    return plt
end

"""
    plot_grid(active::AbstractMatrix{Bool}; kwargs...) -> Plots.Plot

[`plot_grid!`](@ref) onto a fresh `Plots.plot()`.
"""
plot_grid(active::AbstractMatrix{Bool};kwargs...) = plot_grid!(plot(),active;kwargs...)
