function repair_movement_caches(ledger_id::Integer)


    sequence_id=get_sequence_id(ledger_id)

    participants=get_participants(get_movement_participants,sequence_id)
    cache_update_counter=0

    unique_parents= unique(map(x-> x[1],participants) )
    unique_children=unique(map(x->x[2],participants))
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
   

    println("caches updated: $cache_update_counter")


end 



function get_movement_participants(ledger_id::Integer)
    x="SELECT LedgerID,Parent,Child FROM Movements WHERE LedgerID = $ledger_id"
    out=query_db(x) 
    if nrow(out)==1 
        return out[1,"Parent"],out[1,"Child"]
    elseif nrow(out)==0 
        error("found no movement entries for ledger id $ledger_id ")
    elseif nrow(out)> 1 
        error("found multiple movement entries for ledger id $ledger_id")
    end 
end 