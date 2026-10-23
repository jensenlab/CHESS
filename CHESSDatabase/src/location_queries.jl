# Queries over many locations at once: find locations by kind, name, parent, barcode or activity, and
# list the locations inside one. They read the ledger the way the reconstructions do: each sequence slot
# resolves to its newest revision no later than `time`, and the newest movement or activity entry at or
# before `sequence_id` wins. Nothing is cached, so an amendment changes the next answer.

# SQL for the ledger slots visible at (sequence_id, time), the parent of every location that has one, and
# the activity of every location whose activity was ever stated. A well that never moved has the labware
# in `Containment` as its parent.
const _location_state_cte = """
    ledger_subset (ID,SequenceID) AS (
        SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID),
    last_move (Child,Parent,SequenceID) AS (
        SELECT m.Child, m.Parent, Max(l.SequenceID)
        FROM $(movement_events) m INNER JOIN ledger_subset l ON m.LedgerID = l.ID GROUP BY m.Child),
    last_activity (LocationID,IsActive,SequenceID) AS (
        SELECT a.LocationID, a.IsActive, Max(l.SequenceID)
        FROM (SELECT LedgerID,LocationID,IsActive FROM Activity UNION ALL
              SELECT LedgerID,LocationID,IsActive FROM ObservedActivity) a
        INNER JOIN ledger_subset l ON a.LedgerID = l.ID GROUP BY a.LocationID),
    state (ID,Name,Kind,ParentID,IsActive) AS (
        SELECT loc.ID, loc.Name, loc.Type,
               CASE WHEN lm.Child IS NOT NULL THEN lm.Parent ELSE c.ContainerID END,
               COALESCE(la.IsActive,1)
        FROM Locations loc
        LEFT JOIN last_move lm ON lm.Child = loc.ID
        LEFT JOIN last_activity la ON la.LocationID = loc.ID
        LEFT JOIN Containment c ON c.WellID = loc.ID)
"""

_kind_name(k::LocationKind) = string(k.name)
_kind_name(k::Symbol) = string(k)
_kind_name(k::AbstractString) = String(k)

"""
    find_locations(; kind=nothing, name=nothing, parent=missing, barcode=nothing, active=nothing,
                   ignorecase=false, sequence_id=get_last_sequence_id(), time=Dates.now(),
                   limit=nothing, offset=0) -> DataFrame

Find locations that match every filter given, ordered by ID, with columns `ID`, `Name`, `Kind`,
`ParentID` (`missing` for none) and `IsActive`, as of `sequence_id` and `time`.

- `kind`: a [`LocationKind`](@ref), or its name as a `Symbol` or string.
- `name`: the exact name, or any case when `ignorecase = true`.
- `parent`: a location ID, or `nothing` for locations with no parent.
- `barcode`: a barcode string that is attached to the location.
- `active`: `true` or `false`.
- `limit` and `offset` page through the result.

The parent and activity are the ones in force at `sequence_id`. A well's parent is its labware. A
location that has never moved has no parent, and one whose activity was never stated is active.
"""
function find_locations(;kind=nothing,name=nothing,parent=missing,barcode=nothing,active=nothing,ignorecase::Bool=false,
        sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),limit::Union{Integer,Nothing}=nothing,offset::Integer=0)
    conds=String[]; params=Any[db_time(time),sequence_id]
    isnothing(kind) || (push!(conds,"Kind = ?"); push!(params,_kind_name(kind)))
    if !isnothing(name)
        push!(conds,ignorecase ? "lower(Name) = lower(?)" : "Name = ?"); push!(params,String(name))
    end
    if parent === nothing
        push!(conds,"ParentID IS NULL")
    elseif !ismissing(parent)
        push!(conds,"ParentID = ?"); push!(params,Int(parent))
    end
    isnothing(barcode) || (push!(conds,"ID IN (SELECT LocationID FROM Barcodes WHERE Barcode = ?)"); push!(params,string(barcode)))
    isnothing(active) || (push!(conds,"IsActive = ?"); push!(params,Int(active)))
    where_clause=isempty(conds) ? "" : "WHERE "*join(conds," AND ")
    page=isnothing(limit) ? "" : "LIMIT ? OFFSET ?"
    isnothing(limit) || push!(params,Int(limit),Int(offset))
    out=query_db("WITH $_location_state_cte SELECT * FROM state $where_clause ORDER BY ID $page",Tuple(params))
    out.IsActive=Bool.(out.IsActive)
    return out
end

"""
    descendants(location_id::Integer; kinds=nothing, max_depth=nothing,
                sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

Every location inside `location_id`, at any depth, as of `sequence_id` and `time`, with columns `ID`,
`Name`, `Kind`, `ParentID`, `IsActive` and `Depth` (1 for a direct child). `kinds` keeps only locations
of those kinds (a list of kind names or [`LocationKind`](@ref)s), though the search still passes through
the others, and `max_depth` limits how far down the search goes. Wells are included as the children of
their labware.
"""
function descendants(location_id::Integer;kinds=nothing,max_depth::Union{Integer,Nothing}=nothing,
        sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    params=Any[db_time(time),sequence_id,Int(location_id),something(max_depth,typemax(Int32))]
    kind_clause=""
    if !isnothing(kinds)
        names=_kind_name.(collect(kinds))
        kind_clause="WHERE Kind IN ("*join(fill("?",length(names)),",")*")"
        append!(params,names)
    end
    out=query_db("""
        WITH $_location_state_cte,
        tree (ID,Depth) AS (
            SELECT ID, 1 FROM state WHERE ParentID = ?
            UNION ALL
            SELECT s.ID, t.Depth + 1 FROM state s INNER JOIN tree t ON s.ParentID = t.ID WHERE t.Depth < ?)
        SELECT state.*, tree.Depth FROM tree INNER JOIN state ON state.ID = tree.ID $kind_clause
        ORDER BY tree.Depth, state.ID
        """,Tuple(params))
    out.IsActive=Bool.(out.IsActive)
    return out
end

"""
    reconstruct_locations(location_ids, sequence_id=get_last_sequence_id(), time=Dates.now()) -> Vector{Location}

Reconstruct each location in `location_ids` with [`reconstruct_location`](@ref). For a list of many
locations where only the name, kind, parent or activity is needed, [`find_locations`](@ref) reads them
in one query instead.
"""
reconstruct_locations(location_ids::AbstractVector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now()) =
    Location[reconstruct_location(id,sequence_id,time) for id in location_ids]
