
"""
    struct LocationKind

`LocationKind` is a named, interned, immutable value describing a *kind* of location or labware
(e.g. `:Room`, `:Incubator`, `:WP96`, `:AltemisBox`, `:Well200`). It replaces minting a new concrete
Julia type per kind — every [`Location`](@ref)/[`Labware`](@ref)/[`Well`](@ref) instance carries a
*reference* to a shared `LocationKind` value rather than duplicating its descriptive data.

Fields:
- `name`: the kind's unique identifier.
- `categories`: flat, ordered tags used for occupancy-rule resolution (no chaining/hierarchy).
- `shape`: grid shape (rows, cols) if this kind is `Labware`-like; `nothing` otherwise.
- `socket`: the `LocationKind` name filling each grid slot, if `shape` is set.
- `capacity`: well volume capacity if this kind is `Well`-like; `nothing` otherwise.
- `vendor`/`catalog`: descriptive product data, if applicable.
- `default_parent_cost`/`default_child_cost`: fallback occupancy costs used when no specific or
  category-based [`occupancy_cost`](@ref) rule applies.
- `actuatable_attributes`: names of [`AttributeKind`](@ref)s this kind's [`Instrument`](@ref) is
  associated with -- descriptive only, not enforced; empty for non-instrument kinds.
- `performable_operations`: mutating operation functions (e.g. `move_into!`, `transfer!`,
  `set_attribute!`) this kind's instrument can perform on *other* locations; empty for non-instrument
  kinds.
- `readable_types`: names of [`ReadKind`](@ref)s this kind's instrument can produce; empty for
  non-instrument kinds.
- `is_instrument`: whether this kind's [`concretetype`](@ref) is [`Instrument`](@ref).

See also: [`concretetype`](@ref), [`@location_kind`](@ref), [`@loc_str`](@ref)
"""
struct LocationKind
    name::Symbol
    categories::Vector{Symbol}
    shape::Union{Tuple{Int,Int},Nothing}
    socket::Union{Symbol,Nothing}
    capacity::Union{Unitful.Volume,Nothing}
    vendor::Union{String,Nothing}
    catalog::Union{String,Nothing}
    default_parent_cost::Rational
    default_child_cost::Rational
    actuatable_attributes::Set{Symbol}
    performable_operations::Set{Function}
    readable_types::Set{Symbol}
    is_instrument::Bool
end

function LocationKind(name::Symbol;
        categories::Vector{Symbol}=Symbol[],
        shape::Union{Tuple{Int,Int},Nothing}=nothing,
        socket::Union{Symbol,Nothing}=nothing,
        capacity::Union{Unitful.Volume,Nothing}=nothing,
        vendor::Union{String,Nothing}=nothing,
        catalog::Union{String,Nothing}=nothing,
        default_parent_cost::Rational=0//1,
        default_child_cost::Rational=0//1,
        actuatable_attributes::Set{Symbol}=Set{Symbol}(),
        performable_operations::Set{Function}=Set{Function}(),
        readable_types::Set{Symbol}=Set{Symbol}(),
        is_instrument::Bool=false)
    return LocationKind(name,categories,shape,socket,capacity,vendor,catalog,default_parent_cost,default_child_cost,actuatable_attributes,performable_operations,readable_types,is_instrument)
end

Base.show(io::IO,k::LocationKind) = print(io,"LocationKind(",k.name,")")

# LocationKind is a named, interned, shared value (see module docstring) -- deepcopy (used by
# lock/unlock/transfer/etc. to produce non-mutating copies of a Location) must never duplicate it,
# or every "copy" would silently stop sharing its kind with every other instance of that kind.
Base.deepcopy_internal(k::LocationKind,::IdDict) = k

"""
    concretetype(k::LocationKind)

Return the concrete Julia type ([`Instrument`](@ref), [`Well`](@ref), [`Labware`](@ref), or
[`GenericLocation`](@ref)) that a `LocationKind` produces: `Instrument` if `is_instrument` is set,
`Well` if `capacity` is set, `Labware` if `shape` is set, `GenericLocation` otherwise.
"""
function concretetype(k::LocationKind)
    k.is_instrument && return Instrument
    return !isnothing(k.capacity) ? Well :
           !isnothing(k.shape)    ? Labware : GenericLocation
end

# per-module registry, mirrors _chemprops/_orgprops (src/CHESSCore.jl)
function _locationkinds(m::Module)
    lockinds_name = Symbol("#JLIMS_lockinds")
    if isdefined(m,lockinds_name)
        getproperty(m,lockinds_name)
    else
        Core.eval(m,:(const $lockinds_name = Dict{Symbol,LocationKind}()))
    end
end

const location_kinds = _locationkinds(CHESSCore)

function locationkind_expr(m::Module,n,ls)
    if m === CHESSCore
        :($(_locationkinds(CHESSCore))[$n] = $ls)
    else
        quote
            $(_locationkinds(m))[$n] = $ls
            $(_locationkinds(CHESSCore))[$n] = $ls
        end
    end
end

"""
    @location_kind labsymb categories shape socket capacity vendor catalog [default_parent_cost] [default_child_cost]

Define a new [`LocationKind`](@ref) and register it under `labsymb`, both as a `const` binding (so it
can be used directly, e.g. `WP96`) and in the [`location_kinds`](@ref) registry (so it can be looked
up by name, e.g. for database reconstruction).

Example:
```julia-repl
julia> @location_kind WP96 [:Plate] (8,12) :Well200 nothing "Thermo" "123456"
WP96
```
"""
macro location_kind(labsymb,categories,shape,socket,capacity,vendor,catalog,default_parent_cost=0//1,default_child_cost=0//1,actuatable_attributes=Set{Symbol}(),performable_operations=Set{Function}(),readable_types=Set{Symbol}(),is_instrument=false)
    ls = Symbol(labsymb)
    ln = Meta.quot(ls)
    esc(quote
        haskey(CHESSCore.location_kinds,$ln) && throw(ArgumentError("LocationKind $($ln) already exists"))
        const $ls = CHESSCore.LocationKind($ln;categories=$categories,shape=$shape,socket=$socket,capacity=$capacity,vendor=$vendor,catalog=$catalog,default_parent_cost=$default_parent_cost,default_child_cost=$default_child_cost,actuatable_attributes=$actuatable_attributes,performable_operations=$performable_operations,readable_types=$readable_types,is_instrument=$is_instrument)
        $(locationkind_expr(__module__,ln,ls))
        $ls
    end)
end

locstr_check_bool(::LocationKind) = true
locstr_check_bool(::Any) = false

"""
    @loc_str(kind)

String macro to recall a [`LocationKind`](@ref) registered with [`@location_kind`](@ref) by name,
mirroring [`@chem_str`](@ref)/[`@org_str`](@ref) (and sharing their lookup machinery).

`loc"WP96"` is a **pure lookup** — it never allocates a new physical instance or touches the
database. Actual instantiation stays an explicit call, e.g. `generate_location(loc"WP96", "Plate 1")`.

Example:
```julia-repl
julia> loc"WP96"
LocationKind(WP96)
```
"""
macro loc_str(kind)
    # Bare Symbol lookup, not Meta.parse -- see the comment in @chem_str (Chemicals.jl) for why.
    sym = Symbol(kind)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, locstr_check_bool))
end
