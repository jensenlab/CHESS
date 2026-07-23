function get_vc_reagents(vc::DataFrame,units::DataFrame;kwargs...)
    colnames =names(vc)
    # in the vc format, each column other than the "volume" column is a reagent
    reagent_names = setdiff(colnames,["volume"])
    # take units from first row to supply to the reagent parser
    un = units[1,reagent_names]

    reagents = string_to_reagent.(reagent_names,string_to_unit.(collect(un));kwargs...)

    return Dict(reagent_names .=> reagents)
end

function get_quant_reagents(quant::DataFrame,units::DataFrame;kwargs...)
    reagent_names  =names(quant)
    # take units from first row to supply to the reagent parser
    un = units[1,reagent_names]

    reagents = string_to_reagent.(reagent_names,string_to_unit.(collect(un));kwargs...)

    return Dict(reagent_names .=> reagents)
end


function check_csv_inputs(df::DataFrame,units::DataFrame)
    # check that units contains either 1 or N rows
    N = nrow(df)
    U = nrow(units)
    if U != N && U != 1     # check that units contains either 1 or N rows
        error("units file must either have a single row or a corresponding row for each stock")
    end
    if names(df) != names(units)     # check that the column names of each table match
        error("column names must be consistent for each table")
    end

end

function is_single_row(df::DataFrame)
    return nrow(df) == 1
end

## Stock to DataFrame conversion

## User formats
# volconc : a volume x concentration table format for stocks
# quant : a quantity based table format for defining stocks
# stock: a CHESSCore stock representation


## Parsers for different dispensesolver inputs

function vc_to_stock(vc::DataFrame,units::DataFrame;kwargs...)
    check_csv_inputs(vc,units)

    single_unit = is_single_row(units)

    reagent_dict = get_vc_reagents(vc,units;kwargs...)
    N = nrow(vc)
    stocks = Stock[]
    urow = 1 # assume single unit by default
    for row in 1:N
        if !single_unit   # set the units file to follow the vc file, rather than use the single row
            urow = row
        end

        st = Empty()
        vol = vc[row,"volume"] * string_to_unit(units[urow,"volume"]) # parse the volume
        for r in keys(reagent_dict)
            un = string_to_unit(units[urow,r])
            if un isa Unitful.MassUnits || un isa Unitful.VolumeUnits || un isa Unitful.AmountUnits
                error("units provided are in a quantity format, did you mean to use the quantity (q) format?")
            end
            reagent = reagent_dict[r]
            expected = reagent isa Liquid ? dimension(u"mL") : dimension(u"g")
            dimension(un)*dimension(unit(vol)) == expected || error(
                "concentration unit $un for reagent $r is not dimensionally consistent with a total of $(unit(vol)) -- expected units that combine to a $(reagent isa Liquid ? "volume" : "mass")")
            quant = ((vc[row,r] * un) *vol)
            st +=  quant * reagent_dict[r]
        end
        push!(stocks,st)
    end
    return stocks
end



function stock_to_vc(stocks::Vector{<:CHESSCore.Stock}; kwargs...)
    concs = reagent_df(stocks;measure=concentration,kwargs...)
    vols = CHESSCore.quantity.(stocks)
    vols = map(x-> ismissing(x) ? 0u"ml" : x,vols)

    vc = DataFrame()
    un = DataFrame()
    vc.volume = ustrip.(vols)
    un.volume = unit_to_string.(unit.(vols))

    vc= hcat(vc,ustrip.(concs))
    un = hcat(un,unit_to_string.(unit.(concs)))

    return vc, un
end


function q_to_stock(quant::DataFrame,units::DataFrame;kwargs...)
    check_csv_inputs(quant,units)
    single_unit = is_single_row(units)

    reagent_dict = get_quant_reagents(quant,units;kwargs...)
    N = nrow(quant)
    stocks = Stock[]
    urow = 1 # assume single unit by default
    for row in 1:N
        if !single_unit   # set the units file to follow the q file, rather than use the single row
            urow = row
        end

        st = Empty()
        for r in keys(reagent_dict)
            un = string_to_unit(units[urow,r])
            if un isa Unitful.DensityUnits || un isa Unitful.DimensionlessUnits || un isa Unitful.MolarityUnits
                error("units provided are in a concentration format, did you mean to use the volume concentration (vc) format?")
            end
            q = quant[row,r] * un
            st +=  q * reagent_dict[r]
        end
        push!(stocks,st)
    end
    return stocks
