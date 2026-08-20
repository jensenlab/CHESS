
function datarange(data::Vector{T}) where T <: Real
    return maximum(data) - minimum(data)
end



function control_summary(data::Matrix{T}, layout::DataFrame) where T <: Real
    check_single_plate(layout)

    run = [(layout.row[i], layout.col[i]) for i in findall(layout.run)]
    positive = [(layout.row[i], layout.col[i]) for i in findall(layout.positive)]
    negative = [(layout.row[i], layout.col[i]) for i in findall(layout.negative)]

    idxs = [run,positive,negative]

    data_sets = map(x -> [data[r, c] for (r, c) in x], idxs)

    df = DataFrame( type = ["runs","positive controls","negative controls"], median = median.(data_sets), mean = mean.(data_sets),sd =std.(data_sets),maximum = maximum.(data_sets),minimum=minimum.(data_sets),range=datarange.(data_sets))

    return df



end
