"""
    plot_grid!(plt::Plots.Plot, active::AbstractMatrix{Bool};
               fillcolors::Union{Nothing,AbstractMatrix}=nothing, kwargs...) -> Plots.Plot

Draw the shared "grid of wells" skeleton onto `plt`: axis limits sized to `active`'s shape, an
optional per-cell flat-color fill (`fillcolors`, same shape as `active`), black gridlines, and the
standard orientation/labeling styling (flipped y-axis, bijective-base-26 lettered rows via
[`letter_code`](@ref), numbered columns mirrored to the top, no default ticks/legend/grid). Any
additional `kwargs` are forwarded to the final `plot!` styling call (e.g. `title`).

This is the one skeleton every plate/grid plot in the CHESS ecosystem shares -- only the per-cell
color source (a flat lookup, a role-based lookup, or nothing at all) differs between callers.
"""
function plot_grid!(plt::Plots.Plot,active::AbstractMatrix{Bool};
                     fillcolors::Union{Nothing,AbstractMatrix}=nothing,kwargs...)
    R,C = size(active)
    xlims!(plt,(0.5,C+0.5)); ylims!(plt,(0.5,R+0.5))
    if fillcolors !== nothing
        for I in CartesianIndices(active)
            r,c = Tuple(I)
            plot!(plt,rectangle(c-0.5,r-0.5,1,1),fillcolor=fillcolors[I])
        end
    end
    for line in collect(0:R) .+ 0.5
        hline!(plt,[line],color="black")
    end
    for line in collect(0:C) .+ 0.5
        vline!(plt,[line],color="black")
    end
    plot!(plt;legend=false,grid=false,yflip=true,yticks=(collect(1:R),letter_code.(1:R)),
          ytickdirection=:none,xticks=collect(1:C),xmirror=true,xtickdirection=:none,kwargs...)
    return plt
end

"""
    plot_grid(active::AbstractMatrix{Bool}; kwargs...) -> Plots.Plot

[`plot_grid!`](@ref) onto a fresh `Plots.plot()`.
"""
plot_grid(active::AbstractMatrix{Bool};kwargs...) = plot_grid!(plot(),active;kwargs...)
