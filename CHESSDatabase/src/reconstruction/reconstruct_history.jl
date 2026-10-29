#=
The history of one facet of a location: the rows at which its value changed, over a window of slots.

A history is built from timelines. A timeline over the window `[lo, hi]` is a list of rows ordered by slot whose
first row is the state in force at `lo` (the row of the event, or cache, that produced it; it may lie before `lo`)
and whose other rows are the changes in `(lo, hi]`. The value at a slot `s` in `[lo, hi]` is the value of the last
row with `SequenceID <= s`; a timeline with no such row has no value yet.

Own facets (an attribute set on the location itself, its parent, lock, activity, lot, an instrument setting) read
the rows of one key:

  - the state at `lo` comes from the seek of `latest_event.jl` on each source of the facet (the event tables and
    the cache table), over `[0, lo]`;
  - the rows in `(lo, hi]` are read with the better of two exact searches, as in `latest_event.jl`: the tick walk
    over `Ledger` in the window, or a scan of the key's series through its index, whichever touches fewer rows.

How the rows combine is what `reconstruct_*` does, so that the value at a slot is the one the reconstruction gives:

  - attribute, lock, activity: the newest cache at or before the slot is the state; an event at or after that
    cache's slot replaces it. Ordering the rows by (slot, caches first) and keeping the last one is the same rule.
  - parent: as `reconstruct_parent`. A cache with no parent hides every movement before it. A cache with a parent
    does not (the movement in the window `[0, s]` wins over it), and it is the value only when the location was
    never moved.
  - lot, instrument setting: no caches; the last row wins.

The effective value of an attribute is the nearest ancestor-or-self whose own value is not `missing`. It is composed
from timelines: the own timeline, the parent timeline cut into intervals with one parent each, and for each interval
the effective timeline of that parent over exactly that interval. The cost is the number of rows of the chain
members inside the window and not the length of the ledger.

Ties (two events of one key in the same slot) are not defined, as for the other seeks.
=#

const _HISTORY_FIRST_WINDOW = Ref(256)
const _HISTORY_GROWTH = Ref(8)
const _HISTORY_MAX_DEPTH = 64

# one row of a timeline. `rid` is the row's primary key in its table, `kind` is `:event` or `:cache`;
# `ledger == 0` marks the row of "no event yet".
struct _HRow
    slot::Int
    ledger::Int
    rid::Int
    value::Any
    unit::Any
    event::String
    kind::Symbol
    origin::Int
end

_hvirtual(origin) = _HRow(-1,0,0,missing,missing,"",:event,origin)
_isvirtual(r::_HRow) = r.ledger == 0

# a place rows are read from
struct _HSource
    table::String
    key::Vector{Pair{String,Any}}
    extra::String
    kind::Symbol
    event::String
    value::String   # SQL on the alias `e`
    unit::String
end

_sql_literal(s::AbstractString) = "'" * replace(s,"'"=>"''") * "'"

_cached_attribute(col,name) = "(SELECT a.$col FROM CachedAttributes a WHERE a.AttributeSetID = e.AttributeSetID AND a.AttributeID = $(_sql_literal(name)))"