end

function stock_to_q(stocks::Vector{<:CHESSCore.Stock};kwargs...)
    quants = reagent_df(stocks;measure=quantity,kwargs...)

    q = ustrip.(quants)
    un = unit_to_string.(unit.(quants) )
    return q, un
end




"""
    df_to_stock(df::DataFrame, units::DataFrame; kwargs...) -> Vector{Stock}

Parse a pair of DataFrame representations into a vector of `Stock`s.

This is a format-dispatching wrapper that supports two encodings:

- **"vc" (volume/concentration)**: tables include a `"volume"` column (in both `df`
  and `units`) and are parsed via `vc_to_stock(df, units; kwargs...)`.
- **"q" (quantity)**: tables omit `"volume"` and are parsed via
  `q_to_stock(df, units; kwargs...)`.

The function auto-detects the encoding by checking for the presence of the `"volume"`
column in both `df` and `units`.

# Arguments
- `df::DataFrame`: Main stock table (one row per stock; columns depend on the chosen format).
- `units::DataFrame`: Units/metadata table aligned with `df` (e.g., unit strings for
  numeric columns).

# See also
[`stock_to_df`](@ref)
"""
function df_to_stock(df::DataFrame,units::DataFrame;kwargs...)
    if nrow(df) == 0
        return Stock[]
    end
    key_name = "volume"
    if key_name in names(df) && key_name in names(units)
        return vc_to_stock(df,units;kwargs...)
    else
        return q_to_stock(df,units;kwargs...)
    end
end


const dataframe_conversion_formats = Dict(
    "vc" => stock_to_vc ,
    "q" => stock_to_q
)

"""
    stock_to_df(stocks::Vector{<:CHESSCore.Stock}, format::AbstractString = "vc"; kwargs...) -> (DataFrame, DataFrame)

Convert a vector of `Stock`s into a pair of dataframes `(df, units)` suitable for
serialization.

Two formats are supported:

- `format = "vc"`: volume/concentration representation (`stock_to_vc`).
- `format = "q"`: quantity representation (`stock_to_q`).

# Arguments
- `stocks::Vector{<:CHESSCore.Stock}`: Stocks to convert.
- `format::AbstractString = "vc"`: Output encoding; must be one of `$(keys(dataframe_conversion_formats))`.

# See also
[`df_to_stock`](@ref)
"""
function stock_to_df(stocks::Vector{<:CHESSCore.Stock},format="vc";kwargs...)
    if length(stocks) == 0
        return DataFrame(),DataFrame()
    end
    conversion_formats = keys(dataframe_conversion_formats)
    format in conversion_formats  || error("format must be one of $conversion_formats)")
    return dataframe_conversion_formats[format](stocks;kwargs...)
end




