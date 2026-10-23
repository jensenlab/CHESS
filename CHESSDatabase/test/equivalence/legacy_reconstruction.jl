# FROZEN ORACLE -- do not edit, do not "fix", do not delete code from it.
#
# A verbatim copy of the ledger-visibility reconstruction code of CHESSDatabase as it was at commit 4e09b96
# (ledger getters: d232bbd) (the original ledger_subset queries and everything that calls them), in its own module so the tests can
# call "the old function" next to the new one on the same database. Plan decision D9. It is deliberately
# independent of the production source: when production code changes, this file does not.
#
# Contents, in order: the ledger getters (ledger.jl); the pure helpers of reconstruction_utils.jl; the
# files reconstruct_{parent,children,attributes,environment,contents,lock,activity,reads,location}.jl whole;
# get_instrument_settings (instrument_settings.jl); get_all_protocols (encumbrances.jl);
# observation_discrepancies (observations.jl); reconstruct_lot (lots.jl); tracing.jl, forward_tracing.jl and
# location_queries.jl whole. Functions that read no ledger-visible state
# (get_location_info, get_stock, get_component, ...) are imported from CHESSDatabase instead of copied.
# The only edit is the module wrapper and the imports below.
module Legacy

using CHESSCore, Dates, DataFrames, Unitful
import CHESSDatabase
import CHESSDatabase: query_db, execute_db, db_time, julia_time, query_join_vector, get_location_info,
    get_stock, get_component, _parse_unit, get_sequence_id, container_wells, well_container, well_containers, _id_chunk

# ===================================================================== ledger.jl (getters)
"""
    get_last_ledger_id(time::DateTime=Dates.now())

Return the most recent ledger id entry at or before a certain time
"""
function get_last_ledger_id(time::DateTime=Dates.now())
    ledger_time = db_time(time)
    x = "SELECT Max(ID) FROM Ledger WHERE TIME <= ?"
    current_id = query_db(x,(ledger_time,))
    return current_id[1,1]
end

function get_last_ledger_id(sequence_id::Integer,time::DateTime=Dates.now())
    ledger_time=db_time(time)
    x="SELECT Max(ID) FROM LEDGER WHERE SequenceID = ? AND TIME <= ?"
    current_id=query_db(x,(sequence_id,ledger_time))
    return current_id[1,1]
end

"""
    get_last_sequence_id(time::DateTime=Dates.now()) -> Integer

The newest sequence ID in the ledger as of `time`: the current end of the history.
"""
function get_last_sequence_id(time::DateTime=Dates.now())
    ledger_time = db_time(time)
    x= "SELECT Max(SequenceID) FROM Ledger WHERE Time <= ?"
    current_id = query_db(x,(ledger_time,))
    return current_id[1,1]
end


function get_all_ledger_ids(sequence_id::Integer,time::DateTime=Dates.now())
    ledger_time=db_time(time)
    x="SELECT ID FROM LEDGER WHERE SequenceID = ? AND TIME <= ?"
    current_id=query_db(x,(sequence_id,ledger_time))
    return current_id[:,"ID"]
end


# ===================================================================== reconstruction_utils.jl (helpers)
"""
    location_reconstruction_index

Default (empty) value for `reconstruct_contents`'s `loc_index` accumulator: a map from `LocationID`
to every `(SequenceID, Location)` snapshot recorded for it during a single reconstruction pass.

This used to be a single `DataFrame` scanned in full (`filter` + `sort`) on every lookup via
`find_most_recent_location` -- correct, but with a reconstruction touching N locations across the
replay, that meant up to 2N linear scans of a structure that itself grows to ~2N rows, i.e. O(N²)
total work. A well fed by a heavily-reused hub location (thousands of transfers touch that hub over
a lab's lifetime) turned this into the dominant cost of reconstruction -- see the reconstruction
scaling benchmark's REPORT.md for the measurement (99.8% of wall time in this bookkeeping, only 0.2%
in the SQL query that finds the transfers in the first place). Keying by `LocationID` up front makes
each lookup scan only that *one* location's own (typically small) history instead of everything ever
touched in the whole reconstruction.

**Invariant: each location's entry vector is always appended in non-decreasing `SequenceID` order.**
Every `push_location!` call site in `reconstruct_contents.jl` is either a pre-replay-loop bootstrap
entry (`seq <= foot`) or a replay-loop entry (`seq == row.SequenceID`, with `transfers` fetched at
`SequenceID >= foot+1` and iterated in ascending `SequenceID` order). `find_most_recent_location`
relies on this invariant to binary-search each location's vector instead of scanning it -- see its
docstring. Any future `push_location!` call site must preserve non-decreasing order per location, or
that binary search silently returns wrong results instead of erroring.
"""
const location_reconstruction_index=Dict{Integer,Vector{Tuple{Integer,Location}}}()

"""
    push_location!(index, location_id, sequence_id, loc)

Record a `(sequence_id, loc)` snapshot for `location_id` in a `loc_index` accumulator (see
[`location_reconstruction_index`](@ref)). The `push!(all_locs, (id, seq, loc))` counterpart from the
old `DataFrame`-based accumulator.
"""
function push_location!(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer,loc::Location)
    entries = get!(() -> Tuple{Integer,Location}[], index, location_id)
    push!(entries, (sequence_id, loc))
    return nothing
end

"""
    find_most_recent_location(index, location_id)

Return the most recently pushed `Location` for `location_id` in a `loc_index` accumulator (see
[`location_reconstruction_index`](@ref)), or `nothing` if it has no entries. Relies on that type's
documented sortedness invariant: since entries are always appended in non-decreasing `SequenceID`
order, the most recent one is simply the last one -- O(1), no scan needed.
"""
function find_most_recent_location(index::Dict{<:Integer,<:Vector},location_id::Integer)
    haskey(index,location_id) || return nothing
    entries = index[location_id]
    isempty(entries) && return nothing
    return entries[end][2]
end

"""
    find_most_recent_location(index, location_id, sequence_id)

Return the most recently pushed `Location` for `location_id` with `SequenceID <= sequence_id`, or
`nothing` if none qualifies. Relies on the same sortedness invariant as the 2-arg method: since
entries are always appended in non-decreasing `SequenceID` order, a binary search
(`searchsortedlast`) finds the rightmost qualifying entry in O(log k) instead of a linear scan. Ties
(more than one entry at the same `sequence_id`) resolve to the last one pushed, matching the
insertion-order tie-breaking a linear max-scan would produce.
"""
function find_most_recent_location(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer)
    haskey(index,location_id) || return nothing
    entries = index[location_id]
    idx = searchsortedlast(entries, (sequence_id, nothing); by=first)
    idx == 0 && return nothing
    return entries[idx][2]
end

# Event sources for the "last write wins" reconstructions (parent/children, attributes, lock,
# activity): each unions an operation table with its observation table, so an observation replays
# exactly like the operation it declares the outcome of. Observed attributes that only confirmed an
# inherited value (IsInherited = 1) never become own attributes, so they're left out.
const movement_events = "(SELECT LedgerID,Parent,Child FROM Movements UNION ALL SELECT LedgerID,Parent,Child FROM ObservedParents)"
const transfer_events = "(SELECT LedgerID,Source,Destination,Quantity,Unit FROM Transfers UNION ALL SELECT LedgerID,Source,NULL AS Destination,Quantity,Unit FROM Discards)"
const attribute_events = "(SELECT LedgerID,LocationID,Attribute,Value,Unit FROM EnvironmentAttributes UNION ALL SELECT LedgerID,LocationID,Attribute,Value,Unit FROM ObservedAttributes WHERE IsInherited = 0)"
const lock_events = "(SELECT LedgerID,LocationID,IsLocked FROM Locks UNION ALL SELECT LedgerID,LocationID,IsLocked FROM ObservedLocks)"
const activity_events = "(SELECT LedgerID,LocationID,IsActive FROM Activity UNION ALL SELECT LedgerID,LocationID,IsActive FROM ObservedActivity)"

"""
    find_most_recent_entry(index, location_id, sequence_id)

Like [`find_most_recent_location`](@ref), but return the `(SequenceID, Location)` entry itself, so a
caller can tell what sequence point the found state reflects.
"""
function find_most_recent_entry(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer)
    haskey(index,location_id) || return nothing
    entries = index[location_id]
    idx = searchsortedlast(entries, (sequence_id, nothing); by=first)
    idx == 0 && return nothing
    return entries[idx]
end