function _history_sources(facet::Symbol,name::String,loc::Integer)
    if facet === :attribute
        key = ["LocationID"=>loc,"Attribute"=>name]
        return [_HSource("EnvironmentAttributes",key,"",:event,"set_attribute","e.Value","e.Unit"),
                _HSource("ObservedAttributes",key,"e.IsInherited = 0",:event,"observe_attribute","e.Value","e.Unit"),
                _HSource("CachedEnvironments",["LocationID"=>loc],"",:cache,"cache",_cached_attribute("Value",name),_cached_attribute("Unit",name))]
    elseif facet === :locked
        key = ["LocationID"=>loc]
        return [_HSource("Locks",key,"",:event,"set_lock","e.IsLocked","NULL"),
                _HSource("ObservedLocks",key,"",:event,"observe_lock","e.IsLocked","NULL"),
                _HSource("CachedLockActivity",key,"",:cache,"cache","e.IsLocked","NULL")]
    elseif facet === :active
        key = ["LocationID"=>loc]
        return [_HSource("Activity",key,"",:event,"set_activity","e.IsActive","NULL"),
                _HSource("ObservedActivity",key,"",:event,"observe_activity","e.IsActive","NULL"),
                _HSource("CachedLockActivity",key,"",:cache,"cache","e.IsActive","NULL")]
    elseif facet === :parent
        return [_HSource("Movements",["Child"=>loc],"",:event,"move","e.Parent","NULL"),
                _HSource("ObservedParents",["Child"=>loc],"",:event,"observe_parent","e.Parent","NULL"),
                _HSource("CachedAncestors",["LocationID"=>loc],"",:cache,"cache","e.ParentID","NULL")]
    elseif facet === :lot
        return [_HSource("ObservedLots",["LocationID"=>loc],"",:event,"observe_lot",
            "(SELECT p.Supplier || ' ' || p.CatalogNumber || ' lot ' || e.Lot FROM Products p WHERE p.ID = e.ProductID)","NULL")]
    elseif facet === :setting
        return [_HSource("InstrumentSettings",["InstrumentID"=>loc,"Setting"=>name],"",:event,"set_instrument_setting","e.Value","NULL")]
    end
    throw(ArgumentError("no history for facet $facet"))
end

_conditions(src::_HSource) = join(["e.$c = ?" for (c,_) in src.key]," AND ") * (isempty(src.extra) ? "" : " AND ($(src.extra))")

function _hrow(r,src::_HSource,origin)
    return _HRow(r.slot,r.ledger_id,r.rid,r.value,r.unit,src.event,src.kind,origin)
end

# The SQL and parameters of the rows of `src` in the slots `lo..hi`: a walk of `Ledger` over the window or a scan of
# the key's series (a function of its own so a test can explain the plans).
function _window_query(src::_HSource,lo::Integer,hi::Integer,time::DateTime,walk::Bool)
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    conds = _conditions(src)
    kvals = Any[v for (_,v) in src.key]
    cols = "vl.SequenceID AS slot, vl.ID AS ledger_id, e.ID AS rid, $(src.value) AS value, $(src.unit) AS unit"
    walk && return "SELECT $cols FROM Ledger vl CROSS JOIN $(src.table) e ON e.LedgerID = vl.ID WHERE $pred AND $conds ORDER BY vl.SequenceID, e.ID",
        Tuple(vcat(Any[lo,hi,t,t],kvals))
    return "SELECT $cols FROM $(src.table) e CROSS JOIN Ledger vl ON vl.ID = e.LedgerID WHERE $conds AND $pred ORDER BY vl.SequenceID, e.ID",
        Tuple(vcat(kvals,Any[lo,hi,t,t]))
end

# the rows of `src` in the slots `lo..hi`, oldest first (a cache before an event of the same slot)
function _window_rows(src::_HSource,lo::Integer,hi::Integer,time::DateTime,origin::Integer)
    out = _HRow[]
    last_slot = query_db("SELECT SequenceID FROM Ledger ORDER BY SequenceID DESC LIMIT 1")[1,1]
    hi = min(hi,last_slot)
    lo > hi && return out
    width = hi - lo + 1
    cap = _SERIES_SCAN_FACTOR[] * width
    n = query_db("SELECT COUNT(*) AS n FROM (SELECT 1 FROM $(src.table) e WHERE $(_conditions(src)) LIMIT $(cap + 1))",Tuple(v for (_,v) in src.key)).n[1]
    sql,params = _window_query(src,lo,hi,time,n > cap)   # a short series is scanned, a short window is walked
    for r in eachrow(query_db(sql,params))
        push!(out,_hrow(r,src,origin))
    end
    return out
end

# the last row of `src` in the slots `0..at` (the state its key is in at `at`), or `nothing`
function _row_at(src::_HSource,at::Integer,time::DateTime,origin::Integer)
    ev = latest_visible_event(src.table,src.key,0,at,time;extra=src.extra)
    ev === nothing && return nothing
    kvals = Any[v for (_,v) in src.key]
    r = query_db("SELECT $(ev.slot) AS slot, e.LedgerID AS ledger_id, e.ID AS rid, $(src.value) AS value, $(src.unit) AS unit FROM $(src.table) e WHERE $(_conditions(src)) AND e.LedgerID = ? ORDER BY e.ID DESC LIMIT 1",
        Tuple(vcat(kvals,Any[ev.ledger_id])))
    nrow(r) == 0 && return nothing
    return _hrow(r[1,:],src,origin)
