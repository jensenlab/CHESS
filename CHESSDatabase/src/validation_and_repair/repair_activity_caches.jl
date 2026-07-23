function repair_activity_caches(ledger_id::Integer)
    sequence_id=get_sequence_id(ledger_id)

    participants=unique(get_participants(get_activity_participant,sequence_id))
    cache_update_counter=0
    for loc_id in participants

        caches=get_activity_caches(loc_id,sequence_id)
        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_loc,foot=fetch_activity_cache(loc_id,0,cache_seq_id)
            new_loc=reconstruct_activity(loc_id,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.SequenceID || is_active(old_loc) != is_active(new_loc) # cache has been invalidated --replace the cache 
                
                reconstruct_lock!(new_loc,cache_seq_id,Dates.now(),cache_seq_id-1) # also need to reconstruct the lock state to cache, even though presumably it hasn't changed.
                cache_lock_activity(new_loc,cache_ledger_id)
                cache_update_counter +=1 
            end 
        end
    end 
   

    println("caches updated: $cache_update_counter")



end


function get_activity_participant(ledger_id::Integer)
        x="SELECT LedgerID,LocationID FROM Activity WHERE LedgerID = $ledger_id"
        out=query_db(x) 

        if nrow(out)==1 
            return out[1,"LocationID"]
        elseif nrow(out)==0 
            error("found no activity entries for ledger id $ledger_id ")
        elseif nrow(out)> 1 
            error("found multiple activity entries for ledger id $ledger_id")
        end 
    end 