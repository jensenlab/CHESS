function rectangle(x,y,w,h)
    return Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])
end

"""
    plot(pm::PlateMap; inactive="darkgray", empty_color="white", occupied_color="steelblue")

Basic layout visualization: inactive wells, empty active wells, and occupied wells in three flat
colors, labeled by raw node identity where displayable. This is the dependency-free view -- it has no
notion of what an occupant *is* (role, relationships), since `PlateMap` doesn't store that. For a
role-aware, colored-by-role plot, see the `RunMaps` extension's `plot(pm, rm)`.
"""
function plot(pm::PlateMap; inactive="darkgray", empty_color="white", occupied_color="steelblue")
    R,C = size(pm.wells)
    plt = plot()
    xlims!((0.5,C+0.5)); ylims!((0.5,R+0.5))
    for I in CartesianIndices(pm.wells)
        r,c = Tuple(I)
        color = !pm.wells[I] ? inactive : ismissing(pm.occupant[I]) ? empty_color : occupied_color
        plot!(rectangle(c-0.5,r-0.5,1,1),fillcolor=color)
    end
    for line in collect(0:R) .+ 0.5
        hline!([line],color="black")
    end
    for line in collect(0:C) .+ 0.5
        vline!([line],color="black")
    end
    plot!(title="",legend=false,grid=false,yflip=true,yticks=(collect(1:R),letter_code.(1:R)),
          ytickdirection=:none,xticks=collect(1:C),xmirror=true,xtickdirection=:none)
end
