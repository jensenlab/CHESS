
"""
    struct ReadKind

A named, interned, immutable value describing a *kind* of instrument measurement (e.g.
`:Absorbance`, `:ColorimetricResult`), mirroring [`AttributeKind`](@ref)/[`LocationKind`](@ref).
Registered via [`@read`](@ref).

A `ReadKind` is either **quantitative** or **qualitative** — mode is data, not a distinct type
(mirroring how `LocationKind` avoids a type per kind):
- Quantitative: `unit` is set (e.g. `u"percent"`) — values are `Real`, converted to `unit` on
  construction. See [`is_quantitative`](@ref).
- Qualitative: `unit` is `nothing` — values are `String`. `allowed_values`, if set, constrains them to
  a fixed enumerated set (e.g. a colorimetric result); if `nothing`, any string is accepted (free-text
  observation). See [`is_qualitative`](@ref).

Fields:
- `name`: the kind's unique identifier.
- `unit`: canonical storage unit for a quantitative kind; `nothing` for a qualitative kind.
- `allowed_values`: the fixed set of valid strings for a constrained qualitative kind; `nothing` for a
  quantitative kind, or for an unconstrained (free-text) qualitative kind.
"""
struct ReadKind
    name::Symbol
    unit::Union{Unitful.Units,Nothing}
    allowed_values::Union{Set{String},Nothing}
end

"""
    is_quantitative(k::ReadKind)

Return `true` if `k` is a quantitative (unit-bearing) kind.
"""
is_quantitative(k::ReadKind) = !isnothing(k.unit)

"""
    is_qualitative(k::ReadKind)

Return `true` if `k` is a qualitative (string-valued) kind.
"""
is_qualitative(k::ReadKind) = isnothing(k.unit)

Base.show(io::IO,k::ReadKind) = print(io,"ReadKind(",k.name,")")

# ReadKind is a named, interned, shared value -- deepcopy must never duplicate it (see the identical
# rationale on AttributeKind.deepcopy_internal/LocationKind.deepcopy_internal).
Base.deepcopy_internal(k::ReadKind,::IdDict) = k

# per-module registry, mirrors _attributekinds/_locationkinds
function _readkinds(m::Module)
    readkinds_name = Symbol("#JLIMS_readkinds")
    if isdefined(m,readkinds_name)
        getproperty(m,readkinds_name)
    else
        Core.eval(m,:(const $readkinds_name = Dict{Symbol,ReadKind}()))
    end
end

const read_kinds = _readkinds(CHESSCore)

function readkind_expr(m::Module,n,rk)
    if m === CHESSCore
        :($(_readkinds(CHESSCore))[$n] = $rk)
    else
        quote
            $(_readkinds(m))[$n] = $rk
            $(_readkinds(CHESSCore))[$n] = $rk
        end
    end
end

"""
    struct Read

`Read` values represent a single instrument measurement of a [`Location`](@ref) — the specific kind
(`Absorbance`, `Fluorescence`, ...) is carried as data (a [`ReadKind`](@ref)), not as a distinct Julia
type, mirroring [`Attribute`](@ref). Unlike `Attribute`, `Read` is immutable: nothing ever edits a
`Read` in place, since many independent `Read`s of the same `ReadKind` can coexist for the same
location at once (as opposed to `Attribute`'s single-slot-per-kind, overwritable semantics) — see
[`reads`](@ref)/[`record_read!`](@ref).

`value` is one of:
- a `Real` (quantitative kinds only): a concrete measurement, stored in `kind.unit`.
- a `String` (qualitative kinds only): a categorical result or free-text observation, validated
  against `kind.allowed_values` if that's set.
- [`Unknown`](@ref): the instrument attempted this read and got an indeterminate/invalid result
  (sensor error, saturation, timeout).
- `missing`: this location was in scope for a batch of reads but produced no result (e.g. masked out
  of a plate scan) — distinct from never having attempted a read at all.

`time` is the instrument's own recorded time for this read (`nothing` if unknown/unavailable) — kept
as data only, never compared across different instruments. See [`read_time`](@ref).
"""
struct Read
    kind::ReadKind
    value::Union{Real,String,Missing,UnknownValue}
    time::Union{DateTime,Nothing}
    function Read(kind::ReadKind,value::Union{Unitful.Quantity,AbstractString,Missing,UnknownValue},time::Union{DateTime,Nothing}=nothing)
        if value isa UnknownValue
            val = value
        elseif ismissing(value)
            val = missing
        elseif is_quantitative(kind)
            value isa Unitful.Quantity || throw(ArgumentError("$(kind.name) is quantitative -- expected a Quantity, got a $(typeof(value))"))
            val = Unitful.ustrip(Unitful.uconvert(kind.unit,value))
        else
            value isa AbstractString || throw(ArgumentError("$(kind.name) is qualitative -- expected a String, got a $(typeof(value))"))
            isnothing(kind.allowed_values) || value in kind.allowed_values ||
                throw(ArgumentError("\"$value\" is not an allowed value for $(kind.name); allowed: $(kind.allowed_values)"))
            val = String(value)
        end
        new(kind,val,time)
    end
