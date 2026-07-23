
"""
    abstract type Location end

Locations represent the physical objects that make up the lab. `Location` objects use the [AbstractTrees.jl](https://juliacollections.github.io/AbstractTrees.jl/stable/) interface to construct relational hierarchies.

The concrete subtypes are [`GenericLocation`](@ref) (mutable membership over time), [`Labware`](@ref)
(fixed, permanent grid membership), and [`Well`](@ref) (terminal leaf holding a [`Stock`](@ref)).
Every distinct *kind* of location/labware (`:Room`, `:Incubator`, `:WP96`, ...) is data (a
[`LocationKind`](@ref)), not a distinct Julia type — see [`@location_kind`](@ref).
"""
abstract type Location end

# The four definitions below jointly implement AbstractTrees.jl's node interface for Location.
AbstractTrees.children(x::Location) = x.children
AbstractTrees.parent(x::Location) =x.parent
AbstractTrees.nodevalue(x::Location)=location_id(x)
AbstractTrees.ParentLinks(::Type{<:Location})=StoredParent()

# `parent` alone also gets a Base.parent method, unlike children/nodevalue above: Base already has its
# own unrelated `parent` generic (for array/view wrappers like SubDataFrame/ReinterpretArray), so
# `import AbstractTrees: parent; export parent` collides with it -- `using CHESSCore` (or CHESS) ends
# up with the bare name `parent` silently resolving to Base's version instead of this one, and calling
# it on a Location throws a MethodError. Base has no `children`/`nodevalue` to collide with, so those
# two don't need this and are exported directly from AbstractTrees as-is. Extending Base.parent for
# Location is ordinary (not type piracy -- Location is CHESSCore's own type) and makes the bare name
# resolve correctly with nothing extra required, since Base.parent is already visible everywhere by
# default. Do not remove this thinking the asymmetry with children/nodevalue is a mistake to "clean up".
Base.parent(x::Location) = AbstractTrees.parent(x)
childtype(::Location)=Location
# No generic `stock` fallback here -- only Well actually holds a Stock (see Well.jl); a fallback that
# silently returned Empty() for every other Location subtype was indistinguishable from "this location
# holds a Stock and it happens to be empty," which is misleading for types (GenericLocation/Labware/
# Instrument) that structurally can never hold one at all. Calling stock() on those now throws
# MethodError, matching wellcapacity/withdraw!/deposit!/check_capacity (all Well-only, no fallback).

"""
    location_id(x::Location)

Access the `location_id` property of a location. `nothing` by default -- every `Location` is a
normal, complete in-memory object with or without one; a `location_id` only appears once `x` has
been committed to a database (see [`is_committed`](@ref)).
"""
location_id(x::Location)=x.location_id

"""
    is_committed(x::Location)

Return `true` if `x` has a `location_id` — it has been committed to a database and is tracked
there. Most `Location`s never need to be: this is the exceptional case, not the default one.
"""
is_committed(x::Location) = !isnothing(location_id(x))

"""
    assert_all_committed(args...)

Throw [`UncommittedLocationError`](@ref) if any `Location` among `args` is not committed to a
database (see [`is_committed`](@ref)) — an operation that writes to the database needs every
location involved to already have a `location_id`.
"""
function assert_all_committed(args...)
    for a in args
        if a isa Location && !is_committed(a)
            throw(UncommittedLocationError(a))
        end
    end
    return nothing
end

"""
    kind(x::Location)

Access the [`LocationKind`](@ref) of a location.
"""
kind(x::Location)=x.kind

"""
    shape(x::Location)
Access the grid shape of a location's [`LocationKind`](@ref), if defined. `(0,0)` otherwise.
"""
shape(x::Location) = something(kind(x).shape,(0,0))
"""
    vendor(x::Location)
Access the `vendor` property of a location's [`LocationKind`](@ref), if defined.
"""
vendor(x::Location)=kind(x).vendor
"""
    catalog(x::Location)
Access the `catalog` property of a location's [`LocationKind`](@ref), if defined.
"""
catalog(x::Location)=kind(x).catalog

"""
    name(x::Location)
Access the `name` property of a location. The name of a location does not need to be unique and can be used for display purposes.
"""
name(x::Location)=x.name

"""
    attributes(x::Location)
Access the `attributes` property of a location.
"""
attributes(x::Location)=x.attributes

"""
    reads(x::Location)

Access the full `reads` collection of a location -- every [`Read`](@ref) ever recorded for it (see
[`record_read!`](@ref)), in whatever order they were recorded. Unlike [`attributes`](@ref), this is
never overwritten -- many independent reads of the same [`ReadKind`](@ref) can coexist.
"""
reads(x::Location)=x.reads

_read_sort_key(r::Read) = something(read_time(r),typemin(DateTime))

"""
    reads(x::Location, kind::ReadKind)
    reads(x::Location, name::Symbol)

Return `x`'s reads of a single [`ReadKind`](@ref) (by the kind itself, or by its `name`), sorted by
[`read_time`](@ref) (reads with no recorded time sort first) -- directly usable as a time series,
regardless of the underlying collection's insertion order.
"""
reads(x::Location,kind::ReadKind) = sort(filter(r -> read_kind(r) === kind,reads(x));by=_read_sort_key)
reads(x::Location,name::Symbol) = sort(filter(r -> read_kind(r).name === name,reads(x));by=_read_sort_key)

"""
    is_locked(x::Location)

Access the state of the `is_locked` property of a location. Locked locations cannot be moved from their current parent, but *children of locked locations can be moved*.

See also: [`unlock!`](@ref),[`lock!`](@ref),[`toggle_lock!`](@ref),[`unlock`](@ref),[`lock`](@ref),[`toggle_lock`](@ref).
"""
is_locked(x::Location)=x.is_locked # locked locations cannot be moved from their current parent. Children of locked locations CAN be moved.

