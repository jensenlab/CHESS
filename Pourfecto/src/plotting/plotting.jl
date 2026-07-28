

# Pourfecto-owned, explicit set governing a purely cosmetic choice (square vs. circle well markers) --
# deliberately decoupled from CHESSCore.LocationKind's `categories` field (a different-purpose,
# externally-owned field with no exclusivity enforced between tags). Same membership as the
# EightChannel/PlateMaster admissibility sets today, independently defined and independently named --
# this one is cosmetic, not a capability decision, so a future divergence from those sets would be
# harmless by construction.
const plotting_wellplate_kinds = Set([:WP96,:WP384,:DeepWP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow,:brPCR96])

function plot(l::Labware;well_heatmap=false,kwargs...)
    is_wellplate_like = kind(l).name in plotting_wellplate_kinds

    nrow,ncol = CHESSCore.shape(l)

    plt= plot()
    xlims!((0.5,ncol+0.5))
    ylims!((0.5,nrow+0.5))

    hlines=collect(0:nrow) .+ 0.5
    vlines=collect(0:ncol) .+ 0.5
    if well_heatmap
        plot_well_heatmap!(plt,l)
    end
    for line in hlines
        hline!([line],color="black")
    end
    for line in vlines
        vline!([line],color="black")
    end

    if is_wellplate_like
        plot!(plt,title="$(CHESSCore.name(l))",legend=false,grid=false,yflip=true,yticks=(collect(1:nrow),plate_alphabet[1:nrow]),ytickdirection=:none,xticks=collect(1:ncol),xmirror=true,xtickdirection=:none)
    else # Bottle/Conical -- draw a circle marker for each well
        for r in 1:nrow
            for c in 1:ncol
                plot!(circle(r,c,1),color="black")
            end
        end

        plot!(plt,title="$(CHESSCore.name(l))",legend=false,grid=false,yflip=true,yticks=(collect(1:nrow),plate_alphabet[1:nrow]),ytickdirection=:none,xticks=collect(1:ncol),xmirror=true,xtickdirection=:none)

        return plt
    end
end





function circle(x,y,d)
    r=d/2
    θ=LinRange(0,2*π,500)
    x .+ r*sin.(θ), y .+ r*cos.(θ)
end 

function square(x,y,d)
    return x .+ [0,d,d,0] .-d/2 ,y .+ [0,0,d,d].- d/2
end 

function slas_rectangle(x,y,d)
    w = 3/2*d
    return  x .+ [0,w,w,0] .-w/2 ,y .+ [0,0,d,d].- d/2
end

function labware_plotting_shape(l::Labware)

    if kind(l).name in plotting_wellplate_kinds
        return square
    else
        return circle
    end
end


function plot_well_heatmap!(p::Plots.Plot,l::Labware ,kwargs...)

    stocks = stock.(children(l))

    quants = map(x-> x isa Empty ? 0 : ustrip(uconvert(u"µL",CHESSCore.quantity(x))),stocks)


    heatmap!(p,quants,color=Plots.cgrad([:white,:dodgerblue]))

    return p 
end 






function plot(a::FlowNode;shape::Function = circle ,kwargs...)

    l = labware(a.mask) 


    a_plt = plot(l)

    wells= well_connections(a) 
    names= map(x->x[2],wells)

    for idx in CartesianIndices(children(l))
        if CHESSCore.name(children(l)[idx]) in names 
            plot!(a_plt,Shape(shape(idx[2],idx[1],1)...),fill="red")
        end 

    end 
    return a_plt 
end 



"""
    plot_flow(a::AspNode, d::DispNode, vol::Real; kwargs...) -> Any

Create a visualization of a single flow from an aspiration node to a dispense node.

This helper plots the aspiration node `a` and dispense node `d` (via `plot(a; kwargs...)`
and `plot(d; kwargs...)`) and combines them into a single figure with a  title that includes the node configuration type and the requested volume
(in µL).

# Arguments
- `a::AspNode`: Aspiration (source-side) flow node to visualize.
- `d::DispNode`: Dispense (target-side) flow node to visualize.
- `vol::Real`: Flow volume to display in the title (interpreted as µL).

"""
function plot_flow(a::AspNode, d::DispNode, vol::Real;kwargs...)

    asp = plot(a;kwargs...)
    disp= plot(d;kwargs...)
    
    c = a.configuration

    p = plot(asp,disp, aspect_ratio=1, plot_title= "Configuration: $(typeof(c)) Volume: $vol µL",size=(1600,800);kwargs...)
    return p 
end 



