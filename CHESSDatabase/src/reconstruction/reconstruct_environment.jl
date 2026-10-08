"""
    reconstruct_environment(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_environment(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild each location's chain of ancestors and their attributes, so that `environment` gives the inherited environment for the given location IDs, as of `sequence_id` and `time`, and return new
locations holding that state. [`reconstruct_location`](@ref) rebuilds everything at once; the
arguments work the same way (see [`reconstruct_location!`](@ref)).

See also: [`reconstruct_environment!`](@ref).
"""
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



"""
    reconstruct_environment!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_environment!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the parent chain and attributes of existing locations to their reconstructed state. Arguments work as in
[`reconstruct_environment`](@ref).
"""
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


    

