#=
Reconstruction lookups that filter by key first. Each function here replaces the query of the same name that
built `ledger_subset` over the whole ledger (kept as `_<name>_global`). It reads the rows of one key through
an index and applies the visibility rule of `visibility.jl` to those rows only, so its cost depends on the
history of the key, not on the size of the ledger. Results have the columns, types and order of the originals.

The original is used instead when `encumbrances=true` (the planned operations are merged in SQL there), when
`reconstruction_mode[]` is `:legacy`, and for a request naming more than `LOCAL_KEY_LIMIT` keys, where one pass
over the ledger is cheaper than a lookup per key.
=#

"""
    reconstruction_mode

`Ref` holding `:local` (the default) or `:legacy`. In `:legacy` mode the lookups that were rewritten to filter by
key first use their original whole-ledger queries. Set at startup from the environment variable
`CHESS_RECONSTRUCTION`.
"""
const reconstruction_mode = Ref(:local)

const LOCAL_KEY_LIMIT = Ref(200)

_use_global(encumbrances,nkeys=0) = encumbrances || reconstruction_mode[] === :legacy || nkeys > LOCAL_KEY_LIMIT[]

# ------------------------------------------------------------------------------------------ cache getters

# The visible cache rows of one location, one per slot (the highest-ID row of the slot), oldest slot first.
function _local_cache_rows(table::String,column::String,location_id::Integer,starting::Integer,ending::Integer,time::DateTime;
        group::String="vl.SequenceID",cache_time::Bool=false)
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    sql = """
        SELECT Max(c.ID) AS ID, c.LedgerID AS LedgerID, vl.SequenceID AS SequenceID, 0 AS EncumbranceID, c.LocationID AS LocationID, c.$column AS $column
        FROM $table c INNER JOIN Ledger vl ON vl.ID = c.LedgerID AND $pred
        WHERE c.LocationID = ? $(cache_time ? "AND c.Time <= ?" : "")
        GROUP BY $group ORDER BY vl.SequenceID"""
    params = Any[starting,ending,t,t,location_id]
    cache_time && push!(params,t)
    return query_db(sql,Tuple(params))
end

function get_parent_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_parent_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    return _local_cache_rows("CachedAncestors","ParentID",location_id,starting,ending,time)
end

function get_child_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_child_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    return _local_cache_rows("CachedDescendants","ChildSetID",location_id,starting,ending,time)
end

function get_content_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_content_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    # kept as the original has it: grouped by ledger row, and the cache row itself must be no newer than `time`
    return _local_cache_rows("CachedContents","StockID",location_id,starting,ending,time;group="c.LedgerID",cache_time=true)
end

function get_attribute_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_attribute_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    return _local_cache_rows("CachedEnvironments","AttributeSetID",location_id,starting,ending,time)
end

function get_lock_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_lock_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    return _local_cache_rows("CachedLockActivity","IsLocked",location_id,starting,ending,time)
end

function get_activity_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)
    _use_global(encumbrances) && return _get_activity_caches_global(location_id,starting,ending,time;encumbrances=encumbrances)
    return _local_cache_rows("CachedLockActivity","IsActive",location_id,starting,ending,time)
end

# ------------------------------------------------------------------------------- last write wins per key

# Fill a result with one row per key: the latest visible event of `sources(key)` and `fetch(source_index, key,
# ledger_id)`, the event's remaining column(s). `frame` is the empty result and `row(...)` makes one of its rows.
function _latest_rows(frame::DataFrame,keys,sources,fetch,row,starting,ending,time)
    found = Tuple[]
    for key in keys
        ev = latest_visible_event(sources(key),starting,ending,time)
        ev === nothing && continue
        push!(found,(ev.slot,row(key,ev,fetch(ev.source,key,ev.ledger_id))))
    end
    sort!(found;by=first,alg=MergeSort)    # oldest slot first, as the originals order them; stable
    for (_,r) in found
        push!(frame,r)
    end
    return frame
end

const _MOVEMENT_TABLES = ("Movements","ObservedParents")
const _LOCK_TABLES = ("Locks","ObservedLocks")
const _ACTIVITY_TABLES = ("Activity","ObservedActivity")

