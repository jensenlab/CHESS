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


function reconstruct_parent!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_locs=reconstruct_parent(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)

    for i in eachindex(locations)
        locations[i].parent = CHESSCore.parent(parallel_locs[i])
    end 
    return nothing 
end 

function reconstruct_parent!(location::Location,sequence_id=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstrut_parent(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
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
        AS(SELECT e.ID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.ParentID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedAncestors v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.ParentID
            FROM CachedAncestors c INNER JOIN ledger_subset l ON c.LedgerID = l.ID Group By l.SequenceID) 
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
            FROM Movements c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
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
             SELECT  LedgerID,Max(SequenceID),0,Parent,Child FROM Movements INNER JOIN ledger_subset ON Movements.LedgerID = ledger_subset.ID WHERE  Child in $entry GROUP BY Child   ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 
