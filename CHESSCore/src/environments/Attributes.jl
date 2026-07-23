
"""
    struct UnknownValue end

Sentinel type for an attribute value that is actively indeterminate (e.g. a broken sensor), as
distinct from `missing` ("no local opinion, defer to an ancestor's value"). Use the singleton
[`Unknown`](@ref).

See also: [`isunknown`](@ref)
"""
struct UnknownValue end

"""
    const Unknown = UnknownValue()

Singleton representing an actively-indeterminate attribute value. Unlike `missing`, an `Unknown`
value is inserted into a computed [`environment`](@ref) and propagates/overrides like a normal value
— it asserts "unknown here" down to descendants, rather than silently deferring to an ancestor.
"""
const Unknown = UnknownValue()

"""
    isunknown(x::Attribute)

Return `true` if `x`'s value is the [`Unknown`](@ref) sentinel. Mirrors `ismissing`.
"""
isunknown(x) = x isa UnknownValue

"""
    struct AttributeKind

A named, interned, immutable value describing a *kind* of environmental attribute (e.g.
`:Temperature`, `:Humidity`), mirroring [`LocationKind`](@ref). Registered via [`@attribute`](@ref).

Fields:
- `name`: the kind's unique identifier.
- `unit`: canonical storage unit (e.g. `u"°C"`) — values are converted to this unit on construction.
"""
struct AttributeKind
    name::Symbol
    unit::Unitful.Units
end

Base.show(io::IO,k::AttributeKind) = print(io,"AttributeKind(",k.name,")")

# AttributeKind is a named, interned, shared value -- deepcopy must never duplicate it (see the
# identical rationale on LocationKind.deepcopy_internal).
Base.deepcopy_internal(k::AttributeKind,::IdDict) = k

# per-module registry, mirrors _chemprops/_orgprops/_locationkinds
function _attributekinds(m::Module)
    attrkinds_name = Symbol("#JLIMS_attrkinds")
    if isdefined(m,attrkinds_name)
        getproperty(m,attrkinds_name)
    else
        Core.eval(m,:(const $attrkinds_name = Dict{Symbol,AttributeKind}()))
    end
end

const attribute_kinds = _attributekinds(CHESSCore)

function attributekind_expr(m::Module,n,ak)
    if m === CHESSCore
        :($(_attributekinds(CHESSCore))[$n] = $ak)
    else
        quote
            $(_attributekinds(m))[$n] = $ak
            $(_attributekinds(CHESSCore))[$n] = $ak
        end
    end
end

"""
    mutable struct Attribute

`Attribute` values define the environmental properties of [`Location`](@ref) objects. There is a
single concrete `Attribute` type for every environmental variable — the specific kind
(`Temperature`, `Humidity`, ...) is carried as data (an [`AttributeKind`](@ref)), not as a distinct
Julia type.

`value` is one of:
- a `Real`: a concrete reading, stored in `kind.unit`.
- `missing`: no local opinion — [`environment`](@ref) defers to an inherited value.
- [`Unknown`](@ref): actively indeterminate — asserts "unknown" down to descendants.
"""
mutable struct Attribute
    const kind::AttributeKind
    value::Union{Real,Missing,UnknownValue}
    function Attribute(kind::AttributeKind,value::Union{Unitful.Quantity,Missing,UnknownValue})
        val = value isa UnknownValue ? value :
              ismissing(value)       ? missing :
              Unitful.ustrip(Unitful.uconvert(kind.unit,value))
        new(kind,val)
    end
end

(k::AttributeKind)(value::Union{Unitful.Quantity,Missing,UnknownValue}) = Attribute(k,value)

"""
    value(x::Attribute)

Access the `value` property of an [`Attribute`](@ref)
"""
value(x::Attribute)=x.value

"""
    attribute_kind(x::Attribute)

Access the [`AttributeKind`](@ref) of an [`Attribute`](@ref)
"""
attribute_kind(x::Attribute)=x.kind

"""
    attribute_unit(x::Attribute)

Access the canonical unit of an [`Attribute`](@ref)
"""
attribute_unit(x::Attribute)=x.kind.unit

"""
    quantity(x::Attribute)

Return the quantity of an [`Attribute`](@ref). Returns `missing`/[`Unknown`](@ref) unchanged if the
attribute's value is `missing`/`Unknown`.
"""
function quantity(x::Attribute)
    v = value(x)
    (ismissing(v) || isunknown(v)) && return v
    return v * attribute_unit(x)
end

"""
    @attribute name unit

Define a new [`AttributeKind`](@ref) and register it under `name`, both as a `const` binding and in
the [`attribute_kinds`](@ref) registry — mirrors [`@chemical`](@ref)/[`@location_kind`](@ref).
`name` is directly callable as a constructor, e.g. `Temperature(10u"°C")`.

Example:
```julia-repl
julia> using Unitful
julia> @attribute Temperature u"°C"

julia> Temperature(10u"°C")
10.0 °C
```
See also: [`Attribute`](@ref)
"""
macro attribute(name,unit)
    n=Symbol(name)
    ln=Meta.quot(n)
    esc(quote
        haskey(CHESSCore.attribute_kinds,$ln) && throw(ArgumentError("Attribute kind $($ln) already exists"))
        const $n = CHESSCore.AttributeKind($ln,$unit)
        $(attributekind_expr(__module__,ln,n))
        $n
    end)
end

attrstr_check_bool(::AttributeKind) = true
attrstr_check_bool(::Any) = false

"""
    @attr_str(kind)

String macro to recall an [`AttributeKind`](@ref) registered with [`@attribute`](@ref) by name,
mirroring [`@loc_str`](@ref) (and sharing its lookup machinery). `@attribute` doesn't `export` the
name it defines (to avoid flooding the namespace of anyone who `using`s a lab module with dozens of
kind names), so this is the collision-safe way to look one up without needing to `using` the specific
lab module that defined it.

Example:
```julia-repl
julia> attr"Temperature"
AttributeKind(Temperature)
```
"""
macro attr_str(kind)
    # Bare Symbol lookup, not Meta.parse -- see the comment in @chem_str (Chemicals.jl) for why.
    sym = Symbol(kind)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, attrstr_check_bool))
end



Base.show(io::IO,x::Attribute;digits=2) = isunknown(value(x)) ? print(io,"Unknown") : print(io,round(quantity(x),digits=digits))

function ==(x::Attribute,y::Attribute)
    return x.kind===y.kind && quantity(x)==quantity(y)
end

function Base.hash(a::Attribute,h::UInt)
    hash(a.kind,hash(quantity(a),h))
end

const AttributeDict=Dict{Symbol,Attribute}




"""
    set_attribute!(x::AttributeDict,attribute::Attribute)

Set the value for key `attribute.kind.name` of `dict` to `attribute`.

We use this method to ensure a proper pairing between the attribute kind and the attribute in the dict.
"""
function set_attribute!(dict::AttributeDict,attribute::Attribute)
    dict[attribute.kind.name]=attribute ;
    nothing
end
