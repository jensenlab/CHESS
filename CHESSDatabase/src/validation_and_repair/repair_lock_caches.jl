function repair_lock_caches(ledger_id::Integer)
    sequence_id=get_sequence_id(ledger_id)

    participants=unique(get_participants(get_lock_participant,sequence_id))
    repair_lock_caches(participants,sequence_id)
end

# repair the lock caches of `participants` at or after `sequence_id`
function repair_lock_caches(participants::Vector{<:Integer},sequence_id::Integer)
    cache_update_counter=0

    for loc_id in participants 
        caches=get_lock_caches(loc_id,sequence_id)
        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_loc,foot=fetch_lock_cache(loc_id,0,cache_seq_id)
            new_loc=reconstruct_lock(loc_id,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.LedgerID || is_locked(old_loc) != is_locked(new_loc) # cache has been invalidated --replace the cache 
                
                reconstruct_activity!(new_loc,cache_seq_id,Dates.now(),cache_seq_id-1) # also need to reconstruct the activity state to cache, even though presumably it hasn't changed.
                cache_lock_activity(new_loc,cache_ledger_id)
                cache_update_counter +=1 
            end 
        end
    
    end
    return cache_update_counter



end


# the location of every row of Locks recorded under `ledger_id`
function get_lock_participant(ledger_id::Integer)
    return Vector{Int}(query_db("SELECT LocationID FROM Locks WHERE LedgerID = ? ORDER BY ID",(ledger_id,)).LocationID)
end