_event_value(tables,column,keycolumn) = (source,key,ledger_id) ->
    query_db("SELECT $column FROM $(tables[source]) WHERE $keycolumn = ? AND LedgerID = ? ORDER BY ID LIMIT 1",(key,ledger_id))[1,1]

_movement_frame() = DataFrame(LedgerID=Int[],SequenceID=Int[],EncumbranceID=Int[],Parent=Union{Missing,Int}[],Child=Int[])

function get_last_movement_as_child(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(locs)) && return _get_last_movement_as_child_global(locs,starting,ending,time;encumbrances=encumbrances)
    return _latest_rows(_movement_frame(),unique(locs),_movement_sources,_event_value(_MOVEMENT_TABLES,"Parent","Child"),
        (child,ev,parent)->(ev.ledger_id,ev.slot,0,parent,child),starting,ending,time)
end

function get_last_movements_as_parent(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(locs)) && return _get_last_movements_as_parent_global(locs,starting,ending,time;encumbrances=encumbrances)
    # children that were ever placed in one of `locs`; whether it is still where each one is comes from its latest movement
    wanted = Set(locs)
    candidates = Int[]
    for chunk in Iterators.partition(unique(locs),500), table in _MOVEMENT_TABLES
        marks = "(" * join(fill("?",length(chunk)),",") * ")"
        append!(candidates,query_db("SELECT DISTINCT Child FROM $table WHERE Parent IN $marks",Tuple(chunk)).Child)
    end
    out = _latest_rows(_movement_frame(),sort!(unique(candidates)),_movement_sources,_event_value(_MOVEMENT_TABLES,"Parent","Child"),
        (child,ev,parent)->(ev.ledger_id,ev.slot,0,parent,child),starting,ending,time)
    return out[[!ismissing(p) && p in wanted for p in out.Parent],:]
end

function get_locks(location_ids::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(location_ids)) && return _get_locks_global(location_ids,starting,ending,time;encumbrances=encumbrances)
    return _latest_rows(DataFrame(LedgerID=Int[],SequenceID=Int[],EncumbranceID=Int[],LocationID=Int[],IsLocked=Int[]),unique(location_ids),
        _lock_sources,_event_value(_LOCK_TABLES,"IsLocked","LocationID"),(loc,ev,v)->(ev.ledger_id,ev.slot,0,loc,v),starting,ending,time)
end

function get_activity(location_ids::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(location_ids)) && return _get_activity_global(location_ids,starting,ending,time;encumbrances=encumbrances)
    return _latest_rows(DataFrame(LedgerID=Int[],SequenceID=Int[],EncumbranceID=Int[],LocationID=Int[],IsActive=Int[]),unique(location_ids),
        _activity_sources,_event_value(_ACTIVITY_TABLES,"IsActive","LocationID"),(loc,ev,v)->(ev.ledger_id,ev.slot,0,loc,v),starting,ending,time)
end

# ----------------------------------------------------------------------------------- instrument settings

"""
    get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Resolve `instrument_id`'s current value per `Setting` name as of `sequence_id`/`time`, as a
`DataFrame` (columns `Setting`, `Value`, `SequenceID`), ordered by `Setting`. Unlike [`get_reads`](@ref), this *does*
collapse to latest-wins per `Setting` -- instrument settings behave like [`Attribute`](@ref) (a single
current value), not like [`Read`](@ref) (many coexisting values) -- mirroring
`get_attribute_caches`'s `ledger_subset` idiom.
"""
function get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    reconstruction_mode[] === :legacy && return _get_instrument_settings_global(instrument_id,sequence_id,time)
    out = DataFrame(Setting=String[],Value=Union{Missing,String}[],SequenceID=Int[])
    for setting in query_db("SELECT DISTINCT Setting FROM InstrumentSettings WHERE InstrumentID = ? ORDER BY Setting",(instrument_id,)).Setting
        ev = latest_visible_event("InstrumentSettings",["InstrumentID"=>instrument_id,"Setting"=>setting],0,sequence_id,time)
        ev === nothing && continue
        value = query_db("SELECT Value FROM InstrumentSettings WHERE InstrumentID = ? AND Setting = ? AND LedgerID = ? ORDER BY ID LIMIT 1",
            (instrument_id,setting,ev.ledger_id)).Value[1]
        push!(out,(setting,value,ev.slot))
    end
    return out
end
