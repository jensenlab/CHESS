function repair_environment_attribute_caches(ledger_id::Integer)
    sequence_id=get_sequence_id(ledger_id)

    participants=unique(get_participants(get_environment_attribute_participant,sequence_id))
    repair_environment_attribute_caches(participants,sequence_id)
end

# repair the attribute caches of `participants` at or after `sequence_id`
function repair_environment_attribute_caches(participants::Vector{<:Integer},sequence_id::Integer)
    cache_update_counter=0

    for loc_id in participants 
    caches=get_attribute_caches(loc_id,sequence_id)
    
        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_loc,foot=fetch_attribute_cache(loc_id,0,cache_seq_id)
            new_loc=reconstruct_attributes(loc_id,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.LedgerID || attributes(old_loc) != attributes(new_loc) # cache has been invalidated --replace the cache 
                
                cache_environment(new_loc,cache_ledger_id)
                cache_update_counter +=1 
            end 
        end
    end

    return cache_update_counter



end


# the location of every row of EnvironmentAttributes recorded under `ledger_id`
function get_environment_attribute_participant(ledger_id::Integer)
    return Vector{Int}(query_db("SELECT LocationID FROM EnvironmentAttributes WHERE LedgerID = ? ORDER BY ID",(ledger_id,)).LocationID)
end
