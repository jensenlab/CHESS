function plot_control_data(data::Matrix{T}, layout::DataFrame; kwargs...) where T <: Real

    size_data_plate_check(data, layout)

    label_types = fill("", nrow(layout))
    label_types[layout.run] .= "run"
    label_types[layout.negative] .= "negative control"
    label_types[layout.positive] .= "positive control"

    active_idx = findall(layout.run .| layout.positive .| layout.negative)
    active_labels = label_types[active_idx]
    active_data = [data[layout.row[i], layout.col[i]] for i in active_idx]

    active_labels = CategoricalArray(active_labels)
    levels!(active_labels,["negative control","run","positive control"])

    p = Plots.scatter(active_labels,active_data,color=levelcode.(active_labels),palette=[:red,:black,:blue],legend=false,grid=false)
    xlims!(0.5,3.5,kwargs...)
    return p
end



function plot_plate_data(data::Matrix{T}, layout::DataFrame; kwargs...) where T <: Real

    p = heatmap(data; kwargs...)

    return p
end
