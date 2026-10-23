#=
"Last write wins" lookups: of the events recorded for one key (a child, a location, an instrument setting) the
visible one with the highest sequence ID is the current one. Reading the key's events through an index
`(key, LedgerID)` is not enough on its own, because the row order of an operation table is not the order of the
history: an amendment adds a row with a high ID and an old slot, and an insert renumbers slots without touching
any operation row. So the position of an event has to come from the ledger, and two exact searches are used,
stopping when either one finishes:

  - the tick walk reads `Ledger` backwards along `(SequenceID, ID)`, takes each slot's visible revision, and
    probes the key's index for it; the first slot with an event is the answer. Cost: the number of slots between
    the end of the window and the latest event.
  - the series scan reads every event of the key through its index and keeps the visible one in the latest slot.
    Cost: the number of events of the key.

The walk runs over windows of growing length; once a walk has failed, the number of events is counted, and if it
is no more than a few windows the series scan finishes the job.
=#

# Refs so the tests can force every schedule
const _WALK_FIRST_WINDOW = Ref(128)
const _WALK_GROWTH = Ref(8)
const _SERIES_SCAN_FACTOR = Ref(4)

# `table` rows with `key` (a vector of column => value) in the window; returns `nothing` or (ledger_id, slot).
"""
    latest_visible_event(table, key, from, to, time; extra="") -> Union{Nothing,NamedTuple{(:ledger_id,:slot)}}

The visible event in the highest slot of `from..to` among the rows of `table` whose columns equal `key` (a vector
of `column => value`), as of `time`; `extra` adds an SQL condition on the table alias `e`. Returns the ledger
row of that slot and the slot, or `nothing` if the key has no visible event in the window. See the note at the
top of this file for how it is found.
"""
function latest_visible_event(table::AbstractString,key::AbstractVector{<:Pair},from::Integer,to::Integer,time::DateTime;extra::AbstractString="")
    to = min(to,query_db("SELECT SequenceID FROM Ledger ORDER BY SequenceID DESC LIMIT 1")[1,1]) # no slot lies beyond the last one
    from > to && return nothing
    t = db_time(time)
    conds = join(["e.$c = ?" for (c,_) in key]," AND ") * (isempty(extra) ? "" : " AND ($extra)")
    kvals = Any[v for (_,v) in key]
    pred = _visible_predicate("vl","?","?","?")
    walk = "SELECT vl.ID AS ledger_id, vl.SequenceID AS slot FROM Ledger vl CROSS JOIN $table e ON e.LedgerID = vl.ID WHERE $pred AND $conds ORDER BY vl.SequenceID DESC LIMIT 1"
    function walk_window(lo)
        r = query_db(walk,Tuple(vcat(Any[lo,to,t,t],kvals)))
        return nrow(r) == 0 ? nothing : (ledger_id=r.ledger_id[1],slot=r.slot[1])
    end
    function series()
        r = query_db("SELECT vl.ID AS ledger_id, vl.SequenceID AS slot FROM $table e CROSS JOIN Ledger vl ON vl.ID = e.LedgerID WHERE $conds AND $pred ORDER BY vl.SequenceID DESC LIMIT 1",
            Tuple(vcat(kvals,Any[from,to,t,t])))
        return nrow(r) == 0 ? nothing : (ledger_id=r.ledger_id[1],slot=r.slot[1])
    end
    width = _WALK_FIRST_WINDOW[]
    series_length = nothing
    while true
        lo = max(from,to - width + 1)
        found = walk_window(lo)
        (found !== nothing || lo <= from) && return found
        if series_length === nothing
            series_length = query_db("SELECT COUNT(*) AS n FROM $table e WHERE $conds",Tuple(kvals)).n[1]
        end
        series_length <= _SERIES_SCAN_FACTOR[] * width && return series()
        width *= _WALK_GROWTH[]
    end
end

"""
    latest_visible_event(sources, from, to, time) -> Union{Nothing,NamedTuple{(:source,:ledger_id,:slot)}}

The latest visible event over several event tables, `sources` being tuples `(table, key, extra)` as above.
When two sources have an event in the same slot the earlier source wins.
"""
function latest_visible_event(sources,from::Integer,to::Integer,time::DateTime)
    best = nothing
    for (i,(table,key,extra)) in enumerate(sources)
        ev = latest_visible_event(table,key,from,to,time;extra=extra)
        ev === nothing && continue
        (best === nothing || ev.slot > best.slot) && (best = (source=i,ledger_id=ev.ledger_id,slot=ev.slot))
    end
    return best
end

# the movement events of a child: an operation table and its observation table, as in `movement_events`
_movement_sources(child) = [("Movements",["Child"=>child],""),("ObservedParents",["Child"=>child],"")]
_lock_sources(loc) = [("Locks",["LocationID"=>loc],""),("ObservedLocks",["LocationID"=>loc],"")]
_activity_sources(loc) = [("Activity",["LocationID"=>loc],""),("ObservedActivity",["LocationID"=>loc],"")]
