"""
    generate_location(kind::LocationKind,name::String=string(UUIDs.uuid4()),child_namer::Vararg{Function}=plate_namer)

Generate a real, database-tracked `kind` Location and fill it with empty wells if applicable.

Optionally add a variable number of functions to recursively name children of generated labware. naming functions should take two arguments `row` and `col` and return a string. The default is `plate_namer`

See also: [`plate_namer`](@ref), [`build_location`](@ref).
"""
function generate_location(kind::LocationKind,name::String=string(UUIDs.uuid4()),child_namer::Vararg{Function}=plate_namer)
    function next_id(nm,k)
        upload_location_type(k)
        return upload_new_location(nm,k)
    end
    lw=CHESSCore._build_location(kind,name,next_id,child_namer...)
    cache(lw)
    if lw isa Labware
        cache.(children(lw))
    end
    return lw
end
