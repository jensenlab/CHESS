function DataFrame(pm::PlateMap)
    R,C = size(pm.wells)
    well_names = vec(wellnames(pm.wells))
    row = repeat(1:R,C)
    col = repeat(1:C,inner=R)
    active = vec(pm.wells)
    occ = vec(pm.occupant)
    return DataFrame(well=well_names,row=row,col=col,active=active,occupant=occ)
end

function PlateMap(df::DataFrame)
    required = ["well","row","col","active","occupant"]
    all(in(names(df)),required) || error("DataFrame must have the following columns: $(required)")

    extra = setdiff(names(df),required)
    isempty(extra) || @warn("DataFrame includes extra columns. Parsing $(required) columns to build PlateMap")

    R = maximum(df.row)
    C = maximum(df.col)
    wells = BitMatrix(reshape(collect(df.active),R,C))
    T = nonmissingtype(eltype(df.occupant))
    occupant = Matrix{Union{Missing,T}}(reshape(collect(df.occupant),R,C))
    return PlateMap{T}(wells,occupant)
end

"""
    DataFrame(pms::Vector{PlateMap}) -> DataFrame

Compile a multi-plate schedule into a single `DataFrame`: [`DataFrame(pm)`](@ref) for each plate, stacked
with a leading `plate` column (1-based, matching `pms`' order) to disambiguate rows across plates (well
`"A1"` exists on every plate). See [`platemaps_from_dataframe`](@ref) for the reverse.
"""
function DataFrame(pms::Vector{PlateMap})
    dfs = DataFrame[]
    for (i,pm) in enumerate(pms)
        df = DataFrame(pm)
        insertcols!(df,1,:plate=>i)
        push!(dfs,df)
    end
    return vcat(dfs...)
end

"""
    platemaps_from_dataframe(df::DataFrame) -> Vector{PlateMap}

Reverse of [`DataFrame(pms::Vector{PlateMap})`](@ref): splits `df` on its required `plate` column
(sorted ascending) and reconstructs each plate via the existing [`PlateMap(df)`](@ref) on that group's
`well,row,col,active,occupant` columns.
"""
function platemaps_from_dataframe(df::DataFrame)
    "plate" in names(df) || error("DataFrame must have a \"plate\" column to reconstruct multiple PlateMaps")
    pms = PlateMap[]
    for p in sort(unique(df.plate))
        subdf = select(df[df.plate.==p,:],Not(:plate))
        push!(pms,PlateMap(subdf))
    end
    return pms
end