end

# `(slot, caches first, row id)`: the order in which rows of one key are applied
_order_key(r::_HRow) = (r.slot,r.kind === :cache ? 0 : 1,r.rid)

mutable struct _HState
    ev::Union{Nothing,_HRow}
    cache::Union{Nothing,_HRow}
end

_apply!(st::_HState,r::_HRow) = (r.kind === :cache ? (st.cache = r) : (st.ev = r); st)

# the row that gives the value in the state
function _chosen(facet::Symbol,st::_HState,origin::Integer)
    ev,c = st.ev,st.cache
    if facet === :parent
        c === nothing && return ev === nothing ? _hvirtual(origin) : ev
        if ismissing(c.value)           # a cache without a parent hides the movements before it
            return (ev !== nothing && ev.slot >= c.slot) ? ev : c
        end
        return ev !== nothing ? ev : c  # a cache with a parent hides nothing
    end
    ev === nothing && return c === nothing ? _hvirtual(origin) : c
    c === nothing && return ev
    return ev.slot >= c.slot ? ev : c
end

_same_row(a::_HRow,b::_HRow) = a.ledger == b.ledger && a.rid == b.rid && a.kind === b.kind && a.slot == b.slot

# the timeline of an own facet over `lo..hi`. With `collapse`, a row that does not change value or unit is left out.
function _own_timeline(facet::Symbol,name::String,loc::Integer,lo::Integer,hi::Integer,time::DateTime;collapse::Bool=true)
    sources = _history_sources(facet,name,loc)
    st = _HState(nothing,nothing)
    for src in sources
        r = _row_at(src,lo,time,loc)
        r === nothing && continue
        # the latest row of each kind; among events the later one
        if r.kind === :cache
            st.cache = r
        elseif st.ev === nothing || _order_key(r) > _order_key(st.ev)
            st.ev = r
        end
    end
    first_row = _chosen(facet,st,loc)
    out = _HRow[first_row]
    rows = _HRow[]
    for src in sources
        append!(rows,_window_rows(src,lo + 1,hi,time,loc))
    end
    sort!(rows;by=_order_key)
    for r in rows
        _apply!(st,r)
        c = _chosen(facet,st,loc)
        _same_row(c,out[end]) && continue
        if length(out) > 1 && out[end].slot == c.slot
            out[end] = c      # two rows in one slot: the last one stands
        else
            push!(out,c)
        end
    end
    _blank_start(out,loc)
    collapse && (out = _collapsed(out))
    return out
end

# A first row that has no value (a cache without the attribute, or an un-set) says nothing: it is the "no event yet" row.
_blank_start(rows::Vector{_HRow},origin) = (!isempty(rows) && ismissing(rows[1].value) && !_isvirtual(rows[1]) && (rows[1] = _hvirtual(origin)); rows)

_samevalue(a::_HRow,b::_HRow) = isequal(a.value,b.value) && isequal(a.unit,b.unit) && a.origin == b.origin

# the first row is kept; a later row stays when it differs from the one before it
function _collapsed(rows::Vector{_HRow})
    isempty(rows) && return rows
    out = _HRow[rows[1]]
    for r in @view rows[2:end]
        _samevalue(r,out[end]) && continue
        push!(out,r)
    end
    return out
end

# the last row of `rows` (ordered by position) at or before `p`
function _row_in_force(rows::Vector{_HRow},pos::Vector{Int},p::Int)
    k = searchsortedlast(pos,p)
    return k == 0 ? nothing : rows[k]
end

