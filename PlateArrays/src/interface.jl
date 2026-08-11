

function DataFrame(p::PlateArray)
    R,C = size(p.wells)

    well_names = vec(wellnames(p))
    row = repeat(1:R , C)
    col = repeat(1:C, inner = R )

    run = vec(runs(p))
    pos = vec(p.positives)
    neg= vec(p.negatives)

    return DataFrame(well = well_names ,row= row, col = col, run = run, positive = pos , negative = neg)
end 


function PlateArray(df::DataFrame) 
    df_names = ["well","row","col","run","positive","negative"] 

    if names(df) == df_names # df is the exact platarray output 
        # do nothing 
    elseif all(in(names(df)),df_names) # if df includes extra names that are not in the platearray but it has all necessary columsn 
        @warn("DataFrame includes extra columns. Parsing $(df_names) columms to build PlateArray ")
    else
        error("DataFrame must have the following columns  the following names $(df_names)")
    end 

    R = maximum(df.row)
    C = maximum(df.col)

    wells = df.run .|| df.positive .|| df.negative

    return PlateArray(reshape(wells,R,C),reshape(df.positive,R,C),reshape(df.negative,R,C))
end