"""
    df_to_labware(df::DataFrame, units::DataFrame; kwargs...) -> Vector{Labware}

Reconstruct labware (and deposited well contents) from a dataframe representation.

`df_to_labware` expects labware metadata (labware, name, and well) plus the stock columns needed to reconstruct well contents. Stock content may be encoded in any stock dataframe format supported by [`df_to_stock`](@ref) ].

## Required columns in `df`
`df` must include the following columns:

- `labware`: `LocationKind` name registered in [`location_kinds`](@ref) (e.g. `"WP96"`), used to
  look up the kind and call [`build_location`](@ref). Valid codes are `keys(location_kinds)`.
- `name`: Name/identifier of the labware instance. Multiple rows may share the same
  `name` (and `labware`) to indicate multiple wells on the same physical item.
- `well`: Well identifier in row/column form (e.g. `"A1"`, `"H2"`, `"B12"`)

All remaining columns are treated as stock data and are passed to [`df_to_stock`](@ref).

## Behavior
- Creates one labware instance per unique `(labware, name)` pair, via
  `build_location(location_kinds[Symbol(labware)], name)` -- these are uncommitted (no database
  connection needed, `location_id` is `nothing`); commit the result yourself (e.g. via
  `commit_location!` in CHESSDatabase) if you want it tracked.
- Parses a `Stock` per row from the stock columns using `df_to_stock`.
- Looks up each row's well by name (`lw[well]`), not by position.

## Arguments
- `df::DataFrame`: Labware + stock data (one row per filled well).
- `units::DataFrame`: Units/metadata table for the stock columns (passed through to `df_to_stock`).

## See also
[`labware_to_df`](@ref), [`df_to_stock`](@ref)
"""
function df_to_labware(df::DataFrame,units::DataFrame;kwargs...)
    if nrow(df) == 0
        return Labware[]
    end
    labware_cols = ["labware","name","well"]
    stock_data = df[:,Not(labware_cols)]
    lw_data =df[:,labware_cols]
    lw_params = map((x,y)-> (x,y),lw_data.labware,lw_data.name)
    lw_idx = map(x -> findfirst(y->y==x,unique(lw_params)),lw_params)
    lw = map(x-> build_location(location_kinds[Symbol(x[1])],x[2]),unique(lw_params))
    stocks = df_to_stock(stock_data,units;kwargs...)
    for i in 1:nrow(stock_data)
        well_name = lw_data[i,"well"]
        CHESSCore.deposit!(lw[lw_idx[i]][well_name],stocks[i])
    end
    return lw
end


"""
    labware_to_df(lws::Vector{<:Labware}, format::AbstractString = "vc"; kwargs...) -> (DataFrame, DataFrame)

Convert labware into a dataframe representation suitable for serialization

The output contains one row per *non-empty* well and includes three labware
descriptor columns plus the stock columns:

- `labware`: `string(kind(lw).name)` -- the registered [`LocationKind`](@ref) name for the labware
  containing the well (not `typeof(lw)`; every `Labware` shares one concrete type, so the model/kind
  lives in `kind(lw)`, not the Julia type).
- `name`: `CHESSCore.name(lw)` labware instance name
- `well`: `CHESSCore.name(w)` well identifier (e.g., `"A1"`)

Stock content is converted using [`stock_to_df`](@ref) in the requested `format`.
The returned `units` dataframe corresponds to the stock
columns (not the `labware`/`name`/`well` columns).

# Arguments
- `lws::Vector{<:Labware}`: Labware objects to export.
- `format::AbstractString = "vc"`: Stock encoding passed to `stock_to_df`.

# See also
[`df_to_labware`](@ref), [`stock_to_df`](@ref)
"""
function labware_to_df(lws::Vector{<:Labware},format="vc";kwargs...)

    stocks = CHESSCore.Stock[]

    lw_df = DataFrame()
    for lw in lws
        wellnames = String[]
        wells = CHESSCore.children(lw)
        for w in wells
            st = stock(w)
            if st == CHESSCore.Empty()
                continue
            else
                push!(stocks,st)
                push!(wellnames,CHESSCore.name(w))
            end
        end
        n = length(wellnames)
        append!(lw_df,DataFrame( labware = fill(string(kind(lw).name),n), name= fill(CHESSCore.name(lw),n),well=wellnames))
    end

    stock_df,units_df = stock_to_df(stocks,format;kwargs...)

    out_df = hcat(lw_df,stock_df)

    return out_df ,units_df
end
"""
    labware_to_df(lw::Labware, format::AbstractString = "vc"; kwargs...) -> (DataFrame, DataFrame)

Convenience method for exporting a single `Labware` object. Equivalent to
`labware_to_df([lw], format; kwargs...)`.

See also: [`labware_to_df(::Vector{<:Labware})`](@ref)
"""
function labware_to_df(lws::Labware,format="vc";kwargs...)
    return labware_to_df([lws],format;kwargs...)
end
