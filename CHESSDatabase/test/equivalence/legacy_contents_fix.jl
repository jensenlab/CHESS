# Included into the `Legacy` module by test_equivalence.jl (Base.include(Legacy, ...)); see "reconstruct_contents: a well that
# only receives from the requested closure" in test_equivalence.jl. This is Legacy.reconstruct_contents (the vector method,
# legacy_reconstruction.jl lines 1154-1284) copied verbatim except for the two edits that keep a well which only receives from
# the requested closure out of the closure (`core_locs`) and skip what such a well sent on. The frozen file is not edited.

function reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(), max_cache::Integer=sequence_id, loc_index::Dict{<:Integer,<:Vector} = location_reconstruction_index;encumbrances=false)
    all_locs=deepcopy(loc_index)
    cache_feet=[]
    for loc_id in location_ids
        n,t=get_location_info(loc_id)
        loc=t(loc_id,n)
        if !(loc isa CHESSCore.Well)
            push_location!(all_locs,loc_id,0,loc)
            continue
        end
        stock,cache_foot = fetch_content_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        if !isnothing(stock)
            deposit!(loc,stock)
        end

        push_location!(all_locs,CHESSCore.location_id(loc),cache_foot,loc)
        push!(cache_feet,cache_foot)


    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    transfers=get_transfer_ancestors(location_ids,foot+1,sequence_id,time;encumbrances=encumbrances)



    # locations that are part of the genuine ancestor closure (Core=1 in some row) need a real,
    # possibly-recursive bootstrap below. Locations that only appear because a core location's
    # *other* outgoing transfer happened to land on them ("collateral", Core=0 everywhere they
    # appear) never get read back out of this call -- see get_transfer_ancestors's docstring --
    # so they're built as bare Empty() stubs instead, without ever touching the cache tables or
    # recursing. This is what keeps a busy/shared well's reconstruction from cascading into a large,
    # mostly-irrelevant slice of the ledger just because get_transfer_ancestors had to look at it.
    # A well that only receives from a requested well is not part of that closure, even though its row is Core=1: nothing
    # it holds can reach a requested well. The closure is the requested wells and every source that feeds it.
    core_locs=Set{Integer}(location_ids)
    if nrow(transfers) > 0 && hasproperty(transfers,:Core)
        core_rows=[row for row in eachrow(transfers) if row.Core == 1]
        grew=true
        while grew
            grew=false
            for row in core_rows
                row.Source in core_locs && continue
                if ismissing(row.Destination) || row.Destination in core_locs
                    push!(core_locs,row.Source)
                    grew=true
                end
            end
        end
    end

    # component observations on every well whose own state this call reads back: the
    # requested wells plus the core ancestor closure. Collateral destinations never need them.
    target_wells=filter(id -> find_most_recent_location(all_locs,id) isa CHESSCore.Well,location_ids)
    observations=get_content_observations(collect(union(core_locs,target_wells)),foot+1,sequence_id,time)

    # grab the sequence id of each location we need to complete this set of transfers
    cache_dict=Dict{Integer,Integer}()
    for row in reverse(eachrow(transfers))

        seq_id=min(row.SequenceID-1,sequence_id)
        # set it back to the sequence id we are looking at if the transfer is encumbered


        cache_dict[row.Source]=seq_id
        ismissing(row.Destination) || (cache_dict[row.Destination]=seq_id)
    end
    # a core well must also be bootstrapped from before its first observation
    for row in eachrow(observations)
        row.LocationID in core_locs || continue
        seq_id=min(row.SequenceID-1,sequence_id)
        cache_dict[row.LocationID]=min(get(cache_dict,row.LocationID,seq_id),seq_id)
    end
    reconstructions_needed=Set{Integer}()
    for loc_id in keys(cache_dict)

        if !(loc_id in core_locs)
            n,t=get_location_info(loc_id)
            push_location!(all_locs,loc_id,foot,t(loc_id,n))
            continue
        end

        new_stock,new_foot=fetch_content_cache(loc_id,foot,cache_dict[loc_id],time;encumbrances=false)
        n,t=get_location_info(loc_id)
        new_loc=t(loc_id,n)
        if !isnothing(new_stock)
            deposit!(new_loc,new_stock)
            push_location!(all_locs,loc_id,new_foot,new_loc)
        else
            push!(reconstructions_needed,loc_id)
        end
    end
    if length(reconstructions_needed) > 0
        locs=reconstruct_contents(collect(reconstructions_needed),foot,time,max_cache,all_locs)
        for loc in locs
            push_location!(all_locs,CHESSCore.location_id(loc),foot,loc)
        end
    end

    #start simulation: transfers and observations in sequence order. An observation never shares a
    # SequenceID with a transfer (each is its own ledger entry), so the relative order of equal keys
    # doesn't matter.
    events=vcat([(row.SequenceID,row) for row in eachrow(transfers)],
                [(key.SequenceID,rows) for (key,rows) in pairs(groupby(observations,[:LocationID,:SequenceID];sort=false))])
    sort!(events;by=first)

    for (_,row) in events
        if !(row isa DataFrameRow)
            _apply_content_observations!(all_locs,row)
            continue
        end
        # what a well outside the closure sent on (or discarded) is never read back
        (row.Core == 0 || ismissing(row.Destination)) && !(row.Source in core_locs) && continue
        seq_id=row.SequenceID -1
        quant= row.Quantity * _parse_unit(row.Unit)
        src = find_most_recent_location(all_locs,row.Source,seq_id)

        if row.Core == 0 || ismissing(row.Destination) # a discard has no destination to track
            # Collateral: this row exists only so a *core* location's balance is correctly reduced
            # by whatever it sent elsewhere -- the destination itself is never read back out of this
            # call (see get_transfer_ancestors's docstring), so there's no need to find, deepcopy, or
            # track it at all. Just withdraw from a copy of the source and discard the rest.
            new_src = deepcopy(src)
            withdraw!(new_src,quant)
            push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
            continue
        end

        dest = find_most_recent_location(all_locs,row.Destination,seq_id)
        new_src,new_dest=_reconstruction_transfer(src,dest,quant)
        push_location!(all_locs,CHESSCore.location_id(dest),seq_id+1,new_dest)
        push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
    end

    final_out = find_most_recent_location.((all_locs,), location_ids)


    return final_out
end 
