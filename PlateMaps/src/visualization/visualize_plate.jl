"""
    plot(pm::PlateMap; inactive="darkgray", empty_color="white", occupied_color="steelblue")

Basic layout visualization: inactive wells, empty active wells, and occupied wells in three flat
colors, labeled by raw node identity where displayable. This is the dependency-free view -- it has no
notion of what an occupant *is* (role, relationships), since `PlateMap` doesn't store that. For a
role-aware, colored-by-role plot, see the `RunMaps` extension's `plot(pm, rm)`.
"""
function plot(pm::PlateMap; inactive="darkgray", empty_color="white", occupied_color="steelblue")
    fillcolors = [!pm.wells[I] ? inactive : ismissing(pm.occupant[I]) ? empty_color : occupied_color
                  for I in CartesianIndices(pm.wells)]
    return LabwarePlotting.plot_grid(pm.wells; fillcolors=fillcolors)
end
