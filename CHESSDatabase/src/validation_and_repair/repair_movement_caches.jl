function repair_movement_caches(ledger_id::Integer)


    sequence_id=get_sequence_id(ledger_id)

    participants=get_participants(get_movement_participants,sequence_id)
    unique_children=unique(map(x->x[2],participants))
    # a movement with no parent is a removal, so the parent that lost the child needs its caches repaired
    # too: it is the parent the child had just before this entry
    lost=[CHESSCore.parent(reconstruct_parent(chld,sequence_id-1)) for chld in unique_children]
    unique_parents= unique(vcat(collect(skipmissing(map(x-> x[1],participants))),location_id.(filter(!isnothing,lost))))
    repair_movement_caches(unique_parents,unique_children,sequence_id)
end

# repair the child caches of `unique_parents` and the parent caches of `unique_children` at or after
# `sequence_id`
function repair_movement_caches(unique_parents::Vector,unique_children::Vector{<:Integer},sequence_id::Integer)
    cache_update_counter=0

    # repair the parent's child caches 
    for prt in unique_parents
        caches=get_child_caches(prt,sequence_id)
        
        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_loc,foot=fetch_child_cache(prt,0,cache_seq_id)
            new_loc=reconstruct_children(prt,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id  != cache.LedgerID || children(old_loc) != children(new_loc) # cache has been invalidated --replace the cache 
                
                cache_children(new_loc,cache_ledger_id)
                cache_update_counter +=1 
            end 
        end
    end
        # repair the child's parent caches 
    for chld in unique_children
        caches=get_parent_caches(chld,sequence_id)
        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_loc,foot=fetch_parent_cache(chld,0,cache_seq_id)
            new_loc=reconstruct_parent(chld,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.LedgerID || CHESSCore.parent(old_loc) != CHESSCore.parent(new_loc) # cache has been invalidated --replace the cache 

                
                cache_parent(new_loc,cache_ledger_id)
                cache_update_counter +=1 
            end 
        end
    end
   

    return cache_update_counter


end 



# the (parent, child) of every movement recorded under `ledger_id` (the parent is `missing` for a removal)
function get_movement_participants(ledger_id::Integer)
    out=query_db("SELECT Parent,Child FROM Movements WHERE LedgerID = ? ORDER BY ID",(ledger_id,))
    return Tuple{Union{Missing,Int},Int}[(r.Parent,r.Child) for r in eachrow(out)]
end
