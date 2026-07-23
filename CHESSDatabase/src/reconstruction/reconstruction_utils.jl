
function get_location_info(id::Integer)
    loc_info=query_db("SELECT * FROM Locations WHERE ID =?",(id,))
    if nrow(loc_info) == 0
        error("location id not found")
    end
    out=loc_info[1,:]
    name=string(out["Name"])
    k=location_kinds[Symbol(out["Type"])]
    constructor(location_id,nm)=concretetype(k)(location_id,nm,k)
    return name, constructor
end


const location_reconstruction_df=DataFrame(LocationID=Integer[],SequenceID=Integer[],Location=Location[]) # initalizes a set of reconstructed locations 

function find_most_recent_location(set::DataFrame,location_id::Integer)
    x=set[(set.LocationID .== location_id) ,:  ]
    if nrow(x) > 0 
        sort!(x,:SequenceID)

        return x[end,"Location"]
    else 
        return nothing
    end
end

function find_most_recent_location(set::DataFrame,location_id::Integer,sequence_id::Integer)
    x=set[(set.LocationID .== location_id) .& (set.SequenceID .<= sequence_id) ,:  ]
    if nrow(x) > 0 
        sort!(x,:SequenceID)

        return x[end,"Location"]
    else 
        return nothing
    end
end