# the effective value of the attribute `name` of `loc` over `lo..hi`
function _effective_timeline(name::String,loc::Integer,lo::Integer,hi::Integer,time::DateTime,depth::Integer)
    depth > _HISTORY_MAX_DEPTH && throw(ErrorException("the parent chain of location $loc is deeper than $_HISTORY_MAX_DEPTH or has a cycle"))
    own = _own_timeline(:attribute,name,loc,lo,hi,time)
    par = _own_timeline(:parent,"",loc,lo,hi,time)
    ownpos = [max(r.slot,lo) for r in own]
    parpos = [max(r.slot,lo) for r in par]
    subs = Vector{Vector{_HRow}}(undef,length(par))
    subpos = Vector{Vector{Int}}(undef,length(par))
    for j in eachindex(par)
        istart = parpos[j]
        iend = j < length(par) ? par[j+1].slot - 1 : hi
        q = par[j].value
        if ismissing(q) || istart > iend
            subs[j] = _HRow[]
        else
            subs[j] = _effective_timeline(name,Int(q),istart,iend,time,depth + 1)
        end
        subpos[j] = [max(r.slot,istart) for r in subs[j]]
    end
    points = Set{Int}(ownpos)
    union!(points,parpos)
    for j in eachindex(par)
        union!(points,subpos[j])
    end
    out = _HRow[]
    for p in sort!(collect(points))
        o = _row_in_force(own,ownpos,p)
        j = max(searchsortedlast(parpos,p),1)
        pr = par[j]
        s = _row_in_force(subs[j],subpos[j],p)
        winner = nothing
        if o !== nothing && !ismissing(o.value)
            winner = o
        elseif s !== nothing && !ismissing(s.value)
            winner = s
        end
        value = winner === nothing ? missing : winner.value
        unit = winner === nothing ? missing : winner.unit
        origin = winner === nothing ? Int(loc) : winner.origin
        # the row that changed the value at p
        real = filter(r -> r !== nothing && !_isvirtual(r),(o,s,pr))
        decider = nothing
        if p > lo
            at_p = filter(r -> r.slot == p,real)
            decider = if winner !== nothing && any(r -> r === winner,at_p)
                winner
            elseif any(r -> r === pr,at_p)
                pr
            elseif !isempty(at_p)
                at_p[1]
            end
            slot = p
        else
            # the state at lo: the latest change among the rows that make the value
            made_by = winner === nothing ? real : filter(r -> r === winner || r === pr,real)
            winner !== nothing && winner === o && (made_by = [o])
            decider = isempty(made_by) ? nothing : made_by[argmax([r.slot for r in made_by])]
            slot = decider === nothing ? -1 : decider.slot
        end
        row = decider === nothing ? _HRow(slot,0,0,value,unit,"",:event,origin) :
              _HRow(slot,decider.ledger,decider.rid,value,unit,decider.event,decider.kind,origin)
        if isempty(out) || !_samevalue(row,out[end])
            push!(out,row)
        end
    end
    return _blank_start(out,loc)
end

# ------------------------------------------------------------------------------------------ the public function

_history_frame() = DataFrame(SequenceID=Int[],LedgerID=Int[],Time=DateTime[],Value=Any[],Unit=Union{Missing,String}[],Origin=Int[],Event=String[])

# what the facet argument names: (:attribute | :read | :parent | :locked | :active | :lot | :setting | :contents, name)
function _resolve_facet(facet)
    facet isa AttributeKind && return (:attribute,String(facet.name))
    facet isa ReadKind && return (:read,String(facet.name))
    if facet isa Tuple && length(facet) == 2 && Symbol(facet[1]) === :setting
        return (:setting,String(facet[2]))
    end
    (facet isa Symbol || facet isa AbstractString) || throw(ArgumentError("unknown history facet $(repr(facet))"))
    f = Symbol(facet)
    f in (:parent,:locked,:active,:lot,:contents) && return (f,"")
    haskey(attribute_kinds,f) && return (:attribute,String(f))
    haskey(read_kinds,f) && return (:read,String(f))
    throw(ArgumentError("unknown history facet $(repr(facet)): expected an attribute or read kind, :parent, :locked, :active, :lot, :contents or (:setting, name)"))
end

# Time of the ledger rows
function _ledger_times(ids)
    times = Dict{Int,DateTime}()
    for chunk in Iterators.partition(unique(ids),_id_chunk)
        df = query_db("SELECT ID, Time FROM Ledger WHERE ID IN $(_marks(length(chunk)))",Tuple(chunk))
        for r in eachrow(df)
            times[r.ID] = julia_time(r.Time)
        end
    end
    return times
end