"""
    plot_flows(pc::Pourcast; threshold::Real = 1e-4) -> Vector

Generate per-flow plots for all flows in a solved [`Pourcast`](@ref) above a threshold.

This function:
1. Builds aspiration and dispense node grids with `compute_flow_nodes` using the
   `configs(pc)` and the corresponding source/target labware.
2. Reads the flow matrix via [`flows(pc)`](@ref).
3. For each matrix entry `(i, j)` whose flow is `>= threshold`, generates a plot with
   [`plot_flow`](@ref) and collects the results.

# Arguments
- `pc::Pourcast`: A solved  `Pourcast`

# See also
[`flows`](@ref), [`plot_flow`](@ref)
"""
function plot_flows(pc::Pourcast;threshold::Real= 1e-4) 

    asp_nodes = compute_flow_nodes(AspNode,configs(pc),source_labware(pc))

    disp_nodes = compute_flow_nodes(DispNode,configs(pc),target_labware(pc))

    flws = flows(pc) 
    plts = []

    for idx in CartesianIndices(flws) 
        if flws[idx] >= threshold
            p = plot_flow(asp_nodes[idx[1]],disp_nodes[idx[2]],flws[idx])
            push!(plts,p)
        end 
    end 
    return plts 
end 




function plot(pos::ConstrainedPosition;plot_size = (1200,800),titlefontsize=18,tickfontsize=18,kwargs...) 
    r,c = slots(pos)
    plot(grid=false,size=plot_size,yflip=true,legend=false,xticks=1:c,yticks=(1:r,plate_alphabet[1:r]),xmirror=true,tickdirection=:none,tickfontsize=tickfontsize,margin=(5,:mm))
end 

function plot(pos::EmptyPosition;plot_size = (1200,800) ,titlefontsize=18,tickfontsize=18,kwargs...)
    r,c=(1,1)
    plot(showaxis=false,grid=false,size=plot_size,yflip=true,legend=false,ticks=:none,margin=(5,:mm))
end 

function plot(pos::UnconstrainedPosition;plot_size = (1200,800),titlefontsize=18,tickfontsize=18,kwargs...)
    r,c= slots(pos)
    plot(grid=false,yflip=false,size = plot_size,legend=false,xticks=1:c,yticks=(1:r),xmirror=true,tickdirection=:none,tickfontsize=tickfontsize,margin=(5,:mm))
end 

slotting_shape=Dict(
    "circle" => circle,
    "rectangle" => square
)

function plotting_shape(d::Deck) 
    if d isa AbstractVector 
        return (length(d),1)
    else
        return size(d)
    end
end 


"""
    plot_slotting(deck::Deck, slotting::SlottingDict;
                  wrapwidth::Integer=20,
                  titlefontsize::Integer=18,
                  fontsize::Integer=14,
                  plotsize=(1200,800)) -> Plots.Plot

Plot a deck with labware arranged according to `slotting`.

Assumptions about `slotting` (based on your other plotting code):
- `slotting[lw][1]` is a `Position` object on the deck (e.g., `ConstrainedPosition`, `StackPosition`, ...).
- `slotting[lw][2]` is an index (row,col) within that position's slot grid where the labware is placed.

Assumptions about `deck`:
- `deck` is either a matrix-like container (2D) of positions, or a vector of positions.
"""
function plot_slotting(deck::Deck, slotting::SlottingDict;
                       wrapwidth::Integer=30,
                       titlefontsize::Integer=18,
                       fontsize::Integer=14,
                       plotsize=(1200,800),
                       kwargs...)

    # Determine deck layout shape + access method
    deck_is_vector = deck isa AbstractVector
    plot_shape = plotting_shape(deck)

    # Invert slotting once: Position => labware placed there
    # (avoids filtering keys(slotting) for every deck cell)
    pos_to_labware = Dict{Any, Vector{Any}}()
    for (lw, v) in slotting
        pos = v[1]
        push!(get!(pos_to_labware, pos, Any[]), lw)
    end

    plts = Plots.Plot[]
    for row in 1:plot_shape[1], col in 1:plot_shape[2]
        pos = deck_is_vector ? deck[row] : deck[row, col]
        plt = plot(pos;plot_size=plotsize, titlefontsize=titlefontsize, tickfontsize=titlefontsize)

        r, c = 1, 1
        if !(pos isa EmptyPosition)
            r, c = slots(pos)
            vals = fill("", r, c)

            # Fill labels from labware assigned to this position
            for lw in get(pos_to_labware, pos, Any[])
                idx = slotting[lw][2]                 # expected (row,col)
                vals[idx] = CHESSCore.name(lw)
            end

            # Draw slot outlines and labels
            shape = slotting_shape[pos.plotting_shape]  # fallback if missing
            for x in 1:c, y in 1:r
                annotate!(x, y,
                          text(TextWrap.wrap(vals[y, x], width=wrapwidth),
                               :center, fontsize))
                plot!(shape(x, y, 1), color="black")
            end
        end
        plot!(ylims=(0.5, r + 0.5), xlims=(0.5, c + 0.5))
        plot!(title=TextWrap.wrap(pos.name, width=wrapwidth), titlefontsize=titlefontsize)
        push!(plts, plt)
    end

    finalsize = plotsize .* reverse(plot_shape)
    return plot(plts...;
                size=finalsize,
                layout=plot_shape,
                legend=false,
                margins=(10, :mm),
                titlefontsize=titlefontsize)
end
