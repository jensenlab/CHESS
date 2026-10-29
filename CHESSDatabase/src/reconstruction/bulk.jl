#=
Large requests. A request for few keys is answered key first (`local_queries.jl`, `local_series.jl`,
`local_closure.jl`). When the rows the keys own are a large part of the ledger, a lookup per key costs more than one
pass, so `plan_reconstruction` estimates the rows and chooses the path:

  :local   the keys are read through the indexes, in chunks of `_id_chunk`
  :global  one pass over the table; for the transfer closure this is the bulk path below

The bulk path of the transfer closure is its own implementation: one query reads every visible transfer and discard
of the window (or every transfer, for the descendants, which are followed without the visibility test), the rows
are indexed by well in memory and the same closure as the local path runs over them. It does not use the
whole-ledger queries kept for `reconstruction_mode[] == :legacy`. Other lookups still use those queries on the global
path; they must get an implementation of their own before the legacy queries are removed.
=#

"""
    BULK_FRACTION

`Ref` holding the fraction of the ledger above which [`plan_reconstruction`](@ref) chooses the global path.
Provisional (0.2); to be calibrated by the large-scale benchmark.
"""
const BULK_FRACTION = Ref(0.2)

# the (table, column) pairs that hold the rows a key owns, per kind of request
const _PLAN_KEYS = Dict(
    :transfers => (("Transfers","Source"),("Transfers","Destination"),("Discards","Source")),
    :environment => (("EnvironmentAttributes","LocationID"),("ObservedAttributes","LocationID")),
    :observations => (("ObservedComponents","LocationID"),),
    :movements => (("Movements","Child"),("Movements","Parent"),("ObservedParents","Child"),("ObservedParents","Parent")),
    :locks => (("Locks","LocationID"),("ObservedLocks","LocationID")),
    :activity => (("Activity","LocationID"),("ObservedActivity","LocationID")),
    :reads => (("Reads","LocationID"),))

"""
    plan_reconstruction(locs::AbstractVector{<:Integer}; kind::Symbol=:transfers, fraction=BULK_FRACTION[]) -> NamedTuple

Choose between answering a request for `locs` key by key (`:local`) and in one pass (`:global`). The estimate `rows`
is the number of rows the keys own in the tables of `kind` (`:transfers`, `:environment`, `:observations`,
`:movements`, `:locks`, `:activity` or `:reads`), counted through the indexes; `ledger_rows` is the number of ledger
entries. The path is `:global` when `rows` exceeds `fraction` of `ledger_rows`, or when `locs` is empty (no filter).

The result has the fields `path`, `kind`, `rows`, `ledger_rows` and `fraction` (`rows / ledger_rows`). For
`:transfers` the estimate counts the transfers of the keys themselves, not of the closure behind them, so it is a
lower bound.
"""
function plan_reconstruction(locs::AbstractVector{<:Integer};kind::Symbol=:transfers,fraction::Real=BULK_FRACTION[])
    haskey(_PLAN_KEYS,kind) || throw(ArgumentError("kind must be one of $(join(sort!(collect(keys(_PLAN_KEYS))),", ")), not :$kind"))
    ledger_rows = Int(get_last_ledger_id())
    if isempty(locs)
        return (path=:global,kind=kind,rows=0,ledger_rows=ledger_rows,fraction=NaN)
    end
    rows = 0
    for chunk in Iterators.partition(unique(locs),_id_chunk), (table,column) in _PLAN_KEYS[kind]
        rows += query_db("SELECT Count(*) AS N FROM $table WHERE $column IN $(_marks(length(chunk)))",Tuple(chunk)).N[1]
    end
    share = ledger_rows == 0 ? 0.0 : rows/ledger_rows
    return (path=rows > fraction*ledger_rows ? :global : :local,kind=kind,rows=rows,ledger_rows=ledger_rows,fraction=share)
end

# ------------------------------------------------------------------------------------------ transfer closure

# every visible transfer and discard of the window, indexed by well; `edges(wells, side)` returns the rows of the wells
function _bulk_edges(starting::Integer,ending::Integer,time::DateTime)
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    pieces = DataFrame[]
    for (table,dest,kind) in (("Transfers","x.Destination","0"),("Discards","NULL","1"))
        push!(pieces,query_db("""
            SELECT $(replace(_EDGE_COLUMNS,"%DEST%"=>dest,"%KIND%"=>kind)), vl.SequenceID AS SequenceID
            FROM $table x CROSS JOIN Ledger vl ON vl.ID = x.LedgerID AND $pred""",(starting,ending,t,t)))
    end
    rows = _vcat_or(pieces,_empty_edges())
    by_source = Dict{Int,Vector{Int}}()
    by_destination = Dict{Int,Vector{Int}}()
    for (i,r) in enumerate(eachrow(rows))
        push!(get!(()->Int[],by_source,r.Source),i)
        ismissing(r.Destination) || push!(get!(()->Int[],by_destination,r.Destination),i)
    end
    return function (wells,side)
        index = side === :in ? by_destination : by_source
        picked = Int[]
        for w in unique(wells)
            append!(picked,get(index,w,Int[]))
        end
        return rows[sort!(unique!(picked)),:]
    end
end

# every row of Transfers, indexed by source and by destination; `raw(column, wells)` returns the rows of the wells
function _bulk_raw()
    rows = query_db("SELECT LedgerID, Source, Destination, Quantity, Unit, ID AS RowID, 0 AS Kind FROM Transfers")
    isempty(rows) && (rows = _empty_raw())
    indexes = Dict("Source"=>Dict{Int,Vector{Int}}(),"Destination"=>Dict{Int,Vector{Int}}())
    for (i,r) in enumerate(eachrow(rows))
        push!(get!(()->Int[],indexes["Source"],r.Source),i)
        push!(get!(()->Int[],indexes["Destination"],r.Destination),i)
    end
    return function (column,wells)
        index = indexes[column]
        picked = Int[]
        for w in unique(wells)
            append!(picked,get(index,w,Int[]))
        end
        return rows[sort!(unique!(picked)),:]
    end
end
