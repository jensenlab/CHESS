"""
    mutable struct Barcode

A physical barcode string, with an optional name and the `location_id` of the location it is
attached to (`missing` until assigned). See [`assign_barcode!`](@ref).
"""
mutable struct Barcode 
   const id::String
    const name::Union{String,Missing}
    location_id::Union{Integer,Missing}
    Barcode(id,name=missing,location_id=missing)=new(id,name,location_id)
end 


"""
    barcode(x::Barcode) -> String

The barcode string itself.
"""
barcode(x::Barcode)=x.id 
location_id(x::Barcode)=x.location_id
name(x::Barcode)=x.name



"""
    assign_barcode!(barcode::Barcode, location::Location; instrument=nothing)

Attach `barcode` to `location` in memory. Throws an error if the barcode is already attached to a
different location. [`update_barcode`](@ref) records the assignment in the database.
"""
function assign_barcode!(barcode::Barcode,location::Location;instrument::Union{Location,Nothing}=nothing)
        loc_id=location_id(barcode)
        if !ismissing(loc_id) && loc_id !== location_id(location)
            error("barcode already assigned to another location")
        else
            barcode.location_id=location_id(location)
            return nothing
        end
end


"""
    assign_barcode(barcode::Barcode, location::Location) -> Barcode

Non-mutating [`assign_barcode!`](@ref): return a copy of `barcode` attached to `location`.
"""
function assign_barcode(barcode::Barcode,location::Location)
    bc=deepcopy(barcode)
    assign_barcode!(bc,location)
    return bc
end 
