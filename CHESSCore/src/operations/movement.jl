

"""
    can_move_into(parent::Location,child::Location)

returns `true` if child can be moved into parent, throw an error if not

there are four errors that prevent movement

1) [`LockedLocationError`](@ref): `child` is locked in its current parent.
2) [`AlreadyLocatedInError`](@ref): `child` is already located in `parent`
3) [`OccupancyError`](@ref): `parent` has occupancy constraints that prevent it from containing `child`. This could happen if `parent` is full or if `child` is never meant to be able to fit inside `parent`.
4) [`FixedMembershipError`](@ref): `child` is a [`Well`](@ref) -- wells are physically fused to their
   labware and can never be independently relocated, regardless of any occupancy rule (see the
   `can_move_into(::Location,child::Well)` method below).

See also: [`move_into!`](@ref)
"""
function can_move_into(newparent::Location,child::Location)
        if is_locked(child)
                throw(LockedLocationError(child))
        end 

        if AbstractTrees.ischild(child,newparent)
                throw(AlreadyLocatedInError())  #the child is already located in parent 
        end 
        occ_cost = occupancy_cost(newparent,child)
        current= occupancy(newparent)
        if current + occ_cost <= 1//1 
            return true  # movement is allowed! 
        else 
            throw(OccupancyError(current+occ_cost,"movement would overoccupy parent")) # movement would overfill the parent, we block the movement 
        end 
end 



"""
    can_move_into(::Location,child::Well)

A [`Well`](@ref) is physically fused to its [`Labware`](@ref) and can never be independently
relocated -- this always throws [`FixedMembershipError`](@ref), regardless of any
[`set_occupancy_cost!`](@ref) rule that might otherwise apply to the (parent kind, child kind) pair.
Dispatches ahead of the generic `can_move_into(::Location,::Location)` for any `Well` child.
"""
function can_move_into(::Location,child::Well)
    throw(FixedMembershipError(child,"Wells are physically fused to their Labware and cannot be independently relocated"))
end

"""
    remove!(parent::Labware,child::Location)
    remove!(parent::Well,child::Location)

Mirrors [`add_to!`](@ref)'s `Labware`/`Well` overloads: slots are fixed at creation, so removing a
child is just as structurally invalid as adding one -- both throw [`FixedMembershipError`](@ref).
"""
function remove!(parent::Labware,child::Location)
    throw(FixedMembershipError(parent,"Labware slots are fixed at creation; wells cannot be removed"))
end

function remove!(parent::Well,child::Location)
    throw(FixedMembershipError(parent,"Wells cannot have children"))
end

function remove!(parent::Location,child::Location)
    filter!(x->x !== child,parent.children)
    return nothing
end

"""
    add_to!(parent::Labware,child::Location)
    add_to!(parent::Well,child::Location)

`Labware` slots are fixed at creation (populated by [`generate_location`](@ref)) and `Well`s never
have children — both throw [`FixedMembershipError`](@ref) rather than allowing `move_into!` to
mutate their (structurally fixed) membership.
"""
function add_to!(parent::Labware,child::Location)
    throw(FixedMembershipError(parent,"Labware slots are fixed at creation; use generate_location to populate them"))
end

function add_to!(parent::Well,child::Location)
    throw(FixedMembershipError(parent,"Wells cannot have children"))
end

function add_to!(parent::Location,child::Location)
    check=can_move_into(parent,child)
    push!(parent.children,child)
    child.parent=parent
    invalidate_environment!(child)
    return nothing
end

function add_to!(parent::Nothing,child::Location)
    child.parent=nothing
    invalidate_environment!(child)
    return nothing
end



"""
    move_into!(parent::Location,child::Location,lock::Bool=false;instrument=nothing)

Move `child` into `parent`, if allowed.

if `lock=true`, then also lock the child after the movement. See [`_check_capability`](@ref) for
`instrument`.
"""
function move_into!(parent::Union{Location,Nothing},child::Location,lock::Bool=false;instrument::Union{Instrument,Nothing}=nothing)
    _check_capability(instrument,move_into!)
    oldparent=child.parent
    add_to!(parent,child)
    if !isnothing(oldparent)
        remove!(oldparent,child)
    end
    if lock
        lock!(child)
    end
end