end

(k::ReadKind)(value::Union{Unitful.Quantity,AbstractString,Missing,UnknownValue},time::Union{DateTime,Nothing}=nothing) = Read(k,value,time)

"""
    value(x::Read)

Access the `value` property of a [`Read`](@ref). Mirrors `value(x::Attribute)`.
"""
value(x::Read) = x.value

"""
    read_kind(x::Read)

Access the [`ReadKind`](@ref) of a [`Read`](@ref). Mirrors [`attribute_kind`](@ref).
"""
read_kind(x::Read) = x.kind

"""
    read_unit(x::Read)

Access the canonical unit of a [`Read`](@ref). Mirrors [`attribute_unit`](@ref).
"""
read_unit(x::Read) = x.kind.unit

"""
    read_time(x::Read)

Access the instrument's own recorded time for a [`Read`](@ref), or `nothing` if unavailable. Named to
avoid colliding with `Base.time`.
"""
read_time(x::Read) = x.time

"""
    quantity(x::Read)

Return the quantity of a [`Read`](@ref). Returns `missing`/[`Unknown`](@ref) unchanged if the read's
value is `missing`/`Unknown`. For a qualitative read, there's no unit to attach -- returns the raw
`String` value as-is. Mirrors `quantity(x::Attribute)`.
"""
function quantity(x::Read)
    v = value(x)
    (ismissing(v) || isunknown(v)) && return v
    isnothing(read_unit(x)) && return v
    return v * read_unit(x)
end

Base.show(io::IO,x::Read;digits=2) = isunknown(value(x)) ? print(io,"Unknown") :
    ismissing(value(x)) ? print(io,"missing") :
    is_qualitative(read_kind(x)) ? print(io,value(x)) : print(io,round(quantity(x),digits=digits))

function ==(x::Read,y::Read)
    return x.kind===y.kind && quantity(x)==quantity(y) && x.time==y.time
end

function Base.hash(r::Read,h::UInt)
    hash(r.kind,hash(quantity(r),hash(r.time,h)))
end

"""
    @read name unit=nothing allowed_values=nothing

Define a new [`ReadKind`](@ref) and register it under `name`, both as a `const` binding and in the
[`read_kinds`](@ref) registry — mirrors [`@attribute`](@ref). `name` is directly callable as a
constructor, e.g. `Absorbance(0.9u"percent")` or `ColorimetricResult("Positive")`.

Examples:
```julia-repl
julia> using Unitful
julia> @read Absorbance u"percent"       # quantitative
julia> Absorbance(90u"percent")
90.0 %

julia> @read Observation                 # qualitative, free text
julia> Observation("looked a bit cloudy")

julia> @read ColorimetricResult nothing Set(["Positive","Negative"])  # qualitative, constrained
julia> ColorimetricResult("Positive")
```
See also: [`Read`](@ref)
"""
macro read(name,unit=nothing,allowed_values=nothing)
    n=Symbol(name)
    ln=Meta.quot(n)
    esc(quote
        haskey(CHESSCore.read_kinds,$ln) && throw(ArgumentError("Read kind $($ln) already exists"))
        const $n = CHESSCore.ReadKind($ln,$unit,$allowed_values)
        $(readkind_expr(__module__,ln,n))
        $n
    end)
end

readstr_check_bool(::ReadKind) = true
readstr_check_bool(::Any) = false

"""
    @read_str(kind)

String macro to recall a [`ReadKind`](@ref) registered with [`@read`](@ref) by name, mirroring
[`@loc_str`](@ref)/[`@attr_str`](@ref) (and sharing their lookup machinery). `@read` doesn't `export`
the name it defines (to avoid flooding the namespace of anyone who `using`s a lab module with dozens
of kind names), so this is the collision-safe way to look one up without needing to `using` the
specific lab module that defined it.

Example:
```julia-repl
julia> read"Absorbance"
ReadKind(Absorbance)
```
"""
macro read_str(kind)
    # Bare Symbol lookup, not Meta.parse -- see the comment in @chem_str (Chemicals.jl) for why.
    sym = Symbol(kind)
    labmods = [CHESSCore]
    for m in CHESSCore.labmodules
        if isdefined(__module__, nameof(m)) && getfield(__module__, nameof(m)) === m
            push!(labmods, m)
        end
    end
    esc(lookup_named_value(labmods, sym, readstr_check_bool))
end
