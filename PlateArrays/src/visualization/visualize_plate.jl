


function plot(design::PlateArray;pos="blue",neg="red",inactive="darkgray",run="white",k::Real=0.6)
        0 <= k <= 1 ? nothing : error("k must be between zero and one")
        plt=plot()
        nrow,ncol=size(design.wells)
        xlims!((0.5,ncol+0.5))
        ylims!((0.5,nrow+0.5))

        for idx in Tuple.(CartesianIndices(design.wells))
            x,y=idx
            if !design.wells[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=inactive)
            else 
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=run)
            end 
            if design.positives[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=pos)
                plot!(rectangle(y-k/2,x-k/2,k,k),fillcolor=run,linewidth=0)
            end 
            if design.negatives[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=neg)
                plot!(rectangle(y-k/2,x-k/2,k,k),fillcolor=run,linewidth=0)
            end 
        end 
       
        hlines=collect(0:nrow) .+ 0.5
        vlines=collect(0:ncol) .+ 0.5
        for line in hlines
            hline!([line],color="black")
        end 
        for line in vlines
            vline!([line],color="black")
        end
        plot!(title="",legend=false,grid=false,yflip=true,yticks=(collect(1:nrow),alphabet_code.(1:nrow)),ytickdirection=:none,xticks=collect(1:ncol),xmirror=true,xtickdirection=:none)
end 


function plot(designs::Vector{PlateArray};pos::String="blue",neg::String="red",inactive::String="darkgray",runs=ColorBrewer.palette("Pastel2",8),k=0.6)
    0 <= k <= 1 ? nothing : error("k must be between zero and one")
    plt=plot()
    allequal(map(x->size(x.wells),designs)) ? nothing : error("all designs must have the same plate shape")

    nrow,ncol=size(designs[1].wells)
    xlims!((0.5,ncol+0.5))
    ylims!((0.5,nrow+0.5))
    all(sum(map(x->x.wells,designs)).<=1) ? nothing : error("designs must be non-overlapping.")
    inactives=sum(map(x->x.wells,designs)).<=0
    length(designs) <= length(runs) ? nothing : error("not enough colors to plot")
    color_count=1
    for design in designs 
        for idx in Tuple.(CartesianIndices(design.wells))
            x,y=idx
            if design.wells[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=runs[color_count])
            end 
            if design.positives[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=pos)
                plot!(rectangle(y-k/2,x-k/2,k,k),fillcolor=runs[color_count],linewidth=0)
            end 
            if design.negatives[x,y]
                plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=neg)
                plot!(rectangle(y-k/2,x-k/2,k,k),fillcolor=runs[color_count],linewidth=0)
            end 
        end 
        color_count+=1
    end 
    for idx in  Tuple.(CartesianIndices(designs[1].wells))
        x,y=idx
        if inactives[x,y]
        plot!(rectangle(y-0.5,x-0.5,1,1),fillcolor=inactive)
        end
    end
    hlines=collect(0:nrow) .+ 0.5
    vlines=collect(0:ncol) .+ 0.5
    for line in hlines
        hline!([line],color="black")
    end 
    for line in vlines
        vline!([line],color="black")
    end
    plot!(title="",legend=false,grid=false,yflip=true,yticks=(collect(1:nrow),alphabet_code.(1:nrow)),ytickdirection=:none,xticks=collect(1:ncol),xmirror=true,xtickdirection=:none)
end 



function plot(designs::Matrix{PlateArray};kwargs...)
    return [plot(designs[:,i]) for i in 1:size(designs)[2] ]
end 


function alphabet_code(n) 
    
    alphabet=collect('A':'Z')
    k=length(alphabet)
    return repeat(alphabet[mod(n-1,k)+1],cld(n,k))
end 


function rectangle(x,y,w,h)
    return Shape(x .+ [0,w,w,0],y .+ [0,0,h,h])
end 


