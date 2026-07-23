

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
        AS(SELECT e.ID,0,$(get_last_sequence_id())+e.EncumbranceID,e.EncumbranceID, v.LocationID,v.ChildSetID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedDescendants v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.ChildSetID
            FROM CachedDescendants c INNER JOIN ledger_subset l ON c.LedgerID = l.ID Group By l.SequenceID) 
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
            FROM Movements c INNER JOIN ledger_subset l ON c.LedgerID = l.ID) ,
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
             SELECT  LedgerID,Max(SequenceID),0,Parent,Child FROM Movements INNER JOIN ledger_subset ON Movements.LedgerID = ledger_subset.ID GROUP BY Child   ORDER BY SequenceID 
             )
        Select * FROM y WHERE Parent in $entry
        """
    end
    return query_db(x)
end

function get_child_movements(locs::Vector{<:Integer},current_children::Dict{Integer,Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    ledger_time= db_time(time)
    loc_plus_children=unique(vcat(locs,collect(keys(current_children))))
    a=get_last_movement_as_child(collect(keys(current_children)),starting,ending;encumbrances=encumbrances)
    b=get_last_movements_as_parent(locs,starting,ending;encumbrances=encumbrances)

    
    final_movements=vcat(a,b)
    sort!(final_movements,:SequenceID)
    
    return final_movements
end