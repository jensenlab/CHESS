#=
Time series and lists read key first: the environment attributes of a location, the component observations of a
location and the reads of a location. As in `local_queries.jl`, each function replaces the query of the same name
that built `ledger_subset` over the whole ledger (kept as `_<name>_global`) and reads only the rows of its keys
through an index, applying the visibility rule of `visibility.jl` to them.

  - `get_environment_attributes` is a "last write wins" lookup per (location, attribute): `latest_visible_event`
    over the two event tables (see `latest_event.jl`: tick walk and series scan, exact under amendments and inserts).
  - `get_content_observations` is a list: every visible observation of the locations, no collapsing.
  - `get_reads` is a list too. It reads newest first through the `Reads(LocationID, COALESCE(InstrumentTime, Time))`
    index when paged, so a page costs the rows it returns plus the rows hidden among them.

The original is used instead when `encumbrances=true`, when `reconstruction_mode[]` is `:legacy`, and for a request
naming more than `LOCAL_KEY_LIMIT` locations that own a large part of the ledger (`plan_reconstruction`).
=#

# the (location, attribute) pairs a location has ever had an event for, from either table
function _attribute_keys(locs::AbstractVector{<:Integer})
    pairs = Tuple{Int,String}[]
    for chunk in Iterators.partition(locs,_id_chunk)
        marks = _marks(length(chunk))
        df = query_db("""
            SELECT LocationID, Attribute FROM EnvironmentAttributes WHERE LocationID IN $marks
            UNION SELECT LocationID, Attribute FROM ObservedAttributes WHERE LocationID IN $marks AND IsInherited = 0""",(chunk...,chunk...))
        append!(pairs,[(Int(r.LocationID),String(r.Attribute)) for r in eachrow(df)])
    end
    return sort!(unique!(pairs))
end

_attribute_sources(loc,attr) = [("EnvironmentAttributes",["LocationID"=>loc,"Attribute"=>attr],""),
    ("ObservedAttributes",["LocationID"=>loc,"Attribute"=>attr],"e.IsInherited = 0")]

"""
    get_environment_attributes(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

The current value of every attribute set on `locs` themselves (not inherited) between `starting` and `ending`: for
each (location, attribute) the visible event in the highest slot, from the recorded attributes and from the
observed ones. The columns are `LedgerID`, `SequenceID`, `EncumbranceID` (`0`), `LocationID`, `Attribute`, `Value`
and `Unit`, ordered by `SequenceID`.

Each series is searched from its end (see `latest_visible_event`), so the time depends on the events since the
last one in the window or on the length of the series, whichever is less, and not on the length of the ledger.
"""
function get_environment_attributes(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,locs;kind=:environment) && return _get_environment_attributes_global(locs,starting,ending,time;encumbrances=encumbrances)
    rows = DataFrame[]
    for (loc,attr) in _attribute_keys(unique(locs))
        ev = latest_visible_event(_attribute_sources(loc,attr),starting,ending,time)
        ev === nothing && continue
        table = ev.source == 1 ? "EnvironmentAttributes" : "ObservedAttributes"
        row = query_db("""
            SELECT e.LedgerID AS LedgerID, $(ev.slot) AS SequenceID, 0 AS EncumbranceID, e.LocationID AS LocationID,
                   e.Attribute AS Attribute, e.Value AS Value, e.Unit AS Unit
            FROM $table e WHERE e.LedgerID = ? AND e.LocationID = ? AND e.Attribute = ? ORDER BY e.ID LIMIT 1""",(ev.ledger_id,loc,attr))
        push!(rows,row)
    end
    isempty(rows) && return DataFrame(LedgerID=Int[],SequenceID=Int[],EncumbranceID=Int[],LocationID=Int[],Attribute=String[],Value=Any[],Unit=String[])
    out = reduce(vcat,rows)
    return out[sortperm(out.SequenceID;alg=MergeSort),:]
end

"""
    get_content_observations(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Every component observation on `locs` between `starting` and `ending` sequence points, ordered by `SequenceID`
(observations of one slot in the order they were recorded). The columns are `LedgerID`, `SequenceID`, `LocationID`,
`ComponentID`, `Quantity` and `Unit`.
"""
function get_content_observations(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    isempty(locs) && return _get_content_observations_global(locs,starting,ending,time)
    _use_global(false,locs;kind=:observations) && return _get_content_observations_global(locs,starting,ending,time)
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    pieces = DataFrame[]
    for chunk in Iterators.partition(unique(locs),_id_chunk)
        push!(pieces,query_db("""
            SELECT o.LedgerID AS LedgerID, vl.SequenceID AS SequenceID, o.LocationID AS LocationID, o.ComponentID AS ComponentID,
                   o.Quantity AS Quantity, o.Unit AS Unit, o.ID AS RowID
            FROM ObservedComponents o CROSS JOIN Ledger vl ON vl.ID = o.LedgerID AND $pred
            WHERE o.LocationID IN $(_marks(length(chunk)))""",(starting,ending,t,t,chunk...)))
    end
    out = reduce(vcat,pieces)
    out = out[sortperm(collect(zip(out.SequenceID,out.RowID))),:]
    return select(out,Not(:RowID))
end

"""
    get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();
              limit=nothing,offset::Integer=0,newest_first::Bool=false,since=nothing,until=nothing)

Every `Reads` row for `location_id` up to `sequence_id`/`time`, as a `DataFrame`, ordered by the time of the read
(`InstrumentTime`, or the upload `Time` when there is none) and then by insertion. Reads never supersede each
other, but a read recorded in a slot that was later amended belongs to the superseded revision and is not returned.

`newest_first` reverses the order. `limit` and `offset` take a page of that order; `since` and `until` (a `DateTime`)
keep the reads whose time is at or after / at or before them. A page is read through an index on the time of the
read, so its cost does not depend on how many reads the location has.
"""
function get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();
        limit::Union{Integer,Nothing}=nothing,offset::Integer=0,newest_first::Bool=false,
        since::Union{DateTime,Nothing}=nothing,until::Union{DateTime,Nothing}=nothing)
    paged = !(isnothing(limit) && offset == 0 && !newest_first && isnothing(since) && isnothing(until))
    (!paged && reconstruction_mode[] === :legacy) && return _get_reads_global(location_id,sequence_id,time)
    sql,params = _reads_query(location_id,sequence_id,time,limit,offset,newest_first,since,until)
    return query_db(sql,params)
end

# the SQL and parameters of the local `get_reads`; a function of its own so a test can explain the plan
function _reads_query(location_id,sequence_id,time,limit,offset,newest_first,since,until)
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    key = "COALESCE(r.InstrumentTime, r.Time)"
    params = Any[0,sequence_id,t,t,location_id]
    bounds = ""
    isnothing(since) || (bounds *= " AND $key >= ?"; push!(params,db_time(since)))
    isnothing(until) || (bounds *= " AND $key <= ?"; push!(params,db_time(until)))
    dir = newest_first ? "DESC" : "ASC"
    page = ""
    if !isnothing(limit) || offset > 0
        page = " LIMIT ? OFFSET ?"
        push!(params,isnothing(limit) ? -1 : limit,offset)
    end
    sql = """
        SELECT r.* FROM Reads r CROSS JOIN Ledger vl ON vl.ID = r.LedgerID AND $pred
        WHERE r.LocationID = ?$bounds
        ORDER BY $key $dir, r.ID $dir$page"""
    return sql,Tuple(params)
end