# ===================================================================== reconstruct_parent.jl
"""
    reconstruct_parent(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_parent(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's parent for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_parent!`](@ref).
"""
function reconstruct_parent(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    all_locs=Dict{Integer,Location}() # constant defined in reconstruction_utils.jl Columns are location id, sequence id, location
    cache_feet=[]
    for loc_id in location_ids
        n,t=get_location_info(loc_id) 
        loc=t(loc_id,n) 
        prt,cache_foot = fetch_parent_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        #=
        if loc isa CHESSCore.Well || prt isa CHESSCore.Labware
            loc.parent=prt
        elseif prt isa CHESSCore.Location 
            move_into!(prt,loc)
        end
        =#
        loc.parent=prt 
        all_locs[CHESSCore.location_id(loc)]=loc
        push!(cache_feet,cache_foot)


    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    mvts=get_last_movement_as_child(location_ids,foot,sequence_id,time;encumbrances=encumbrances)
    for row in eachrow(mvts) 
        loc_id=row.Child 
        if ismissing(row.Parent)
            move_into!(nothing,all_locs[loc_id])
        else
            n,t=get_location_info(row.Parent)
            prt = t(row.Parent,n)
            move_into!(prt,all_locs[loc_id])
        end 
    end

    return map(x->all_locs[x],location_ids)

end 

function reconstruct_parent(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_parent([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end


"""
    reconstruct_parent!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_parent!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the parent of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_parent`](@ref).
"""
function reconstruct_parent!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_locs=reconstruct_parent(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)

    for i in eachindex(locations)
        locations[i].parent = CHESSCore.parent(parallel_locs[i])
    end 
    return nothing 
end 

function reconstruct_parent!(location::Location,sequence_id=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_parent(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    location.parent=CHESSCore.parent(parallel_loc)
    return nothing 
end




function fetch_parent_cache(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

    caches=get_parent_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    p=nothing
    foot=0
    encumber_offset=0 
    if nrow(caches)>0 

        last=caches[end,:]
        if !ismissing(last.ParentID)

            n,t=get_location_info(last.ParentID)
            p=t(last.ParentID,n)
        else
            foot=last.SequenceID
        end
    else
        return nothing,0
    end
    return p,foot
end 



function get_parent_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,ParentID)
        AS(SELECT e.EncumbranceID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.ParentID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedAncestors v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.ParentID
            FROM CachedAncestors c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID,EncumbranceID, LocationID, ParentID)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.ParentID FROM CachedAncestors c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id Group By SequenceID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
    end
end


function get_last_movement_as_child(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    entry=query_join_vector(locs)
    ledger_time=db_time(time)
    x=""
    if encumbrances 
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
         y (LedgerID,SequenceID,EncumbranceID, Parent,Child)
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.Parent,v.Child
            FROM encumbrance_subset e INNER JOIN EncumberedMovements v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.Parent,c.Child
            FROM $(movement_events) c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
        z( LedgerID, SequenceID,EncumbranceID,Parent,Child) 
        As(SELECT  LedgerID,Max(SequenceID),EncumbranceID, Parent,Child FROM y WHERE  Child in $entry GROUP BY Child  ORDER BY   SequenceID 
        )
        SELECT * FROM z 
        """
    else
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,
             y(LedgerID, SequenceID,EncumbranceID,Parent,Child) 
             AS( 
             SELECT  LedgerID,Max(SequenceID),0,Parent,Child FROM $(movement_events) AS Movements INNER JOIN ledger_subset ON Movements.LedgerID = ledger_subset.ID WHERE  Child in $entry GROUP BY Child   ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 

# ===================================================================== reconstruct_children.jl


"""
    reconstruct_children(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_children(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's children (as bare locations, not themselves reconstructed) for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_children!`](@ref).
"""
function reconstruct_children(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    all_locs=Dict{Integer,Location}() 
    cache_feet=[]
    current_children=Dict{Integer,Integer}() # dict mapping child_id to parent_id
    for loc_id in location_ids
        loc,cache_foot = fetch_child_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        all_locs[loc_id]=loc
        push!(cache_feet,cache_foot)
        for child in children(loc)
            all_locs[location_id(child)]=child
            current_children[location_id(child)]=location_id(loc)
        end
    end 

    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    mvmts=get_child_movements(location_ids,current_children,foot,sequence_id,time;encumbrances=encumbrances)
    for row in eachrow(mvmts) 
        if row.Parent in location_ids 
            if !in(row.Child,keys(all_locs))
                n,t=get_location_info(row.Child)
                all_locs[row.Child]=t(row.Child,n)
            end
            # the cache this started from may already hold the child: a movement or observation on
            # the cache's own ledger entry is already reflected in it
            any(c -> c === all_locs[row.Child],children(all_locs[row.Parent])) && continue
            move_into!(all_locs[row.Parent],all_locs[row.Child])
        elseif (row.Child in keys(current_children)) && row.Parent != current_children[row.Child]
            p_id=location_id(CHESSCore.parent(all_locs[row.Child]))
            remove!(all_locs[p_id],all_locs[row.Child])
        end
    end


    return map(x->all_locs[x],location_ids)

end 


function reconstruct_children(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_children([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end 

"""
    reconstruct_children!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_children!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the children of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_children`](@ref).
"""
function reconstruct_children!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_locs=reconstruct_children(locations,sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)
        if locations[i] isa CHESSCore.Well
            continue 
        else 
            locations[i].children=children(parallel_locs[i])
        end
    end

    return nothing 
end 

function reconstruct_children!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_children(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    if location isa CHESSCore.Well 
        return nothing 
    elseif location isa CHESSCore.Labware 
        for i in eachindex(children(location))
            location.children[i]=children(parallel_loc)[i]
        end

    else 
        location.children = children(parallel_loc)
    end 
    return nothing 
end 




function fetch_child_cache(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    n,t=get_location_info(location_id)

    loc=t(location_id,n)
    foot=0
    caches=get_child_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    if nrow(caches) > 0 
        foot=caches[end,"SequenceID"]
        children_id=caches[end,"ChildSetID"]
        childset=query_db("SELECT * FROM CachedChildren WHERE CachedChildSetID= ?",(children_id,))
        if loc isa CHESSCore.Labware
            for i in 1:nrow(childset)
                child_id=childset[i,"ChildID"]
                row=childset[i,"RowIdx"]
                col=childset[i,"ColIdx"]
                n,t=get_location_info(child_id)
                loc.children[row,col]=t(child_id,n)
            end 
        else # for other locations 
            for i in 1:nrow(childset)
                child_id=childset[i,"ChildID"]
                n,t=get_location_info(child_id)
                move_into!(loc,t(child_id,n))
            end
        end 
    elseif nrow(caches)==0 && loc isa CHESSCore.Labware
        error("No child cache found for this labware . Labware must have a valid child cache for reconstructon. Either make a cache or change the query parameters. \\ QUERY PARAMETERS \\ Sequence ID: $starting -- $ending \\ Time: $time. ") 
    end 
    return loc,foot
end 



function get_child_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID, LedgerID,SequenceID,EncumbranceID,LocationID,ChildSetID)
        AS(SELECT e.EncumbranceID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.ChildSetID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedDescendants v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.ChildSetID
            FROM CachedDescendants c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID,EncumbranceID, LocationID, ChildSetID)
        AS( SELECT c.ID,c.LedgerID,l.SequenceID,0, c.LocationID,c.ChildSetID FROM CachedDescendants c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id Group By SequenceID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
    end
end





function get_last_movements_as_parent(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)  # find all movements for a set of locations betweeen `starting` and `ending` ledger ids
    entry=query_join_vector(locs)
    ledger_time = db_time(time)
    x=""
    if encumbrances 
        x=
        """
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
                 y (LedgerID,SequenceID,EncumbranceID, Parent,Child)
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.Parent,v.Child
            FROM encumbrance_subset e INNER JOIN EncumberedMovements v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.Parent,c.Child
            FROM $(movement_events) c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
        z( LedgerID, SequenceID,EncumbranceID,Parent,Child) 
        As(SELECT  LedgerID,Max(SequenceID),EncumbranceID, Parent,Child FROM y  GROUP BY Child  ORDER BY   SequenceID 
        )
        SELECT * FROM z WHERE Parent in $entry 
        """
    else
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,
             y(LedgerID, SequenceID,EncumbranceID,Parent,Child) 
             AS( 
             SELECT  LedgerID,Max(SequenceID),0,Parent,Child FROM $(movement_events) AS Movements INNER JOIN ledger_subset ON Movements.LedgerID = ledger_subset.ID GROUP BY Child   ORDER BY SequenceID 
             )
        Select * FROM y WHERE Parent in $entry
        """
    end
    return query_db(x)
end

function get_child_movements(locs::Vector{<:Integer},current_children::Dict{Integer,Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    ledger_time= db_time(time)
    loc_plus_children=unique(vcat(locs,collect(keys(current_children))))
    a=get_last_movement_as_child(collect(keys(current_children)),starting,ending,time;encumbrances=encumbrances)
    b=get_last_movements_as_parent(locs,starting,ending,time;encumbrances=encumbrances)

    
    final_movements=vcat(a,b)
    sort!(final_movements,:SequenceID)
    
    return final_movements
end
# ===================================================================== reconstruct_attributes.jl



"""
    reconstruct_attributes(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_attributes(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's own attributes for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_attributes!`](@ref).
"""
function reconstruct_attributes(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
        all_locs=Dict{Integer,Location}() # constant defined in reconstruction_utils.jl Columns are location id, sequence id, location
        cache_feet=[]
        for loc_id in location_ids
 
            loc,cache_foot = fetch_attribute_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)

            all_locs[CHESSCore.location_id(loc)]=loc
            push!(cache_feet,cache_foot)
        end 
    
        foot=0
        if length(cache_feet)>0 
            foot = min(minimum(cache_feet),sequence_id)
        end
        attrs=get_environment_attributes(location_ids,foot,sequence_id,time;encumbrances=encumbrances)
        for row in eachrow(attrs) 
            loc_id=row.LocationID 
            attr=get_attribute(row.Attribute)
            val=row.Value
            un=row.Unit
            set_attribute!(all_locs[loc_id],attr(val*_parse_unit(un)))
        end
    
        return map(x->all_locs[x],location_ids)
    
end 

function reconstruct_attributes(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_attributes([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end 


"""
    reconstruct_attributes!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_attributes!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the own attributes of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_attributes`](@ref).
"""
function reconstruct_attributes!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    parallel_locs=reconstruct_attributes(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)
        locations[i].attributes = CHESSCore.attributes(parallel_locs[i])
    end 
    return nothing 
end 

function reconstruct_attributes!(location::Location ,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_attributes(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    location.attributes=CHESSCore.attributes(parallel_loc)
    return nothing 
end 


function get_attribute(attr::String)
    return attribute_kinds[Symbol(attr)]
end

function fetch_attribute_cache(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
        caches=get_attribute_caches(location_id,starting,ending,time;encumbrances=encumbrances)
        n,t=get_location_info(location_id)

        loc=t(location_id,n)
        foot=0
        if nrow(caches)>0 
    
            last=caches[end,:]
            attr_id=last["AttributeSetID"]
            attr_set=query_db("SELECT * FROM CachedAttributes WHERE AttributeSetID = ?",(attr_id,))
            foot=last["SequenceID"]
            for i in 1:nrow(attr_set)
                attr=get_attribute(attr_set[i,"AttributeID"])
                val=attr_set[i,"Value"]
                un=attr_set[i,"Unit"]
                set_attribute!(loc,attr(val*_parse_unit(un)))
            end 
        end 

        return loc, foot

end 




function get_attribute_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

        ledger_time=db_time(time)
        if encumbrances
            return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
            AS(
                SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
                ),
    
                        encumbrance_subset (EncumbranceID)
            AS(SELECT e.ID
                FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1
    
            ),
            
                y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,AttributeSetID)
            AS(SELECT e.EncumbranceID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.AttributeSetID
                FROM encumbrance_subset e INNER JOIN EncumberedCachedEnvironments v ON e.EncumbranceID = v.EncumbranceID 
            UNION ALL 
                SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.AttributeSetID
                FROM CachedEnvironments c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id Group By l.SequenceID) 
                SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
        else
            return query_db("
                WITH ledger_subset (ID,SequenceID,Time)
            AS(
                SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
                ) ,
            y (ID,LedgerID,SequenceID,EncumbranceID, LocationID, AttributeSetID)
            AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.AttributeSetID FROM CachedEnvironments c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id Group By SequenceID ORDER BY SequenceID ) 
            SELECT * from y
            " )
            
        end
end






function get_environment_attributes(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(), time::DateTime=Dates.now();encumbrances=false)
    ledger_time= db_time(time)
    entry=query_join_vector(locs)
    x=""
    if encumbrances 
        x=
        """
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
        y (LedgerID,SequenceID, EncumbranceID, LocationID,Attribute,Value,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.Attribute,v.Value,v.Unit
            FROM encumbrance_subset  e INNER JOIN EncumberedEnvironments v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0,c.LocationID,c.Attribute,c.Value,c.Unit
            FROM $(attribute_events) c INNER JOIN ledger_subset l on l.ID = c.LedgerID) ,
        
        z (LedgerID,SequenceID,EncumbranceID,LocationID,Attribute,Value,Unit)
        AS(Select LedgerID, Max(SequenceID),EncumbranceID,LocationID,Attribute,Value,Unit FROM y WHERE  LocationID in $entry  GROUP BY LocationID, Attribute ORDER BY SequenceID)
            


        SELECT * FROM z
        """
    else
        x=
        """
                    WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (LedgerID,SequenceID,EncumbranceID, LocationID, Attribute, Value,Unit)
        AS( SELECT c.LedgerID,l.SequenceID,0, c.LocationID,c.Attribute,c.Value,c.Unit FROM $(attribute_events) c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,

                z (LedgerID,SequenceID,EncumbranceID,LocationID,Attribute,Value,Unit)
        AS(Select LedgerID, Max(SequenceID),EncumbranceID,LocationID,Attribute,Value,Unit FROM y WHERE  LocationID in $entry  GROUP BY LocationID, Attribute ORDER BY SequenceID)
            


        SELECT * FROM z
        """
    end
    return query_db(x)
end 
# ===================================================================== reconstruct_environment.jl
"""
    reconstruct_environment(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_environment(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's chain of ancestors and their attributes, so that `environment` gives the inherited environment for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_environment!`](@ref).
"""
function reconstruct_environment(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    
    all_locs=Dict{Integer,Location}()
    parent_set=location_ids


    while length(parent_set) > 0 
        new_locs=reconstruct_parent(parent_set,sequence_id,time,max_cache;encumbrances=encumbrances)
        for loc in new_locs 
            all_locs[CHESSCore.location_id(loc)]=loc
        end 
        parent_set=Int.(unique(filter(x->!isnothing(x),map(x->CHESSCore.location_id(CHESSCore.parent(x)),new_locs))))
    end 

    all_keys=collect(keys(all_locs))
    all_vals=collect(values(all_locs))

    reconstruct_attributes!(all_vals,sequence_id,time,max_cache;encumbrances=encumbrances)

    all_locs=Dict(all_keys .=> all_vals) 

    for key in collect(all_keys) 
        prt_id = CHESSCore.location_id(CHESSCore.parent(all_locs[key]))
        if isnothing(prt_id)
            all_locs[key].parent=nothing 
        else 

            all_locs[key].parent = all_locs[prt_id]
        end 
    end 

    return map(x->all_locs[x],location_ids)
end 

function reconstruct_environment(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_environment([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end 



"""
    reconstruct_environment!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_environment!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the parent chain and attributes of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_environment`](@ref).
"""
function reconstruct_environment!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    parallel_locs=reconstruct_environment(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)
        locations[i].parent= CHESSCore.parent(parallel_locs[i])
        locations[i].attributes=CHESSCore.attributes(parallel_locs[i])
    end
     return nothing 
end 

function reconstruct_environment!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_environment(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    location.parent=CHESSCore.parent(parallel_loc)
    location.attributes=CHESSCore.attributes(parallel_loc)
    return nothing 
end 


    


# ===================================================================== reconstruct_contents.jl


"""
    _reconstruction_transfer(donor,recipient,quantity,configuration::String="")

Internal, non-exported helper used only by the ledger-replay simulation below. Returns new
`(donor,recipient)` objects reflecting a transfer of `quantity`, without mutating the originals — the
replay needs to keep both the pre- and post-transfer versions of each well in its own history log
(`all_locs`), so it can't just mutate in place like [`transfer!`](@ref) does.

This is `deepcopy`-based like the old public non-mutating `transfer` (removed — see
[`reconstruct_location`](@ref)/[`build_location`](@ref) for the actual preview pattern), but it's safe
here specifically because `src`/`dest` in this context are always standalone reconstruction shells
(`parent === nothing`, no children) built directly by `t(loc_id,n)` a few lines up — never part of a
live connected tree — so `deepcopy` has nothing extra to copy.
"""
function _reconstruction_transfer(donor,recipient,quantity,configuration::String="")
    d=deepcopy(donor)
    r=deepcopy(recipient)
    transfer!(d,r,quantity,configuration)
    return d,r
end

function get_content_caches(location_id::Integer, starting::Integer=0, ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,StockID)
        AS(SELECT e.EncumbranceID,0,0,e.EncumbranceID,v.LocationID, v.StockID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedContents v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0,c.LocationID,c.StockID
            FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id AND c.Time <= $ledger_time Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID, EncumbranceID,LocationID,StockID)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.StockID FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id AND c.Time <= $ledger_time Group By LedgerID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
end
end

# good luck to whoever tries to figure this out. Ben probably won't remember enough to be helpful. 
# leger_subset grabs all of the ledger entries that reflect the parameters of the query: when to start and finish and at what time we are reconstructing the transfers
# encumbrance_subset grabs all of the encumbrances that were active during the time of ledger_subset 
# y grabs all of the regular and encumbered transfers using ledger_subset and encumbrance_subset respectively 
# x does a recursive search to grab all of the transfers from y that play a role in reconstrucint locs 

"""
    get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

Find every transfer relevant to reconstructing `locs`' contents between `starting` and `ending`
sequence points.

The result has a `Core` column (`1`/`0`). `Core=1` rows are the genuine ancestor closure: `locs`
themselves plus every location transitively feeding them (found the traditional way, recursively
following `Source = <already-found Source>.Destination`). `Core=0` ("collateral") rows are *other*
outgoing transfers of a `Core=1` location, to a destination that never itself feeds back into the
closure -- needed so replay can correctly account for stock a core location sent away to something
`reconstruct_contents` doesn't otherwise care about (see the module docs above `x`'s definition for
why this ever mattered). Collateral destinations never need their own correct reconstruction --
`reconstruct_contents` bootstraps them as bare `Empty()` stubs instead of recursing, which is what
keeps a busy/shared well's reconstruction from pulling in a large, mostly-irrelevant slice of the
whole ledger's history: the *query* still has to look at every collateral edge (that's inherent to
correctly zeroing out a core well's balance), but no collateral destination ever triggers its own
expensive reconstruction.
"""
function get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)  # find all transfers for a set of locations betweeen `starting` and `ending` ledger ids
    ledger_time= db_time(time)
    entry=query_join_vector(locs)
    x=""
    if encumbrances
        x=
        """
                    WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),

         y (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+c.EncumbranceID, c.EncumbranceID, c.Source,c.Destination,c.Quantity,c.Unit
            FROM encumbrance_subset e INNER JOIN EncumberedTransfers c ON e.EncumbranceID = c.EncumbranceID
        UNION ALL
            SELECT t.LedgerID,l.SequenceID,0,t.Source, t.Destination, t.Quantity, t.Unit
            FROM $(transfer_events) t INNER JOIN ledger_subset l ON t.LedgerID = l.ID ) ,
        x (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
         SELECT y.LedgerID,y.SequenceID,y.EncumbranceID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y  ,x
            WHERE x.Source = y.Destination
        ),
        ancestor_wells (LocationID) AS (
            SELECT Source FROM x UNION SELECT Destination FROM x
        ),
        full_set (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit,Core) AS (
            SELECT *, 1 FROM x
            UNION
            SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit, 0
                FROM y INNER JOIN ancestor_wells ON y.Source = ancestor_wells.LocationID
                WHERE NOT EXISTS (SELECT 1 FROM x WHERE x.LedgerID = y.LedgerID AND x.EncumbranceID = y.EncumbranceID)
        )
        SELECT DISTINCT * FROM full_set ORDER BY SequenceID
        """
    else
        x=
        """
            WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

         -- restrict to transfers inside the requested window before walking ancestors, as the
         -- encumbrance branch does: a transfer after `ending` must not pull its source into the
         -- closure, or that source's earlier outgoing transfers come back as collateral rows
         -- for a well that was never bootstrapped.
         y (LedgerID,Source,Destination,Quantity,Unit)
        AS(SELECT t.LedgerID,t.Source,t.Destination,t.Quantity,t.Unit
            FROM $(transfer_events) t INNER JOIN ledger_subset l ON t.LedgerID = l.ID),

         x (LedgerID,Source,Destination,Quantity,Unit)
        AS(
        SELECT y.LedgerID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT y.LedgerID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y ,x
            WHERE x.Source = y.Destination
        ),
        ancestor_wells (LocationID) AS (
            SELECT Source FROM x UNION SELECT Destination FROM x
        ),
        full_set (LedgerID,Source,Destination,Quantity,Unit,Core) AS (
            SELECT *, 1 FROM x
            UNION
            SELECT y.LedgerID, Source, Destination, y.Quantity, y.Unit, 0
                FROM y INNER JOIN ancestor_wells ON y.Source = ancestor_wells.LocationID
                WHERE NOT EXISTS (SELECT 1 FROM x WHERE x.LedgerID = y.LedgerID)
        )
        SELECT full_set.LedgerID,Source,Destination,Quantity,Unit,Max(Core) AS Core,ledger_subset.SequenceID
            FROM full_set INNER JOIN ledger_subset ON full_set.LedgerID = ledger_subset.ID
            GROUP BY full_set.LedgerID ORDER BY ledger_subset.SequenceID
        """

    end
return query_db(x)
end

function get_transfer_descendents(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)  # find all transfers stemming from a set of locations betweeen `starting` and `ending` ledger ids
    ledger_time= db_time(time)
    entry=query_join_vector(locs)
    x=""
    if encumbrances 
        x= 
        """
                    WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),

         y (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+c.EncumbranceID, c.EncumbranceID, c.Source,c.Destination,c.Quantity,c.Unit
            FROM encumbrance_subset e INNER JOIN EncumberedTransfers c ON e.EncumbranceID = c.EncumbranceID
        UNION ALL 
            SELECT t.LedgerID,l.SequenceID,0,t.Source, t.Destination, t.Quantity, t.Unit
            FROM Transfers t INNER JOIN ledger_subset l ON t.LedgerID = l.ID ) ,
        x (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
         SELECT y.LedgerID,y.SequenceID,y.EncumbranceID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y  ,x
            WHERE y.Source = x.Destination
        )
        SELECT DISTINCT  * FROM x ORDER BY SequenceID
        """
    else
        x=
        """
            WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

         x (LedgerID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
        SELECT Transfers.LedgerID,0, Source,Destination,Transfers.Quantity,Transfers.Unit
            FROM Transfers
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT t.LedgerID,0,t.Source,t.Destination,t.Quantity,t.Unit
            FROM Transfers t  ,x
            WHERE t.Source = x.Destination
        )
        SELECT DISTINCT  * FROM x INNER JOIN ledger_subset ON x.LedgerID = ledger_subset.ID  ORDER BY SequenceID
        """

    end 
return query_db(x)
end 

function transfers_touch(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_descendents([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    for row in eachrow(out)
        ismissing(row.Destination) && continue # a discard reaches no other well
        push!(out_set,(row.Destination,row.LedgerID,row.EncumbranceID))
    end
    return out_set
end 

function transfers_touched_by(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_ancestors([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    for row in eachrow(out)
        ismissing(row.Destination) && continue # a discard reaches no other well
        push!(out_set,(row.Destination,row.LedgerID,row.EncumbranceID))
    end
    return out_set
end 




"""
    fetch_content_cache(location_id::Integer,starting::Integer,ending::Integer,time::DateTime=Dates.now();encumbrances=false)

Look up `location_id`'s most recent cached [`Stock`](@ref) within `starting..ending`. Returns
`(stock, foot)`.

`stock` is `nothing` when no `CachedContents` row exists in that window at all -- distinct from a
row that exists and legitimately caches an empty stock (which returns `Empty()`, not `nothing`).
Callers (see [`reconstruct_contents`](@ref)) rely on this distinction: `nothing` means "we don't
actually know this location's content here, go reconstruct it," while `Empty()` means "confirmed
empty as of this cache point."
"""
function fetch_content_cache(location_id::Integer,starting::Integer,ending::Integer,time::DateTime=Dates.now();encumbrances=false)
    caches=get_content_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    nrow(caches) == 0 && return nothing, 0

    row=caches[end,:]
    stock_id=row.StockID
    foot=row.SequenceID

    stock=Empty()
    if !ismissing(stock_id)
        stock=get_stock(stock_id)
    end

    return stock, foot
end

"""
    reconstruct_contents(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild the stock of wells from the ledger's transfer history, returning new locations for
the given IDs. [`reconstruct_contents!`](@ref) writes the result into existing
[`Location`](@ref)s instead. IDs that are not [`Well`](@ref)s come back as bare locations with no contents.

A well's contents can depend on every well that ever transferred into it, so reconstruction starts
from the most recent cached stock of each well and replays only the transfers since then. Passing
several wells at once shares that work.

The optional arguments work as in [`reconstruct_location!`](@ref): `sequence_id` and `time` choose the
point in history, `max_cache` limits which caches may be used, and `encumbrances=true` includes
planned future operations.
"""
function reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(), max_cache::Integer=sequence_id, loc_index::Dict{<:Integer,<:Vector} = location_reconstruction_index;encumbrances=false)
    all_locs=deepcopy(loc_index)
    cache_feet=[]
    for loc_id in location_ids
        n,t=get_location_info(loc_id)
        loc=t(loc_id,n)
        if !(loc isa CHESSCore.Well)
            push_location!(all_locs,loc_id,0,loc)
            continue
        end
        stock,cache_foot = fetch_content_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        if !isnothing(stock)
            deposit!(loc,stock)
        end

        push_location!(all_locs,CHESSCore.location_id(loc),cache_foot,loc)
        push!(cache_feet,cache_foot)


    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    transfers=get_transfer_ancestors(location_ids,foot+1,sequence_id,time;encumbrances=encumbrances)



    # locations that are part of the genuine ancestor closure (Core=1 in some row) need a real,
    # possibly-recursive bootstrap below. Locations that only appear because a core location's
    # *other* outgoing transfer happened to land on them ("collateral", Core=0 everywhere they
    # appear) never get read back out of this call -- see get_transfer_ancestors's docstring --
    # so they're built as bare Empty() stubs instead, without ever touching the cache tables or
    # recursing. This is what keeps a busy/shared well's reconstruction from cascading into a large,
    # mostly-irrelevant slice of the ledger just because get_transfer_ancestors had to look at it.
    core_locs=Set{Integer}()
    if nrow(transfers) > 0 && hasproperty(transfers,:Core)
        for row in eachrow(transfers)
            if row.Core == 1
                push!(core_locs,row.Source)
                ismissing(row.Destination) || push!(core_locs,row.Destination)
            end
        end
    end

    # component observations on every well whose own state this call reads back: the
    # requested wells plus the core ancestor closure. Collateral destinations never need them.
    target_wells=filter(id -> find_most_recent_location(all_locs,id) isa CHESSCore.Well,location_ids)
    observations=get_content_observations(collect(union(core_locs,target_wells)),foot+1,sequence_id,time)

    # grab the sequence id of each location we need to complete this set of transfers
    cache_dict=Dict{Integer,Integer}()
    for row in reverse(eachrow(transfers))

        seq_id=min(row.SequenceID-1,sequence_id)
        # set it back to the sequence id we are looking at if the transfer is encumbered


        cache_dict[row.Source]=seq_id
        ismissing(row.Destination) || (cache_dict[row.Destination]=seq_id)
    end
    # a core well must also be bootstrapped from before its first observation
    for row in eachrow(observations)
        row.LocationID in core_locs || continue
        seq_id=min(row.SequenceID-1,sequence_id)
        cache_dict[row.LocationID]=min(get(cache_dict,row.LocationID,seq_id),seq_id)
    end
    reconstructions_needed=Set{Integer}()
    for loc_id in keys(cache_dict)

        if !(loc_id in core_locs)
            n,t=get_location_info(loc_id)
            push_location!(all_locs,loc_id,foot,t(loc_id,n))
            continue
        end

        new_stock,new_foot=fetch_content_cache(loc_id,foot,cache_dict[loc_id],time;encumbrances=false)
        n,t=get_location_info(loc_id)
        new_loc=t(loc_id,n)
        if !isnothing(new_stock)
            deposit!(new_loc,new_stock)
            push_location!(all_locs,loc_id,new_foot,new_loc)
        else
            push!(reconstructions_needed,loc_id)
        end
    end
    if length(reconstructions_needed) > 0
        locs=reconstruct_contents(collect(reconstructions_needed),foot,time,max_cache,all_locs)
        for loc in locs
            push_location!(all_locs,CHESSCore.location_id(loc),foot,loc)
        end
    end

    #start simulation: transfers and observations in sequence order. An observation never shares a
    # SequenceID with a transfer (each is its own ledger entry), so the relative order of equal keys
    # doesn't matter.
    events=vcat([(row.SequenceID,row) for row in eachrow(transfers)],
                [(key.SequenceID,rows) for (key,rows) in pairs(groupby(observations,[:LocationID,:SequenceID];sort=false))])
    sort!(events;by=first)

    for (_,row) in events
        if !(row isa DataFrameRow)
            _apply_content_observations!(all_locs,row)
            continue
        end
        seq_id=row.SequenceID -1
        quant= row.Quantity * _parse_unit(row.Unit)
        src = find_most_recent_location(all_locs,row.Source,seq_id)

        if row.Core == 0 || ismissing(row.Destination) # a discard has no destination to track
            # Collateral: this row exists only so a *core* location's balance is correctly reduced
            # by whatever it sent elsewhere -- the destination itself is never read back out of this
            # call (see get_transfer_ancestors's docstring), so there's no need to find, deepcopy, or
            # track it at all. Just withdraw from a copy of the source and discard the rest.
            new_src = deepcopy(src)
            withdraw!(new_src,quant)
            push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
            continue
        end

        dest = find_most_recent_location(all_locs,row.Destination,seq_id)
        new_src,new_dest=_reconstruction_transfer(src,dest,quant)
        push_location!(all_locs,CHESSCore.location_id(dest),seq_id+1,new_dest)
        push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
    end

    final_out = find_most_recent_location.((all_locs,), location_ids)


    return final_out
end 

function reconstruct_contents(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)
    return reconstruct_contents([location_id],sequence_id,time,max_cache,loc_index;encumbrances=encumbrances)[1]
end

"""
    reconstruct_contents!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_contents!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the stock of each [`Well`](@ref) in `locations` to its reconstructed state. Other
locations are left alone. Arguments work as in [`reconstruct_contents`](@ref).
"""
function reconstruct_contents!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)


    parallel_locs=reconstruct_contents(location_id.(locations),sequence_id,time,max_cache,loc_index,encumbrances=encumbrances)

    for i in eachindex(locations)
        if locations[i] isa CHESSCore.Well
            locations[i].stock=CHESSCore.stock(parallel_locs[i])
        else
            continue 
        end 
    end 
    return nothing
end 

function reconstruct_contents!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)
    parallel_loc=reconstruct_contents(location_id(location),sequence_id,time,max_cache,loc_index,encumbrances=encumbrances)
    if location isa CHESSCore.Well
        location.stock=CHESSCore.stock(parallel_loc)
    end 
    return nothing 
end 

    


        








"""
    get_content_observations(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Every component observation on `locs` between `starting` and `ending` sequence points,
ordered by `SequenceID`.
"""
function get_content_observations(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    isempty(locs) && return DataFrame(LedgerID=Int[],SequenceID=Int[],LocationID=Int[],ComponentID=Union{Int,Missing}[],
        Quantity=Union{Float64,Missing}[],Unit=Union{String,Missing}[])
    ledger_time=db_time(time)
    entry=query_join_vector(locs)
    return query_db("""
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            )
        SELECT o.LedgerID,l.SequenceID,o.LocationID,o.ComponentID,o.Quantity,o.Unit
            FROM ObservedComponents o INNER JOIN ledger_subset l ON o.LedgerID = l.ID WHERE o.LocationID IN $entry
        ORDER BY SequenceID
        """)
end

"""
    _apply_content_observations!(all_locs, rows)

Replay one location's observations at one sequence point (`rows` share a `LocationID` and
`SequenceID`) on top of its most recent reconstructed state, and record the result at that sequence
point. Skipped when that location's state is only known from a point at or after the observation --
a cache written there already reflects it.
"""
function _apply_content_observations!(all_locs,rows)
    loc_id=rows[1,:LocationID]
    seq_id=rows[1,:SequenceID]
    entry=find_most_recent_entry(all_locs,loc_id,seq_id-1)
    isnothing(entry) && return nothing
    loc=deepcopy(entry[2])
    for row in eachrow(rows)
        quant=row.Quantity*_parse_unit(row.Unit)
        loc.stock=set_component(CHESSCore.stock(loc),get_component(row.ComponentID),quant)
    end
    push_location!(all_locs,loc_id,seq_id,loc)
    return nothing
end

# ===================================================================== reconstruct_lock.jl


"""
    reconstruct_lock(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_lock(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's locked state for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_lock!`](@ref).
"""
function reconstruct_lock(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    all_locs=Dict{Integer,Location}() # constant defined in reconstruction_utils.jl Columns are location id, sequence id, location
    cache_feet=[]
    for loc_id in location_ids
        loc,cache_foot = fetch_lock_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        all_locs[CHESSCore.location_id(loc)]=loc
        push!(cache_feet,cache_foot)
    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    locks=get_locks(location_ids,foot,sequence_id,time;encumbrances=encumbrances)
    for row in eachrow(locks) 
        loc_id=row.LocationID 
        locked=Bool(row.IsLocked)
        if locked 
            lock!(all_locs[loc_id])
        else
            unlock!(all_locs[loc_id])
        end 
    end

    return map(x->all_locs[x],location_ids)


end 

function reconstruct_lock(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_lock([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end


"""
    reconstruct_lock!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_lock!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the locked state of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_lock`](@ref).
"""
function reconstruct_lock!(locations::Vector{Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    parallel_locs=reconstruct_lock(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)

        if locations[i] isa CHESSCore.Well
            continue 
        else 
            locations[i].is_locked = is_locked(parallel_locs[i])
        end 
    end 
    return nothing 
end 

function reconstruct_lock!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_lock(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    if location isa CHESSCore.Well
         
    else 
        location.is_locked = is_locked(parallel_loc)
    end 
    return nothing 
end 





function fetch_lock_cache(location_id::Integer,starting::Integer,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)
    n,t=get_location_info(location_id)
    loc=t(location_id,n)
    caches=get_lock_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    foot=0
    if nrow(caches)>0 
        last=caches[end,:]
        locked=Bool(last.IsLocked)
        foot=last.SequenceID
        if locked
            lock!(loc)
        else
            unlock!(loc)
        end
    end
    return loc,foot
end 



function get_lock_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)

    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,IsLocked)
        AS(SELECT e.EncumbranceID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.IsLocked
            FROM encumbrance_subset e INNER JOIN EncumberedCachedLockActivity v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsLocked
            FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID,EncumbranceID, LocationID, IsLocked)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsLocked FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id Group By SequenceID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
    end
end 


function get_locks(location_ids::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

    entry=query_join_vector(location_ids)
    ledger_time=db_time(time)
    x=""
    if encumbrances 
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
         y (LedgerID,SequenceID,EncumbranceID, LocationID,IsLocked)
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.LocationID,v.Lock
            FROM encumbrance_subset e INNER JOIN EncumberedLocks v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.LocationID,c.IsLocked
            FROM $(lock_events) c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
        z( LedgerID, SequenceID,EncumbranceID,LocationID,IsLocked) 
        As(SELECT  LedgerID,Max(SequenceID),EncumbranceID, LocationID,IsLocked FROM y WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY   SequenceID 
        )
        SELECT * FROM z 
        """
    else
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,
             y(LedgerID, SequenceID,EncumbranceID,LocationID,IsLocked) 
             AS( 
             SELECT  LedgerID,Max(SequenceID),0,LocationID,IsLocked FROM $(lock_events) AS Locks INNER JOIN ledger_subset ON Locks.LedgerID = ledger_subset.ID WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 




# ===================================================================== reconstruct_activity.jl


"""
    reconstruct_activity(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_activity(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's active state for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_activity!`](@ref).
"""
function reconstruct_activity(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    all_locs=Dict{Integer,Location}() # constant defined in reconstruction_utils.jl Columns are location id, sequence id, location
    cache_feet=[]
    for loc_id in location_ids
        loc,cache_foot = fetch_activity_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        all_locs[CHESSCore.location_id(loc)]=loc
        push!(cache_feet,cache_foot)
    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    activities=get_activity(location_ids,foot,sequence_id,time;encumbrances=encumbrances)
    for row in eachrow(activities) 
        loc_id=row.LocationID 
        active=Bool(row.IsActive)
        if active
            activate!(all_locs[loc_id])
        else
            deactivate!(all_locs[loc_id])
        end 
    end



    return map(x->all_locs[x],location_ids)


end 

function reconstruct_activity(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_activity([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end


"""
    reconstruct_activity!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_activity!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the active state of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_activity`](@ref).
"""
function reconstruct_activity!(locations::Vector{Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    parallel_locs=reconstruct_activity(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)
            locations[i].is_active= is_active(parallel_locs[i])
    end 
    return nothing 
end 

function reconstruct_activity!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_activity(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    location.is_active= is_active(parallel_loc) 
    return nothing 
end 





function fetch_activity_cache(location_id::Integer,starting::Integer,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)
    n,t=get_location_info(location_id)
    loc=t(location_id,n)
    caches=get_activity_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    foot=0
    if nrow(caches)>0 
        last=caches[end,:]
        active=Bool(last.IsActive)
        foot=last.SequenceID
        if active
            activate!(loc)
        else
            deactivate!(loc)
        end
    end
    return loc,foot
end 



function get_activity_caches(location_id::Integer,starting::Integer=0,ending::Integer=get_last_sequence_id(),time=Dates.now();encumbrances=false)

    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,IsActive)
        AS(SELECT e.EncumbranceID, 0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.IsActive
            FROM encumbrance_subset e INNER JOIN EncumberedCachedLockActivity v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsActive
            FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID, LedgerID,SequenceID,EncumbranceID, LocationID, IsActive)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsActive FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id Group By SequenceID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
    end
end 


function get_activity(location_ids::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

    entry=query_join_vector(location_ids)
    ledger_time=db_time(time)
    x=""
    if encumbrances 
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
         y (LedgerID,SequenceID,EncumbranceID, LocationID,IsActive)
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.LocationID,v.Activate
            FROM encumbrance_subset e INNER JOIN EncumberedActivity v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.LocationID,c.IsActive
            FROM $(activity_events) c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
        z( LedgerID, SequenceID,EncumbranceID,LocationID,IsActive) 
        As(SELECT  LedgerID,Max(SequenceID),EncumbranceID, LocationID,IsActive FROM y WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY   SequenceID 
        )
        SELECT * FROM z 
        """
    else
        x=
        """
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,
             y(LedgerID, SequenceID,EncumbranceID,LocationID,IsActive) 
             AS( 
             SELECT  LedgerID,Max(SequenceID),0,LocationID,IsActive FROM $(activity_events) AS Activity INNER JOIN ledger_subset ON Activity.LedgerID = ledger_subset.ID WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 




# ===================================================================== reconstruct_reads.jl

"""
    get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Return every `Reads` row for `location_id` up to `sequence_id`/`time`, as a `DataFrame`. Unlike
`get_*_caches` (e.g. `get_attribute_caches`), there is no latest-wins collapsing here -- reads
never supersede each other, only accumulate (see [`Read`](@ref)'s docstring).
"""
function get_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_time=db_time(time)
    return query_db("""
        SELECT r.* FROM Reads r INNER JOIN Ledger l ON r.LedgerID = l.ID
        WHERE l.SequenceID BETWEEN 0 AND ? AND l.Time <= ? AND r.LocationID = ?
        """,(sequence_id,ledger_time,location_id))
end

_reads_sort_key(row) = something(row.InstrumentTime,row.Time)

"""
    reconstruct_reads!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Populate `loc`'s [`reads`](@ref) collection from the database, up to `sequence_id`/`time`, sorted by
`InstrumentTime` (falling back to the upload `Time` when `InstrumentTime` is unavailable) -- the sort
is what makes `reads(loc)` interpretable as a time series. `max_cache`/`encumbrances` are accepted (and
ignored) purely so [`reconstruct_location!`](@ref) can call every `reconstruct_*!` uniformly -- reads
have no cache/encumbrance layer (see [`get_reads`](@ref)).
"""
function reconstruct_reads!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    rows=get_reads(CHESSCore.location_id(loc),sequence_id,time)
    for row in sort(collect(eachrow(rows));by=_reads_sort_key)
        rk=read_kinds[Symbol(row.Type)]
        val = ismissing(row.Value) ? missing :
              ismissing(row.Unit)  ? row.Value :
              parse(Float64,row.Value)*_parse_unit(row.Unit)
        rd_time = ismissing(row.InstrumentTime) ? nothing : julia_time(row.InstrumentTime)
        record_read!(loc,rk(val,rd_time))
    end
    return nothing
end

"""
    reconstruct_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Reconstruct a location by `location_id` and populate its [`reads`](@ref). See [`reconstruct_reads!`](@ref).
"""
function reconstruct_reads(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    n,t=get_location_info(location_id)
    loc=t(location_id,n)
    reconstruct_reads!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
    return loc
end

# ===================================================================== reconstruct_location.jl



"""
    reconstruct_location!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Reconstruct the entire state of a [`Location`](@ref) `location` in a CHESS Database. 

# Optional Arguments 
1) `sequence_id`: set the reconstruction to happen at a particular sequence point in the ledger. Default is the current maximum sequence ID in the Database. 
2) `time`: only consider operations that were recorded in the CHESS ledger before  `time`. `time` uses [Dates.jl](https://docs.julialang.org/en/v1/stdlib/Dates/) to standardize the time formatting. Default is Dates.now()
3) `max_cache`: only consider caches up to a certain sequence point and force the algorithm to simulate thereafter. Default is the current value of `sequence_id`. This feature is used for cache repair. 
# Keyword Arguments
1) `encumbrances`=false: Include encumbrances in the reconstruction. Encumbrances are future operations that are not in the ledger but have been planned.

Note: Combining these optional arguments allows users to traverse the state of any location at any time, past or present. Encumbrances are enforced as they would have been at the `sequence_id` and `time` of the reconstruction.

See Also: [`reconstruct_location`](@ref)
"""
function reconstruct_location!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    reconstruct_environment!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs full parent chain and environmental attributes. We don't need to call reconstruct_parent  and reconstruct_attribute seperately if doing a full environment reconstruction
    reconstruct_children!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # finds the current children of the location but doesn't fully reconstruct them, just creates a reference. 
    reconstruct_contents!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the stock of wells
    reconstruct_lock!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the locked state (recall locks prevent movement)
    reconstruct_activity!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the activity state
    reconstruct_reads!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the reads recorded for the location
    reconstruct_lot!(loc,sequence_id,time) # reconstructs the lot a labware was received as
    return nothing
end






"""
    reconstruct_location(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

Reconstruct the entire state of location in a CHESS Database using only an integer location_id

# Optional Arguments
1) `sequence_id`: set the reconstruction to happen at a particular sequence point in the ledger. Default is the current maximum sequence ID in the Database. 
2) `time`: only consider operations that were recorded in the CHESS ledger before  `time`. `time` uses [Dates.jl](https://docs.julialang.org/en/v1/stdlib/Dates/) to standardize the time formatting. Default is Dates.now()
3) `max_cache`: only consider caches up to a certain sequence point and force the algorithm to simulate thereafter. Default is the current value of `sequence_id`. This feature is used for cache repair. 
# Keyword Arguments
1) `encumbrances`=false: Include encumbrances in the reconstruction. Encumbrances are future operations that are not in the ledger but have been planned.

Note: Combining these optional arguments allows users to traverse the state of any location at any time, past or present. Encumbrances are enforced as they would have been at the sequence_id and time of the reconstruction.

**Previewing hypothetical changes**: `reconstruct_location` builds a *fresh, independent* object graph
from the ledger on every call — mutating the result (e.g. with `move_into!`, `drain!`, `lock!`, ...)
never touches any other object, live or otherwise, since nothing else shares its identity. This makes
it the way to preview a hypothetical change to a real, already-persisted location: reconstruct a
disposable copy, mutate it however you like, inspect it, then just let it go — there's nothing to
"restore" since the live object you started from was never touched. Call `reconstruct_location` again
for another independent snapshot. For hypothetical locations that don't exist yet, see
[`build_location`](@ref) instead.

See Also: [`reconstruct_location!`](@ref), [`build_location`](@ref)
"""
function reconstruct_location(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    

    n,t=get_location_info(location_id)

    loc=t(location_id,n)

    reconstruct_location!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
    return loc 
end 







# ===================================================================== instrument_settings.jl

"""
    get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Resolve `instrument_id`'s current value per `Setting` name as of `sequence_id`/`time`, as a
`DataFrame` (columns `Setting`, `Value`, `SequenceID`). Unlike [`get_reads`](@ref), this *does*
collapse to latest-wins per `Setting` -- instrument settings behave like [`Attribute`](@ref) (a single
current value), not like [`Read`](@ref) (many coexisting values) -- mirroring
`get_attribute_caches`'s `ledger_subset` idiom.
"""
function get_instrument_settings(instrument_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_time=db_time(time)
    return query_db("""
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= ? AND SequenceID BETWEEN 0 AND ? GROUP BY SequenceID
        ),
        y (LedgerID,SequenceID,InstrumentID,Setting,Value)
        AS( SELECT s.LedgerID,l.SequenceID,s.InstrumentID,s.Setting,s.Value FROM InstrumentSettings s INNER JOIN ledger_subset l ON s.LedgerID = l.ID WHERE s.InstrumentID = ? )
        SELECT Setting,Value,Max(SequenceID) as SequenceID FROM y GROUP BY Setting
        """,(ledger_time,sequence_id,instrument_id))
end

# ===================================================================== encumbrances.jl (get_all_protocols)
function get_all_protocols(sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();enforced_only=true)
    starting=0 
    ending = sequence_id
    ledger_time=db_time(time)
    out= query_db("""
    With protocol_info(ExperimentID,ProtocolID,Name,UploadLedgerID,LedgerID,IsEnforced) AS( 
    SELECT p.ExperimentID , p.ID, p.Name ,p.LedgerIDCreatedAt, e.LedgerID, e.IsEnforced FROM Protocols p INNER JOIN ProtocolEnforcement e ON p.ID = e.ProtocolID
    ),
    ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT ID, SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending
            ),
    y (ExperimentID, ProtocolID, Name, UploadLedgerID,LedgerID, IsEnforced) AS( 
    
    SELECT p.ExperimentID, p.ProtocolID, p.Name, p.UploadLedgerID,Max(p.LedgerID),p.IsEnforced FROM protocol_info p INNER JOIN ledger_subset l ON p.LedgerID = l.ID GROUP BY p.ProtocolID
    ),
    z (ExperimentID, ExperimentName,ProtocolID, Name, UploadLedgerID,IsEnforced) AS(
    SELECT y.ExperimentID,Experiments.Name,y.ProtocolID,y.Name,y.UploadLedgerID,y.IsEnforced FROM y INNER JOIN Experiments ON y.ExperimentID =Experiments.ID 
    )

    SELECT * FROM z
    """
    )

    if enforced_only
        out = subset(out , :IsEnforced => x -> x .== 1)
    end 
    return out 
end 

# ===================================================================== observations.jl (observation_discrepancies)
_components(s::Stock) = merge(Dict{StockComponent,Any}(),solids(s),liquids(s),organisms(s))

"""
    observation_discrepancies(location_ids; sequence_id=get_last_sequence_id(), time=Dates.now())

Compare every observation of `location_ids` up to `sequence_id` with what history predicted just
before it, and return the ones that differ as a `DataFrame` with columns `LedgerID`, `SequenceID`,
`LocationID`, `Facet` (`"component"`, `"attribute"`, `"parent"`, `"locked"` or `"active"`),
`Key` (the component or attribute, else `missing`), `Predicted` and `Observed`.

Attributes are compared with the location's effective environment, so a value it inherits counts.
Parents are reported as location ids (`missing` for none).
"""
function observation_discrepancies(location_ids::Vector{<:Integer};sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    out=DataFrame(LedgerID=Int[],SequenceID=Int[],LocationID=Int[],Facet=String[],Key=Any[],Predicted=Any[],Observed=Any[])
    ledger_time=db_time(time)
    entry=query_join_vector(location_ids)
    subset="""WITH ledger_subset (ID,SequenceID,Time)
        AS(SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $sequence_id GROUP BY SequenceID)"""
    rows(tbl,loc_col="LocationID") = query_db("$subset SELECT o.*, l.SequenceID FROM $tbl o INNER JOIN ledger_subset l ON o.LedgerID = l.ID WHERE o.$loc_col IN $entry ORDER BY l.SequenceID")
    report!(row,loc_id,facet,key,predicted,observed) = push!(out,(row.LedgerID,row.SequenceID,loc_id,facet,key,predicted,observed))

    for row in eachrow(rows("ObservedComponents"))
        observed=row.Quantity*_parse_unit(row.Unit)
        component=get_component(row.ComponentID)
        comps=_components(CHESSCore.stock(reconstruct_contents(row.LocationID,row.SequenceID-1)))
        predicted=haskey(comps,component) ? uconvert(unit(observed),comps[component]) : zero(observed)
        isapprox(predicted,observed;rtol=1e-9) || report!(row,row.LocationID,"component",component,predicted,observed)
    end
    for row in eachrow(rows("ObservedAttributes"))
        kind=get_attribute(row.Attribute)
        observed=ismissing(row.Value) ? Attribute(kind,missing) : kind(row.Value*_parse_unit(row.Unit))
        env=environment(reconstruct_environment(row.LocationID,row.SequenceID-1))
        predicted=get(env,kind.name,Attribute(kind,missing))
        isequal(CHESSCore.value(predicted),CHESSCore.value(observed)) || report!(row,row.LocationID,"attribute",kind.name,predicted,observed)
    end
    for row in eachrow(rows("ObservedParents","Child"))
        prt=CHESSCore.parent(reconstruct_parent(row.Child,row.SequenceID-1))
        predicted=isnothing(prt) ? missing : location_id(prt)
        isequal(predicted,row.Parent) || report!(row,row.Child,"parent",missing,predicted,row.Parent)
    end
    for row in eachrow(rows("ObservedLocks"))
        predicted=is_locked(reconstruct_lock(row.LocationID,row.SequenceID-1))
        predicted == Bool(row.IsLocked) || report!(row,row.LocationID,"locked",missing,predicted,Bool(row.IsLocked))
    end
    for row in eachrow(rows("ObservedActivity"))
        predicted=is_active(reconstruct_activity(row.LocationID,row.SequenceID-1))
        predicted == Bool(row.IsActive) || report!(row,row.LocationID,"active",missing,predicted,Bool(row.IsActive))
    end
    sort!(out,:SequenceID)
    return out
end

observation_discrepancies(location_id::Integer;kwargs...) = observation_discrepancies([location_id];kwargs...)



# ===================================================================== lots.jl (reconstruct_lot)
"""
    reconstruct_lot(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> Union{Lot,Nothing}

The [`Lot`](@ref) most recently observed for the location as of `sequence_id` and `time`, or `nothing`
when none was observed.

See also: [`reconstruct_lot!`](@ref).
"""
function reconstruct_lot(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    rows=query_db("""
        WITH ledger_subset (ID,SequenceID) AS (
            SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
        SELECT p.Supplier, p.CatalogNumber, o.Lot, o.GTIN, o.Quantity, o.Unit, o.Cost, o.Received, o.Notes
        FROM ObservedLots o INNER JOIN ledger_subset l ON o.LedgerID = l.ID INNER JOIN Products p ON o.ProductID = p.ID
        WHERE o.LocationID = ? ORDER BY l.SequenceID DESC, o.ID DESC LIMIT 1
        """,(db_time(time),sequence_id,location_id))
    nrow(rows)==0 && return nothing
    r=rows[1,:]
    quantity = ismissing(r.Quantity) ? missing : r.Quantity*_parse_unit(r.Unit)
    received = ismissing(r.Received) ? missing : Date(r.Received)
    return Lot(r.Supplier,r.CatalogNumber,r.Lot;gtin=r.GTIN,quantity,cost=r.Cost,received,notes=r.Notes)
end

"""
    reconstruct_lot!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now())

Set the lot of a [`Labware`](@ref) to its reconstructed lot. Other locations have no lot and are left
unchanged. Arguments work as in [`reconstruct_lot`](@ref).
"""
function reconstruct_lot!(location::Labware,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    location.lot=reconstruct_lot(location_id(location),sequence_id,time)
    return nothing
end
reconstruct_lot!(::Location,args...) = nothing

# ===================================================================== tracing.jl
# Tracing: which lots the material in a well came from, found by replaying the ledger. A trace is
# computed on demand and never stored. It follows the same transfers and component observations as
# `reconstruct_contents`, and carries alongside each well's stock the quantity of each component that
# came from each lot.

# Replay state of one well: its stock, and the quantity of each component traced to a lot. Material in
# the stock that no share accounts for is untraced.
mutable struct _TracedWell
    stock::Stock
    shares::Dict{Tuple{StockComponent,Lot},Unitful.Quantity}
end
_TracedWell() = _TracedWell(Empty(),Dict{Tuple{StockComponent,Lot},Unitful.Quantity}())

function _component_quantity(st::Stock,component::StockComponent)
    dict = component isa Solid ? solids(st) : component isa Liquid ? liquids(st) : organisms(st)
    return get(dict,component,nothing)
end

# move the fraction `factor` of a well's stock and traced shares out, returning what left
function _withdraw_traced!(w::_TracedWell,quant)
    factor = Unitful.uconvert(Unitful.NoUnits,quant/CHESSCore.quantity(w.stock))
    out_stock = factor*w.stock
    out_shares = Dict(k=>factor*q for (k,q) in w.shares)
    w.stock = w.stock - out_stock
    for (k,q) in out_shares
        w.shares[k] -= q
    end
    return out_stock,out_shares
end

function _deposit_traced!(w::_TracedWell,stock::Stock,shares)
    w.stock = w.stock + stock
    mergewith!(+,w.shares,shares)
    return nothing
end

# State that `component` is present in the well at exactly `quant`. Material already there keeps its
# proportions among lots and untraced material. A component appearing in an empty well is traced to the
# lot of the well's labware, when it has one.
function _observe_traced!(w::_TracedWell,component::StockComponent,quant,bottle_lot::Union{Lot,Nothing})
    old = _component_quantity(w.stock,component)
    w.stock = set_component(w.stock,component,quant)
    if isnothing(old) || iszero(old)
        for k in filter(k->k[1]==component,collect(keys(w.shares)))
            delete!(w.shares,k)
        end
        isnothing(bottle_lot) || iszero(quant) || (w.shares[(component,bottle_lot)] = quant)
    else
        factor = Unitful.uconvert(Unitful.NoUnits,quant/old)
        for k in keys(w.shares)
            k[1]==component && (w.shares[k] *= factor)
        end
    end
    return nothing
end

"""
    trace_contents(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

Trace what a well holds back to the lots it came from, as of `sequence_id` and `time`. The result has one
row for each component and lot, with columns `Component`, `Lot`, and `Quantity`. Material that cannot be
tied to a lot, such as water drawn from a tap, appears as a row with a `missing` `Lot`.

The trace follows the transfers into the well and the observations of its ancestors, with each transfer
taking the same fraction of every lot's share of a component as of the component itself. A component
observed in a well that held none of it comes from the [`Lot`](@ref) of the well's labware as of
`sequence_id`, which is how a bottle's contents are attributed to the bottle's lot. A component observed
in a well that already held some keeps its proportions among lots.

The trace is computed from the ledger each time and is not stored. See also [`trace_cost`](@ref).
"""
function trace_contents(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    name,build = get_location_info(location_id)
    build(location_id,name) isa CHESSCore.Well || error("only a well holds contents to trace, and location $location_id is not one")
    transfers = get_transfer_ancestors([location_id],0,sequence_id,time)
    core = Set{Int}([location_id])
    for row in eachrow(transfers)
        row.Core == 1 && union!(core,ismissing(row.Destination) ? (row.Source,) : (row.Source,row.Destination))
    end
    observations = get_content_observations(collect(core),0,sequence_id,time)

    wells = Dict{Int,_TracedWell}()
    well(id) = get!(()->_TracedWell(),wells,id)
    lots = Dict{Int,Union{Lot,Nothing}}()
    function bottle_lot(well_id)
        get!(lots,well_id) do
            parent = CHESSCore.parent(reconstruct_parent(well_id,sequence_id,time))
            isnothing(parent) ? nothing : reconstruct_lot(CHESSCore.location_id(parent),sequence_id,time)
        end
    end
    components = Dict{Int,StockComponent}()
    component(id) = get!(()->get_component(id),components,id)

    events = vcat([(row.SequenceID,:transfer,row) for row in eachrow(transfers)],
                  [(row.SequenceID,:observation,row) for row in eachrow(observations)])
    sort!(events;by=first)
    for (_,kind,row) in events
        quant = row.Quantity*_parse_unit(row.Unit)
        if kind === :observation
            _observe_traced!(well(row.LocationID),component(row.ComponentID),quant,bottle_lot(row.LocationID))
        elseif row.Core == 1 && !ismissing(row.Destination)
            out_stock,out_shares = _withdraw_traced!(well(row.Source),quant)
            _deposit_traced!(well(row.Destination),out_stock,out_shares)
        else # a discard, or a core well's outgoing transfer to a well that never feeds back into it
            _withdraw_traced!(well(row.Source),quant)
        end
    end

    result = DataFrame(Component=StockComponent[],Lot=Union{Lot,Missing}[],Quantity=Unitful.Quantity[])
    w = well(location_id)
    for (component,total) in _components(w.stock)
        traced = [(k[2],q) for (k,q) in w.shares if k[1]==component]
        sort!(traced;by=t->(t[1].supplier,t[1].catalog_number,t[1].lot))
        for (lot,q) in traced
            push!(result,(component,lot,q))
        end
        remainder = total - sum(last.(traced);init=zero(total))
        abs(Unitful.ustrip(remainder)) > 1e-9*abs(Unitful.ustrip(total)) && push!(result,(component,missing,remainder))
    end
    return result
end

# What `quantity` of `component` costs, given the lot's price for its whole quantity. `missing` when the
# lot has no cost or quantity or its quantity cannot be expressed in the component's terms.
function _lot_cost(component::StockComponent,lot::Union{Lot,Missing},quantity)
    (ismissing(lot) || ismissing(lot.cost) || ismissing(lot.quantity)) && return missing
    total = try
        _in_quantity_of(component,lot.quantity,quantity)
    catch err
        err isa Union{ArgumentError,Unitful.DimensionError} || rethrow()
        return missing
    end
    return lot.cost*Unitful.uconvert(Unitful.NoUnits,quantity/total)
end

# a lot's purchased quantity in the dimension of `like`, converting through the component's density or
# molar mass when the lot is bought in a different dimension than the component is tracked in
function _in_quantity_of(component::StockComponent,purchased,like)
    Unitful.dimension(purchased) == Unitful.dimension(like) && return purchased
    component isa Reagent || throw(ArgumentError("$(component) cannot be converted between dimensions"))
    mass = Unitful.dimension(purchased) == Unitful.dimension(u"g") ? purchased :
           Unitful.dimension(purchased) == Unitful.dimension(u"mol") ? purchased*molecular_weight(component) :
           purchased*density(component)
    Unitful.dimension(like) == Unitful.dimension(u"g") && return Unitful.uconvert(Unitful.unit(like),mass)
    return Unitful.uconvert(Unitful.unit(like),mass/density(component))
end

"""
    trace_cost(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

The cost of what a well holds, share by share. It is [`trace_contents`](@ref) with a `Cost` column: the
cost of each share is the lot's `cost` times the share's fraction of the lot's `quantity`. The cost is
`missing` for a share with no lot, and for one whose lot has no cost or quantity.

See also: [`reconstruct_cost`](@ref).
"""
function trace_cost(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    traced = trace_contents(location_id,sequence_id,time)
    traced.Cost = Union{Float64,Missing}[_lot_cost(r.Component,r.Lot,r.Quantity) for r in eachrow(traced)]
    return traced
end

"""
    reconstruct_cost(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(); strict=false)

The cost of what a well holds: the sum of [`trace_cost`](@ref) over the shares whose cost is known. Material
with no known cost does not add to the sum, so the result is a lower bound unless every share is costed.
With `strict=true` the result is `missing` unless every share is costed.
"""
function reconstruct_cost(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();strict::Bool=false)
    costs = trace_cost(location_id,sequence_id,time).Cost
    strict && any(ismissing,costs) && return missing
    return sum(skipmissing(costs);init=0.0)
end

# ===================================================================== forward_tracing.jl
# Forward tracing: where material went after it was in a well or lot. This is the reverse of
# `trace_contents`, which finds the lots that the material in a well came from. A forward trace follows
# the recorded transfers out of a well, and out of every well they reach, in the order they happened. It is
# computed from the ledger each time and nothing is stored, so an amendment (`update` with `replace` or
# `insert`) changes the next answer, and a trace as of an earlier sequence ID still gives the old one.

# the transfers out of `sources` as of `sequence_id` and `time`, one row per transfer
function _transfers_out_of(sources::AbstractVector{<:Integer},sequence_id::Integer,time::DateTime)
    out=DataFrame(LedgerID=Int[],SequenceID=Int[],Source=Int[],Destination=Int[])
    for chunk in Iterators.partition(sources,_id_chunk)
        marks="("*join(fill("?",length(chunk)),",")*")"
        rows=query_db("""
            WITH ledger_subset (ID,SequenceID) AS (
                SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
            SELECT t.LedgerID, l.SequenceID, t.Source, t.Destination
            FROM Transfers t INNER JOIN ledger_subset l ON t.LedgerID = l.ID
            WHERE t.Source IN $marks
            """,(db_time(time),sequence_id,chunk...))
        append!(out,rows)
    end
    return out
end

# Spread from `seeds`, a dictionary from well ID to the sequence ID from which the well's material may
# be passed on. A transfer out of a well at sequence `s` carries the material on only if `s` is no
# earlier than the sequence from which the well has it (strictly later for a well that received it by
# transfer). Each well is kept at the earliest sequence it can be reached, which is repeated until nothing
# changes.
function _spread_forward(seeds::AbstractDict{<:Integer,<:Integer},sequence_id::Integer,time::DateTime)
    reached=Dict{Int,NamedTuple{(:sequence,:ledger,:depth,:via),Tuple{Int,Union{Int,Missing},Int,Union{Int,Missing}}}}()
    frontier=Int[]
    for (w,s) in seeds
        reached[w]=(sequence=s,ledger=missing,depth=0,via=missing)
        push!(frontier,w)
    end
    while !isempty(frontier)
        transfers=_transfers_out_of(frontier,sequence_id,time)
        changed=Set{Int}()
        for r in eachrow(transfers)
            from=reached[r.Source]
            # material arrived by transfer at `from.sequence`, so only later transfers carry it on
            usable = ismissing(from.ledger) ? r.SequenceID >= from.sequence : r.SequenceID > from.sequence
            usable || continue
            cur=get(reached,r.Destination,nothing)
            (isnothing(cur) || r.SequenceID < cur.sequence) || continue
            reached[r.Destination]=(sequence=r.SequenceID,ledger=r.LedgerID,depth=from.depth+1,via=r.Source)
            push!(changed,r.Destination)
        end
        frontier=collect(changed)
    end
    return reached
end

function _forward_result(reached)
    ids=sort!(collect(keys(reached));by=w->(reached[w].sequence,w))
    containers=well_containers(ids)
    return DataFrame(
        WellID=ids,
        ContainerID=Union{Int,Missing}[get(containers,w,missing) for w in ids],
        FirstSequenceID=[reached[w].sequence for w in ids],
        FirstLedgerID=Union{Int,Missing}[reached[w].ledger for w in ids],
        Depth=[reached[w].depth for w in ids],
        ViaWell=Union{Int,Missing}[reached[w].via for w in ids])
end

"""
    trace_forward(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(); from_sequence=0) -> DataFrame
    trace_forward(lot::Lot, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

Find every well that received material from a well, or from the labware received as a lot, as of
`sequence_id` and `time`. This is the reverse of [`trace_contents`](@ref), which finds the lots a well's
material came from. It is the list to check when a lot turns out to be bad, or when a transfer is
corrected with [`update`](@ref).

The result has one row for each well reached, including the starting wells, ordered by when they were
first reached, with columns:

- `WellID`: the well.
- `ContainerID`: the labware the well belongs to (see [`well_container`](@ref)), or `missing` if it is not recorded.
- `FirstSequenceID`: the sequence ID of the first transfer that brought material into the well, or of the start for a starting well.
- `FirstLedgerID`: the ledger entry of that transfer, or `missing` for a starting well.
- `Depth`: the number of transfers between the starting well and this one along that first path.
- `ViaWell`: the well that transfer came from, or `missing` for a starting well. Following `ViaWell` rebuilds the path.

The trace follows the transfers in the order they happened. A transfer out of a well carries the
material on only if it comes after the material arrived, so a transfer out of a well before it received
anything is not followed. `from_sequence` starts a well trace at a later point in the history. A lot
starts from every well of the labware that has the lot as of `sequence_id`, from the beginning of the
history.

The trace follows transfers only. It is slightly larger than the exact set: a transfer carries the
material on even if an observation has since overwritten that component in the well, and a
discard is not a way out. Planned operations (encumbrances) are not followed. The trace is
computed from the ledger each time and is not stored.

See also: [`forward_containers`](@ref), [`forward_runs`](@ref).
"""
function trace_forward(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();from_sequence::Integer=0)
    name,build=get_location_info(location_id)
    build(location_id,name) isa CHESSCore.Well || error("only a well can be traced forward, and location $location_id is not one")
    return _forward_result(_spread_forward(Dict(Int(location_id)=>Int(from_sequence)),sequence_id,time))
end

function trace_forward(lot::Lot,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    candidates=query_db("""
        WITH ledger_subset (ID,SequenceID) AS (
            SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
        SELECT DISTINCT o.LocationID
        FROM ObservedLots o INNER JOIN ledger_subset l ON o.LedgerID = l.ID INNER JOIN Products p ON o.ProductID = p.ID
        WHERE p.Supplier = ? AND p.CatalogNumber = ? AND o.Lot = ?
        """,(db_time(time),sequence_id,lot.supplier,lot.catalog_number,lot.lot))
    seeds=Dict{Int,Int}()
    for labware_id in candidates.LocationID
        current=reconstruct_lot(labware_id,sequence_id,time) # a later observation may have changed the labware's lot
        isnothing(current) && continue
        (current.supplier,current.catalog_number,current.lot)==(lot.supplier,lot.catalog_number,lot.lot) || continue
        for w in container_wells(labware_id).WellID
            seeds[w]=0
        end
    end
    return _forward_result(_spread_forward(seeds,sequence_id,time))
end

"""
    forward_containers(trace::DataFrame) -> DataFrame
    forward_containers(source, args...; kwargs...) -> DataFrame

The labware that holds the wells of a forward trace, with columns `ContainerID`, `WellCount` (the
number of reached wells in it) and `FirstSequenceID` (the earliest sequence at which any of them was
reached). Wells with no recorded labware are left out. The second form runs [`trace_forward`](@ref)
on `source` first.
"""
function forward_containers(trace::DataFrame)
    out=DataFrame(ContainerID=Int[],WellCount=Int[],FirstSequenceID=Int[])
    seen=Dict{Int,Int}()
    for r in eachrow(trace)
        ismissing(r.ContainerID) && continue
        i=get(seen,r.ContainerID,0)
        if i==0
            push!(out,(r.ContainerID,1,r.FirstSequenceID))
            seen[r.ContainerID]=nrow(out)
        else
            out.WellCount[i]+=1
            out.FirstSequenceID[i]=min(out.FirstSequenceID[i],r.FirstSequenceID)
        end
    end
    return out
end
forward_containers(source,args...;kwargs...) = forward_containers(trace_forward(source,args...;kwargs...))

"""
    forward_runs(trace::DataFrame) -> DataFrame
    forward_runs(source, args...; kwargs...) -> DataFrame

The runs recorded on the wells or labware of a forward trace, with columns `RunID`, `ExperimentID` and
`LocationID` (the well or labware the run is recorded on). The second form runs [`trace_forward`](@ref)
on `source` first.
"""
function forward_runs(trace::DataFrame)
    ids=unique(vcat(trace.WellID,collect(skipmissing(trace.ContainerID))))
    out=DataFrame(RunID=Int[],ExperimentID=Int[],LocationID=Int[])
    for chunk in Iterators.partition(ids,_id_chunk)
        marks="("*join(fill("?",length(chunk)),",")*")"
        rows=query_db("SELECT ID AS RunID, ExperimentID, LocationID FROM Runs WHERE LocationID IN $marks",Tuple(chunk))
        append!(out,rows)
    end
    return sort!(out,:RunID)
end
forward_runs(source,args...;kwargs...) = forward_runs(trace_forward(source,args...;kwargs...))

# ===================================================================== location_queries.jl
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

end # module Legacy
