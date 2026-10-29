
function repair_content_caches(ledger_id::Integer)

    sequence_id=get_sequence_id(ledger_id)

    participants=get_participants(get_transfer_participants,sequence_id)
    locs=unique(vcat(collect.(participants)...))
    repair_content_caches(locs,sequence_id)
end

# The wells whose contents can change when the contents of `locs` change from `sequence_id` on: `locs` and the wells
# reached by transfers that follow the change in time (`_spread_forward`, the set `trace_forward` reports). It is a
# subset of the structural closure `get_transfer_descendents` returns, which also follows transfers that happened
# before the material arrived. A transfer out of a well at a slot before the change moved material the change did not
# touch, so the wells behind it keep their caches.
function _repair_set(locs::Vector{<:Integer},sequence_id::Integer;time_respecting::Bool=true)
    if time_respecting
        reached=_spread_forward(Dict{Int,Int}(Int(l)=>Int(sequence_id) for l in locs),get_last_sequence_id(),Dates.now())
        return collect(keys(reached))
    end
    trfs=get_transfer_descendents(locs,sequence_id)
    return unique(vcat(locs,trfs.Source,trfs.Destination))
end

# repair the content caches of `locs`, and of every well downstream of them, at or after `sequence_id`;
# returns the number of caches rewritten. `time_respecting=false` repairs the structural closure instead.
function repair_content_caches(locs::Vector{<:Integer},sequence_id::Integer;time_respecting::Bool=true)
    all_locs=_repair_set(locs,sequence_id;time_respecting=time_respecting)
    cache_update_counter=0
    for loc_id in all_locs

        caches=get_content_caches(loc_id,sequence_id)

        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_stock,_=fetch_content_cache(loc_id,0,cache_seq_id)
            new_loc=reconstruct_contents(loc_id,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.LedgerID || old_stock != stock(new_loc) 
            
            cache_contents(new_loc,cache_ledger_id)
            cache_update_counter +=1 
            end 
        end
    end 

    return cache_update_counter
end 







# the (source, destination) of every transfer recorded under `ledger_id`, in the order they were recorded
function get_transfer_participants(ledger_id::Integer)
    out=query_db("SELECT Source,Destination FROM Transfers WHERE LedgerID = ? ORDER BY ID",(ledger_id,))
    return Tuple{Int,Int}[(r.Source,r.Destination) for r in eachrow(out)]
end