function _history_value(kind::Symbol,v)
    ismissing(v) && return missing
    kind in (:locked,:active) && return Bool(v)
    kind === :parent && return Int(v)
    kind === :attribute && return Float64(v)
    return v
end

"""
    reconstruct_history(location_id::Integer, facet; from=0, to=get_last_sequence_id(), time=Dates.now(),
                        effective=nothing, order=:asc, limit=nothing, after=nothing, collapse=true, encumbrances=false) -> DataFrame

The history of one facet of a location: the rows at which its value changed between the slots `from` and `to`, as
recorded by the ledger as of `time`.

`facet` is an attribute kind or its name (`attr"Temperature"`, `:Temperature`), `:parent` (the id of the parent,
`missing` for none), `:locked`, `:active`, `:lot` (supplier, catalog number and lot of the lot observed on the
labware), `(:setting, name)` (an instrument setting, `location_id` being the instrument) or a read kind (the reads
of that kind, by the time of the read). `:contents` is not available yet.

The columns are `SequenceID`, `LedgerID`, `Time` (of the ledger row; of the read for a read kind), `Value`, `Unit`,
`Origin` and `Event`. `Origin` is the location whose value this is: the location itself, or for an effective
attribute the ancestor it was inherited from. `Event` names the operation (`set_attribute`, `observe_attribute`,
`move`, `observe_parent`, `set_lock`, `observe_lock`, `set_activity`, `observe_activity`, `observe_lot`,
`set_instrument_setting`, `read`), or `cache` where a cache snapshot gives the value; for an effective attribute
it is the event that changed the value, which can be a move. 

The value at a slot `s` is the `Value` of the last row with `SequenceID <= s` ([`history_value_at`](@ref)); no such row
means the facet has not been set (a default applies). The first row is the state in force at `from`, with the slot of
the event that last set it, which can lie before `from`. For a read kind the rows are the reads, ordered by the
time of the read.

# Keyword Arguments
1) `from`, `to`: the slots; `to` defaults to the last one.
2) `time`: only operations recorded at or before `time` count, as in [`reconstruct_location`](@ref).
3) `effective`: for an attribute, `true` (the default) gives the value the location actually had, taken from the
   nearest ancestor-or-self whose own value was not `missing`; `false` gives only the events recorded on the location
   itself. Other facets have no effective form and only accept `false`.
4) `order`: `:asc` (oldest first, the default) or `:desc`.
5) `limit`, `after`: a page of at most `limit` rows. `after` is the `SequenceID` of the last row of the previous page
   (for a read kind, its `Time`); the page holds the rows after it in the chosen order. Only the part of the history
   a page needs is read.
6) `collapse`: with `true` (the default) a row is kept only if its `Value`, `Unit` or `Origin` differs from the row
   before it. `false` keeps every event and cache row of an own facet (an effective history is always collapsed).
7) `encumbrances`: planned operations are not included yet; `true` throws an `ArgumentError`.

The value at every slot equals the value of the matching `reconstruct_*` at that slot and `time`.
"""
function reconstruct_history(location_id::Integer,facet;from::Integer=0,to::Union{Integer,Nothing}=nothing,time::DateTime=Dates.now(),
        effective::Union{Bool,Nothing}=nothing,order::Symbol=:asc,limit::Union{Integer,Nothing}=nothing,after=nothing,
        collapse::Bool=true,encumbrances::Bool=false)
    encumbrances && throw(ArgumentError("reconstruct_history does not include planned (encumbered) operations yet"))
    order in (:asc,:desc) || throw(ArgumentError("order must be :asc or :desc, got $(repr(order))"))
    isnothing(limit) || limit >= 1 || throw(ArgumentError("limit must be at least 1"))
    kind,name = _resolve_facet(facet)
    kind === :contents && throw(ArgumentError("the history of :contents is not available yet"))
    to = something(to,get_last_sequence_id())
    from = max(from,0)
    kind === :read && return _read_history(location_id,name,from,to,time,order,limit,after)
    isnothing(after) || after isa Integer || throw(ArgumentError("after must be a SequenceID"))
    eff = something(effective,kind === :attribute)
    eff && kind !== :attribute && throw(ArgumentError("only an attribute has an effective history (effective=false for :$kind)"))
    timeline = (lo,hi) -> eff ? _effective_timeline(name,location_id,lo,hi,time,0) : _own_timeline(kind,name,location_id,lo,hi,time;collapse=collapse)
    rows = _history_pages(timeline,from,to,order,limit,after)
    isempty(rows) && return _history_frame()
    times = _ledger_times([r.ledger for r in rows])
    return DataFrame(SequenceID=[r.slot for r in rows],LedgerID=[r.ledger for r in rows],Time=[times[r.ledger] for r in rows],
        Value=Any[_history_value(kind,r.value) for r in rows],Unit=Union{Missing,String}[ismissing(r.unit) ? missing : String(r.unit) for r in rows],
        Origin=[r.origin for r in rows],Event=[r.event for r in rows])