"""
    unlock!(x::Location)
Change the state of the `is_locked` property of a location to `false`.

See also: [`is_locked`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function unlock!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_locked=false
end

"""
    lock!(x::Location)
Change the state of the `is_locked` property of a location to `true`.

See also: [`is_locked`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function lock!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_locked=true
end

"""
    toggle_lock!(x:Location)

Flip the state of the `is_locked` property of a location.

See also: [`is_locked`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function toggle_lock!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_locked=!is_locked(x)
end

"""
    is_active(x::Location)

Access the `is_active` property of a location


See also: [`activate!`](@ref), [`deactivate!`](@ref), [`toggle_activity!`](@ref)
"""
function is_active(x::Location)
    return x.is_active
end


"""
    activate!(x::Location)

Set the `is_active` property of [`Location`](@ref) `x` to `true`

See also: [`is_active`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function activate!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_active=true
end
"""
    deactivate!(x::Location)

Set the `is_active` property of [`Location`](@ref) `x` to `false`

See also: [`is_active`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function deactivate!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_active=false
end

"""
    toggle_activity!(x::Location)

Switch the `is_active` property of [`Location`](@ref) `x` from its current state.

See also: [`is_active`](@ref). To preview this without mutating `x`, see
[`reconstruct_location`](@ref)/[`build_location`](@ref).
"""
function toggle_activity!(x::Location;instrument::Union{Location,Nothing}=nothing)
    x.is_active=!is_active(x)
end

cost(::Location)=0 # refers to the cost of the contents of a location. cost is implemented for Well but needs to be defined for all locations.

"""
    mutable struct GenericLocation <: Location

The concrete [`Location`](@ref) subtype for locations with mutable, heterogeneous membership over
time (rooms, incubators, drawers, ...) — as opposed to [`Labware`](@ref) (fixed grid) or [`Well`](@ref)
(terminal leaf). Every distinct kind (`:Room`, `:Incubator`, ...) is a [`LocationKind`](@ref) value
carried in `kind`, not a distinct Julia type.
"""
mutable struct GenericLocation <: Location
    const location_id::Union{Integer,Nothing}
    const name::String
    const kind::LocationKind
    parent::Union{Location,Nothing}
    children::Vector{Location}
    attributes::AttributeDict
    reads::Vector{Read}
    is_locked::Bool
    is_active::Bool
end

function GenericLocation(location_id::Union{Integer,Nothing},name::String,kind::LocationKind;
        parent::Union{Location,Nothing}=nothing,children::Vector{<:Location}=Location[],
        attributes::AttributeDict=AttributeDict(),reads::Vector{Read}=Read[],is_locked::Bool=false,is_active::Bool=true)
    return GenericLocation(location_id,name,kind,parent,Location[children...],attributes,reads,is_locked,is_active)
end

function softequal(x::Location,y::Location)
    if typeof(x) != typeof(y)
        return false
    end
    props = setdiff(fieldnames(typeof(x)),[:parent,:children])
    return all(map(prop -> getproperty(x,prop)==getproperty(y,prop),props)) && all(map((a,b)->location_id(a)==location_id(b),ancestors(x),ancestors(y))) && all(map((x,y)->softequal(x,y),children(x),children(y)))


end

function softequal(x::Nothing,y::Nothing)

    return x == y
end


"""
    ancestors(x::Location;rev=false)

return the parent location chain of location `x` in the order of most to least proximal.

Use the keyword arg `rev=true` to reverse the order from least proximal to most proximal
"""
function ancestors(x::Location;rev=false)
    out=Location[]
    node=x
    while !AbstractTrees.isroot(node)
        push!(out,node);
        node=AbstractTrees.parent(node);
    end
    push!(out,node);
    if rev
        return reverse(out)
    else
        return out
    end
end


function Base.in(x::Location,y::Location)
    return y in ancestors(x)
end


"""
    get_all_within(loc::Location,typ::Type{<:Location})

Find and return all locations of type `typ` within loc or loc's children
"""
function get_all_within(loc::Location,typ::Type{<:Location})
    out=typ[]
    for child in children(loc)
        if child isa typ
            push!(out,child)
        end
        out=vcat(out,get_all_within(child,typ))
    end
    return out
end


function Base.show(io::IO,x::Location)
    print(io,name(x))
end

"""
    children_named(loc::Location,name::String)

Return every direct child of `loc` whose `name` matches, as a `Vector` (possibly empty). `name(x)`
is explicitly documented as non-unique, so unlike [`Base.getindex(::Location,::String)`](@ref) this
never errors — use it when duplicate names are expected and you want to handle them yourself.
"""
function children_named(loc::Location,name::String)
    return filter(c -> CHESSCore.name(c)==name, children(loc))
end

"""
    getindex(loc::Location,name::String)

Look up the unique direct child of `loc` named `name`. Throws [`ChildNotFoundError`](@ref) if no
child matches, or [`AmbiguousChildNameError`](@ref) if more than one does — `name` is not guaranteed
unique (see [`children_named`](@ref) for the non-throwing, plural alternative). There is
deliberately no integer `getindex` for a generic `Location`: unlike [`Labware`](@ref)'s fixed grid,
`children` is a mutable `Vector` with no stable positional identity.
"""
function Base.getindex(loc::Location,name::String)
    matches = children_named(loc,name)
    length(matches)==0 && throw(ChildNotFoundError(loc,name))
    length(matches)>1 && throw(AmbiguousChildNameError(loc,name,matches))
    return only(matches)
end


function location_id(::Nothing)
    return nothing
end

is_active(::Nothing)=false
is_locked(::Nothing)=false
