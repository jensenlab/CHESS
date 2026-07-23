function reconstruct_environment(location_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    
    all_locs=Dict{Integer,Location}()
    parent_set=location_ids


    while length(parent_set) > 0 
        new_locs=reconstruct_parent(parent_set,sequence_id,time,max_cache;encumbrances=encumbrances)
        for loc in new_locs 
            all_locs[CHESSCore.location_id(loc)]=loc
        end 
        parent_set=Int.(unique(filter(x->!isnothing(x),map(x->CHESSCore.location_id(CHESSCore.parent(x)),new_locs))))
    end 

    all_keys=collect(keys(all_locs))
    all_vals=collect(values(all_locs))

    reconstruct_attributes!(all_vals,sequence_id,time,max_cache;encumbrances=encumbrances)

    all_locs=Dict(all_keys .=> all_vals) 

    for key in collect(all_keys) 
        prt_id = CHESSCore.location_id(CHESSCore.parent(all_locs[key]))
        if isnothing(prt_id)
            all_locs[key].parent=nothing 
        else 

            all_locs[key].parent = all_locs[prt_id]
        end 
    end 

    return map(x->all_locs[x],location_ids)
end 

function reconstruct_environment(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    return reconstruct_environment([location_id],sequence_id,time,max_cache;encumbrances=encumbrances)[1]
end 



function reconstruct_environment!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)

    parallel_locs=reconstruct_environment(location_id.(locations),sequence_id,time,max_cache;encumbrances=encumbrances)
    for i in eachindex(locations)
        locations[i].parent= CHESSCore.parent(parallel_locs[i])
        locations[i].attributes=CHESSCore.attributes(parallel_locs[i])
    end
     return nothing 
end 

function reconstruct_environment!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false)
    parallel_loc=reconstruct_environment(location_id(location),sequence_id,time,max_cache;encumbrances=encumbrances)
    location.parent=CHESSCore.parent(parallel_loc)
    location.attributes=CHESSCore.attributes(parallel_loc)
    return nothing 
end 


    

