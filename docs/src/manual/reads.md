# Reads & Instrument Measurements

## Registering what an instrument can measure

A [`ReadKind`](@ref) is either quantitative (unit-bearing) or qualitative (string-valued, optionally
constrained to a fixed set of values), registered with [`@read`](@ref) (mirrors
[`@attribute`](@ref)/[`@location_kind`](@ref)):

```julia
@read Absorbance u"OD"
```

```julia-repl
julia> Absorbance(90u"OD")
90.0 OD
```

Recalled collision-safely with [`@read_str`](@ref): `read"Absorbance"`.

## Recording a read

[`record_read!(loc, read; instrument=nothing)`](@ref) appends a [`Read`](@ref) to a location's
collection, continuing `a1` (the well from [Wells](wells.md)):

```julia-repl
julia> record_read!(a1, Absorbance(0.47u"OD", DateTime(2026,1,1,9,30)))

julia> record_read!(a1, Absorbance(0.42u"OD", DateTime(2026,1,1,9,0)))

julia> reads(a1, Absorbance)
Read[0.42 OD, 0.47 OD]
```

Unlike [`Attribute`](@ref)'s single overwritable slot per kind, [`reads(x)`](@ref) is insertion
order and never overwritten -- many reads of the same kind coexist. Filtering to one kind via
`reads(x, kind_or_name)` sorts by [`read_time`](@ref) instead, making it a usable time series
regardless of recording order.

## Qualitative reads

Constrained (categorical) and free-text qualitative kinds, contrasted directly:

```julia
@read Observation
@read ColorimetricResult nothing Set(["Positive","Negative"])
```

```julia-repl
julia> Observation("looked a bit cloudy")
looked a bit cloudy

julia> ColorimetricResult("Positive")
Positive

julia> ColorimetricResult("Maybe")
ERROR: ArgumentError: "Maybe" is not an allowed value for ColorimetricResult; allowed: Set(["Negative", "Positive"])
```

## `Unknown` and `missing`

The same contrast already established for [`Attribute`](@ref) in [Environmental Attributes &
Inheritance](attributes.md) applies to reads: `missing` means no reading was attempted or the
location was out of scope; `Unknown` means one was attempted but came back indeterminate (a sensor
fault, a saturation error):

```julia-repl
julia> Absorbance(CHESSCore.Unknown)
Unknown

julia> Absorbance(missing)
missing
```

## `Instrument`s and capability gating

There is a single concrete `Instrument` type for every instrument model -- per-model capability is
data on its [`LocationKind`](@ref) ([`performable_operations`](@ref), [`actuatable_attributes`](@ref),
[`readable_types`](@ref)), not a distinct Julia type. `record_read!`'s optional `instrument` keyword
routes the call through `_check_capability`: it does nothing when `instrument` is omitted (the
default), otherwise the instrument must have the calling operation in its `performable_operations`
or the call throws `ArgumentError`:

```julia
@location_kind PlateReader Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}([record_read!]) Set([:Absorbance]) true
@location_kind Autoclave   Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}() Set{Symbol}() true
```

```julia-repl
julia> reader = build_location(loc"PlateReader", "Reader 1")

julia> autoclave = build_location(loc"Autoclave", "Autoclave 1")

julia> record_read!(a1, Absorbance(0.5u"OD"); instrument=reader)

julia> record_read!(a1, Absorbance(0.5u"OD"); instrument=autoclave)
ERROR: ArgumentError: Autoclave 1 cannot perform record_read!
```

This check only asks whether `record_read!` is allowed at all -- `readable_types` (`{:Absorbance}`
above) is descriptive `LocationKind` data only, not enforced here. A `PlateReader` could record any
registered `ReadKind` through this gate, not just the ones listed in its own `readable_types`.
