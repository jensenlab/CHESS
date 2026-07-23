


"""
    mutable struct Labware <: Location

The concrete [`Location`](@ref) subtype for a manufactured physical item with a fixed, homogeneous
grid of slots (`kind.shape`), populated once at creation by
[`generate_location`](@ref) and never restructured afterward — `add_to!`/`remove!` on a `Labware`
throw [`FixedMembershipError`](@ref). Every distinct model (`:WP96`, `:AltemisBox`, ...) is a
[`LocationKind`](@ref) value carried in `kind`, not a distinct Julia type.
"""
mutable struct Labware <: Location
    const location_id::Union{Integer,Nothing}
    const name::String
    const kind::LocationKind
    parent::Union{Location,Nothing}
    children::Matrix{Location}
    attributes::AttributeDict
    reads::Vector{Read}
    is_locked::Bool
    is_active::Bool
end

function Labware(location_id::Union{Integer,Nothing},name::String,kind::LocationKind;
        parent::Union{Location,Nothing}=nothing,
        children::Matrix{<:Location}=Matrix{Location}(undef,something(kind.shape,(0,0))...),
        attributes::AttributeDict=AttributeDict(),reads::Vector{Read}=Read[],is_locked::Bool=false,is_active::Bool=true)
    return Labware(location_id,name,kind,parent,Matrix{Location}(children),attributes,reads,is_locked,is_active)
end

# No parent_cost override here -- Labware uses the generic, kind-data-driven definition
# (Occupancy.jl) like any other Location. "A Labware's slots are fixed at creation" is enforced
# directly by add_to!(parent::Labware,...) (movement.jl), not by hijacking the occupancy-cost
# fallback -- see the comment on Well's (now-removed) equivalent override for why that mattered:
# occupancy(x) calls occupancy_cost(x,child) directly for reporting, with no movement in progress,
# so a parent_cost hack here would corrupt every Labware's reported fullness, not just gate movement.

"""
    occupancy(x::Labware)

Always `1//1` -- a `Labware`'s children (`kind.shape` wells) are populated exactly once at
construction and can never change (`add_to!`/`remove!` throw `FixedMembershipError`), so there is no
"how full" question to answer the way there is for `GenericLocation`/`Instrument`. Mirrors
`occupancy(::Well)` (Well.jl), which is fully-occupied for the same reason (fixed contents, no
partial-membership state).
"""
occupancy(::Labware) = 1//1

"""
    childtype(x::Labware)

Return the concrete [`Location`](@ref) subtype (see [`concretetype`](@ref)) that fills each of `x`'s
grid slots, per `x.kind.socket`.
"""
function childtype(x::Labware)
    isnothing(kind(x).socket) && return Location
    return concretetype(location_kinds[kind(x).socket])
end

wells(x::Labware) = children(x)

# Ergonomic array-like indexing forwarding to the underlying children Matrix. Deliberately no
# Base.setindex! (slot membership is fixed, see FixedMembershipError) and no AbstractArray
# subtyping (would pull in push!/resize!/broadcasting semantics that don't apply to a fixed grid).
Base.getindex(lw::Labware, i, j) = children(lw)[i, j]
Base.getindex(lw::Labware, i::Int) = children(lw)[i]
Base.size(lw::Labware) = shape(lw)
Base.length(lw::Labware) = prod(shape(lw))
Base.eachindex(lw::Labware) = eachindex(children(lw))
Base.iterate(lw::Labware, state...) = iterate(children(lw), state...)
