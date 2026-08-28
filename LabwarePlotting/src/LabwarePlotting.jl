module LabwarePlotting

using Plots, ColorBrewer

include("naming.jl")
include("shapes.jl")
include("grid.jl")
include("heatmap.jl")
include("colors.jl")

export letter_code, wellnames, rectangle, circle, square, slas_rectangle,
       plot_grid, plot_grid!, place_shape!, plot_heatmap!, role_palette

end # module LabwarePlotting
