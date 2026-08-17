

function DataFrame(p::PlateArray)
    R,C = size(p.wells)

    well_names = vec(wellnames(p))
    row = repeat(1:R , C)
    col = repeat(1:C, inner = R )

    run = vec(runs(p))
    pos = vec(p.positives)
    neg= vec(p.negatives)
    run_idx = vec(p.run_index)

    return DataFrame(well = well_names ,row= row, col = col, run = run, positive = pos , negative = neg, run_index = run_idx)
end


function PlateArray(df::DataFrame)
    required_cols = ["well","row","col","run","positive","negative"]
    recognized_cols = vcat(required_cols,"run_index")

    all(in(names(df)),required_cols) || error("DataFrame must have the following columns  the following names $(required_cols)")

    extra = setdiff(names(df),recognized_cols)
    isempty(extra) || @warn("DataFrame includes extra columns. Parsing $(recognized_cols) columms to build PlateArray ")

    R = maximum(df.row)
    C = maximum(df.col)

    wells = df.run .|| df.positive .|| df.negative

    run_index = "run_index" in names(df) ? reshape(Vector{Union{Missing,Int}}(df.run_index),R,C) : fill(missing,R,C)

    return PlateArray(reshape(wells,R,C),reshape(df.positive,R,C),reshape(df.negative,R,C),run_index)
end





