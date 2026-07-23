

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
        AS(SELECT e.ID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.IsLocked
            FROM encumbrance_subset e INNER JOIN EncumberedCachedLockActivity v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsLocked
            FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID Group By l.SequenceID) 
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
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.LocationID,v.IsLocked
            FROM encumbrance_subset e INNER JOIN EncumberedLocks v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.LocationID,c.IsLocked
            FROM Locks c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
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
             SELECT  LedgerID,Max(SequenceID),0,LocationID,IsLocked FROM Locks INNER JOIN ledger_subset ON Locks.LedgerID = ledger_subset.ID WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 