end

# The rows of the page, `timeline(lo, hi)` being the timeline of the window.
function _history_pages(timeline,from::Int,to::Int,order::Symbol,limit,after)
    real(rows) = filter(r -> !_isvirtual(r),rows)
    width = _HISTORY_FIRST_WINDOW[]
    if order === :asc
        lo = isnothing(after) ? from : max(from,after)
        lo > to && return _HRow[]
        keep(rows) = isnothing(after) ? real(rows) : filter(r -> r.slot > after,real(rows))
        isnothing(limit) && return keep(timeline(lo,to))
        hi = min(to,lo + width - 1)
        while true
            rows = keep(timeline(lo,hi))
            (length(rows) >= limit || hi >= to) && return rows[1:min(limit,length(rows))]
            width *= _HISTORY_GROWTH[]
            hi = min(to,lo + width - 1)
        end
    else
        hi = isnothing(after) ? to : min(to,after - 1)
        hi < from && return _HRow[]
        isnothing(limit) && return reverse(real(timeline(from,hi)))
        lo = max(from,hi - width + 1)
        while true
            rows = timeline(lo,hi)
            exact = real(lo == from ? rows : rows[2:end])  # the first row of a window stands for the state before it
            if length(exact) >= limit || lo == from
                exact = reverse(exact)
                return exact[1:min(limit,length(exact))]
            end
            width *= _HISTORY_GROWTH[]
            lo = max(from,hi - width + 1)
        end
    end
end

"""
    history_value_at(history::DataFrame, sequence_id::Integer) -> Any

The value a [`reconstruct_history`](@ref) result gives at `sequence_id`: the `Value` of its last row with
`SequenceID <= sequence_id`, or `missing` when there is none. The result must be in ascending order.
"""
function history_value_at(history::DataFrame,sequence_id::Integer)
    k = searchsortedlast(history.SequenceID,sequence_id)
    return k == 0 ? missing : history.Value[k]
end

# the reads of one kind, paged by the time of the read
function _read_history(location_id,name,from,to,time,order,limit,after)
    isnothing(after) || after isa DateTime || throw(ArgumentError("after must be the Time of the last row for a read kind"))
    t = db_time(time)
    pred = _visible_predicate("vl","?","?","?")
    key = "COALESCE(r.InstrumentTime, r.Time)"
    params = Any[from,to,t,t,location_id,name]
    bounds = ""
    if !isnothing(after)
        # strictly after, at the millisecond the times are kept in
        bounds = order === :asc ? " AND $key > ?" : " AND $key < ?"
        push!(params,db_time(after))
    end
    dir = order === :asc ? "ASC" : "DESC"
    page = ""
    if !isnothing(limit)
        page = " LIMIT ?"
        push!(params,limit)
    end
    rows = query_db("""
        SELECT r.LedgerID AS LedgerID, vl.SequenceID AS SequenceID, $key AS T, r.Value AS Value, r.Unit AS Unit
        FROM Reads r CROSS JOIN Ledger vl ON vl.ID = r.LedgerID AND $pred
        WHERE r.LocationID = ? AND r.Type = ?$bounds
        ORDER BY $key $dir, r.ID $dir$page""",Tuple(params))
    out = _history_frame()
    for r in eachrow(rows)
        v = ismissing(r.Value) ? missing : (ismissing(r.Unit) ? r.Value : parse(Float64,r.Value))
        push!(out,(r.SequenceID,r.LedgerID,julia_time(r.T),v,r.Unit,Int(location_id),"read"))
    end
    return out
end
