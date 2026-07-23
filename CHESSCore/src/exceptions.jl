

"""
    WellCapacityError(vol,cap)

The volume `vol` exceeds the capacity `cap` of its well.

"""
struct WellCapacityError <:Exception
    vol::Any
    cap::Any
 end

function Base.showerror(io::IO, e::WellCapacityError)
    print(io, "Well Capacity Error: ", e.vol ," is greater than the well's capacity (",e.cap,")")
    nothing
end 


"""
    MixingError(chem,msg)

chemical `chem` causes a mixing operation to be invalid
"""
struct MixingError <: Exception
    chem::Any
    msg::Any
end 

function Base.showerror(io::IO,e::MixingError)
    print(io,"Mixing Error with ",e.chem)
    print(io,"\n",e.msg)
    nothing 
end 


"""
    AlreadyLocatedInError

The two locations already share a parent-child relationship
"""
struct AlreadyLocatedInError <: Exception 
end 

function Base.showerror(io::IO,e::AlreadyLocatedInError)
    print(io,"Already-Located-In Error")
end 


"""
    OccupancyError(val,msg)

The movement would overoccupy the parent, with an occupancy `val` greater than 1
"""
struct OccupancyError <: Exception 
    val::Number
    msg::AbstractString 
end 

function Base.showerror(io::IO,e::OccupancyError) 
    print(io,"Occupancy Error: (",e.val,")")
    print(io,"\n",e.msg)
    nothing
end


"""
    LockedLocationError(loc)

The location cannot be moved because it is locked
"""
struct LockedLocationError <: Exception
    loc::Any
end

function Base.showerror(io::IO,e::LockedLocationError)
    print(io, "Locked Location Error with: ",e.loc)
    nothing
end


"""
    FixedMembershipError(loc,msg)

`loc`'s children are fixed and cannot be added to or removed from through the normal movement API.
"""
struct FixedMembershipError <: Exception
    loc::Any
    msg::Any
end

function Base.showerror(io::IO,e::FixedMembershipError)
    print(io,"Fixed Membership Error with ",e.loc)
    print(io,"\n",e.msg)
    nothing
end


"""
    AmbiguousOccupancyRuleError(parent_kind,child_kind,matches)

More than one category-based occupancy rule matches `parent_kind`/`child_kind` with no exact-kind
rule to break the tie. Add an explicit exact-kind rule to resolve the ambiguity.
"""
struct AmbiguousOccupancyRuleError <: Exception
    parent_kind::Any
    child_kind::Any
    matches::Any
end

function Base.showerror(io::IO,e::AmbiguousOccupancyRuleError)
    print(io,"Ambiguous Occupancy Rule Error: multiple category rules match (",e.parent_kind,", ",e.child_kind,"): ",e.matches)
    print(io,"\nAdd an explicit exact-kind occupancy rule to resolve this.")
    nothing
end


"""
    ChildNotFoundError(loc,name)

No child of `loc` has the given `name`.
"""
struct ChildNotFoundError <: Exception
    loc::Any
    name::Any
end

function Base.showerror(io::IO,e::ChildNotFoundError)
    print(io,"Child Not Found Error: no child of ",e.loc," named ",e.name)
    nothing
end


"""
    AmbiguousChildNameError(loc,name,matches)

More than one child of `loc` has the given `name`.
"""
struct AmbiguousChildNameError <: Exception
    loc::Any
    name::Any
    matches::Any
end

function Base.showerror(io::IO,e::AmbiguousChildNameError)
    print(io,"Ambiguous Child Name Error: ",length(e.matches)," children of ",e.loc," are named ",e.name)
    nothing
end


"""
    UncommittedLocationError(loc)

An uncommitted Location (no `location_id`) was passed to a function that requires the location to
already be tracked in the database.
"""
struct UncommittedLocationError <: Exception
    loc::Any
end

function Base.showerror(io::IO,e::UncommittedLocationError)
    print(io,"Uncommitted Location Error: ",e.loc," has no location_id and has not been committed. See commit_location!.")
    nothing
end
