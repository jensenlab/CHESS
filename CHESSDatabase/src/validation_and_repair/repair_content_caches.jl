
function repair_content_caches(ledger_id::Integer)

    sequence_id=get_sequence_id(ledger_id)

    participants=get_participants(get_transfer_participants,sequence_id)
    locs=unique(vcat(collect.(participants)...))
    trfs=get_transfer_descendents(locs,sequence_id)
    
    srcs=trfs.Source
    dests=trfs.Destination

    all_locs=unique(vcat(srcs,dests))
    cache_update_counter=0
    for loc_id in all_locs

        caches=get_content_caches(loc_id,sequence_id)

        for cache in eachrow(caches)

            cache_seq_id=cache.SequenceID
            old_stock,a,b=fetch_content_cache(loc_id,0,cache_seq_id)
            new_loc=reconstruct_contents(loc_id,cache_seq_id,Dates.now(),cache_seq_id-1) # reconstruct but only use caches from before the one we are testing
            cache_ledger_id=get_last_ledger_id(cache_seq_id)
            if cache_ledger_id != cache.LedgerID || old_stock != stock(new_loc) 
            
            cache_contents(new_loc,cache_ledger_id)
            cache_update_counter +=1 
            end 
        end
    end 

    println("caches updated: $cache_update_counter")
end 







function get_transfer_participants(ledger_id::Integer)
    x="SELECT LedgerID,Source,Destination,Quantity,Unit FROM Transfers WHERE LedgerID = $ledger_id"
    out=query_db(x) 
    if nrow(out)==1 
        return out[1,"Source"],out[1,"Destination"]
    elseif nrow(out)==0 
        error("found no transfer entries for ledger id $ledger_id ")
    elseif nrow(out)> 1 
        error("found multiple transfer entries for ledger id $ledger_id")
    end 
end 




