

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
        AS(SELECT e.ID, 0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.IsActive
            FROM encumbrance_subset e INNER JOIN EncumberedCachedLockActivity v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.IsActive
            FROM CachedLockActivity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID Group By l.SequenceID) 
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
        AS(SELECT 0,$(get_last_sequence_id())+v.EncumbranceID, v.EncumbranceID, v.LocationID,v.IsActive
            FROM encumbrance_subset e INNER JOIN EncumberedActivity v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT c.LedgerID,l.SequenceID,0, c.LocationID,c.IsActive
            FROM Activity c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
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
             SELECT  LedgerID,Max(SequenceID),0,LocationID,IsActive FROM Activity INNER JOIN ledger_subset ON Activity.LedgerID = ledger_subset.ID WHERE  LocationID in $entry GROUP BY LocationID  ORDER BY SequenceID 
             )
        Select * FROM y 
        """
    end
    return query_db(x)
end 



