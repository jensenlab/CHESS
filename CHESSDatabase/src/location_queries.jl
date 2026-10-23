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
    global_path() = _find_locations_global(;kind=kind,name=name,parent=parent,barcode=barcode,active=active,ignorecase=ignorecase,
        sequence_id=sequence_id,time=time,limit=limit,offset=offset)
    reconstruction_mode[] === :legacy && return global_path()
    ids = _location_candidates(kind,name,parent,barcode,ignorecase)
    ids === nothing && return global_path()      # no filter that names few locations: one pass over the ledger is the right plan
    states = _location_states(ids,sequence_id,time)
    keep = filter(states) do s
        (isnothing(kind) || s.Kind == _kind_name(kind)) &&
        (isnothing(name) || (ignorecase ? lowercase(s.Name) == lowercase(String(name)) : s.Name == String(name))) &&
        (parent === nothing ? ismissing(s.ParentID) : (ismissing(parent) || (!ismissing(s.ParentID) && s.ParentID == Int(parent)))) &&
        (isnothing(active) || s.IsActive == Bool(active))
    end
    sort!(keep;by=s->s.ID)
    isnothing(limit) || (keep = keep[min(offset+1,end+1):min(offset+limit,end)])
    return _location_frame(keep)
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
    reconstruction_mode[] === :legacy && return _descendants_global(location_id;kinds=kinds,max_depth=max_depth,sequence_id=sequence_id,time=time)
    kind_names = isnothing(kinds) ? nothing : Set(_kind_name.(collect(kinds)))
    limit_depth = something(max_depth,typemax(Int32))
    rows = NamedTuple[]
    seen = Set{Int}(Int(location_id))
    level = Int[Int(location_id)]
    depth = 0
    while !isempty(level) && (depth == 0 || depth < limit_depth)
        depth += 1
        candidates = _children_candidates(level)
        below = Set(level)
        next = Int[]
        for s in _location_states(candidates,sequence_id,time)
            (ismissing(s.ParentID) || !(s.ParentID in below) || s.ID in seen) && continue
            push!(seen,s.ID); push!(next,s.ID)
            (isnothing(kind_names) || s.Kind in kind_names) && push!(rows,merge(s,(Depth=depth,)))
        end
        level = next
    end
    sort!(rows;by=r->(r.Depth,r.ID))
    out = _location_frame(rows)
    out.Depth = Int[r.Depth for r in rows]
    return out
end

# ---------------------------------------------------------------------------- the filter-first path

const _CANDIDATE_LIMIT = 5000    # more candidates than this and one pass over the ledger is cheaper

_in_marks(chunk) = "(" * join(fill("?",length(chunk)),",") * ")"

# the locations that have ever been placed in one of `parents`: by a movement or an observation, or as a well of that labware
function _children_candidates(parents::AbstractVector{<:Integer})
    out = Set{Int}()
    for chunk in Iterators.partition(unique(parents),500)
        for table in _MOVEMENT_TABLES
            union!(out,query_db("SELECT DISTINCT Child FROM $table WHERE Parent IN $(_in_marks(chunk))",Tuple(chunk)).Child)
        end
        union!(out,query_db("SELECT WellID FROM Containment WHERE ContainerID IN $(_in_marks(chunk))",Tuple(chunk)).WellID)
    end
    return sort!(collect(out))
end

# Location ids that include every location matching the filters, chosen through an index, or `nothing` when no
# filter names few enough locations.
function _location_candidates(kind,name,parent,barcode,ignorecase)
    if !isnothing(barcode)
        return Int.(query_db("SELECT LocationID FROM Barcodes WHERE Barcode = ?",(string(barcode),)).LocationID |> skipmissing |> collect)
    end
    if !isnothing(name) && !ignorecase
        return Int.(query_db("SELECT ID FROM Locations WHERE Name = ?",(String(name),)).ID)
    end
    if !(parent === nothing || ismissing(parent))
        ids = _children_candidates([Int(parent)])
        length(ids) <= _CANDIDATE_LIMIT && return ids
    end
    if !isnothing(kind)
        n = query_db("SELECT COUNT(*) AS n FROM Locations WHERE Type = ?",(_kind_name(kind),)).n[1]
        n <= _CANDIDATE_LIMIT && return Int.(query_db("SELECT ID FROM Locations WHERE Type = ?",(_kind_name(kind),)).ID)
    end
    return nothing
end

# the state `_location_state_cte` gives each location, for these locations only: parent and activity are the
# latest visible movement and activity events, and a location that never moved has its labware (if any) as parent
function _location_states(ids::AbstractVector{<:Integer},sequence_id::Integer,time::DateTime)
    out = NamedTuple{(:ID,:Name,:Kind,:ParentID,:IsActive),Tuple{Int,String,String,Union{Missing,Int},Bool}}[]
    for chunk in Iterators.partition(ids,500)
        info = query_db("SELECT ID, Name, Type FROM Locations WHERE ID IN $(_in_marks(chunk))",Tuple(chunk))
        container = Dict{Int,Int}(r.WellID => r.ContainerID for r in eachrow(query_db("SELECT WellID, ContainerID FROM Containment WHERE WellID IN $(_in_marks(chunk))",Tuple(chunk))))
        for r in eachrow(info)
            id = Int(r.ID)
            mv = latest_visible_event(_movement_sources(id),0,sequence_id,time)
            parent = mv === nothing ? get(container,id,missing) :
                _event_value(_MOVEMENT_TABLES,"Parent","Child")(mv.source,id,mv.ledger_id)
            ac = latest_visible_event(_activity_sources(id),0,sequence_id,time)
            active = ac === nothing ? true : Bool(_event_value(_ACTIVITY_TABLES,"IsActive","LocationID")(ac.source,id,ac.ledger_id))
            push!(out,(ID=id,Name=String(r.Name),Kind=String(r.Type),ParentID=parent,IsActive=active))
        end
    end
    return out
end

function _location_frame(rows)
    return DataFrame(ID=Int[r.ID for r in rows],Name=String[r.Name for r in rows],Kind=String[r.Kind for r in rows],
        ParentID=Union{Missing,Int}[r.ParentID for r in rows],IsActive=Bool[r.IsActive for r in rows])
end

function _find_locations_global(;kind=nothing,name=nothing,parent=missing,barcode=nothing,active=nothing,ignorecase::Bool=false,
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

function _descendants_global(location_id::Integer;kinds=nothing,max_depth::Union{Integer,Nothing}=nothing,
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
