# Reads & Instrument Measurements

```@meta
DocTestSetup = :(using CHESS)
```

## Registering what an instrument can measure

A [`ReadKind`](@ref) is either quantitative (unit-bearing) or qualitative (string-valued, optionally
constrained to a fixed set of values), registered with [`@read`](@ref) (mirrors
[`@attribute`](@ref)/[`@location_kind`](@ref)):

```jldoctest reads
julia> @read Conductivity u"mS/cm"
ReadKind(Conductivity)

julia> Conductivity(1.2u"mS/cm")
1.2 mS cm⁻¹
```

`using CHESS` registers the read kinds its supported instruments produce, such as `Absorbance`.
Recall a registered kind collision-safely with [`@read_str`](@ref):

```jldoctest reads
julia> read"Absorbance"(0.9u"OD")
0.9 OD
```

## Recording a read

[`record_read!(loc, read; instrument=nothing)`](@ref) appends a [`Read`](@ref) to a location's
collection. Here the location is well A1 of a new plate:

```jldoctest reads
julia> using Dates

julia> a1 = build_location(loc"WP96", "Plate 1")["A1"];

julia> record_read!(a1, read"Absorbance"(0.47u"OD", DateTime(2026,1,1,9,30)))

julia> record_read!(a1, read"Absorbance"(0.42u"OD", DateTime(2026,1,1,9,0)))

julia> reads(a1, read"Absorbance")
2-element Vector{Read}:
 0.42 OD
 0.47 OD
```

Unlike [`Attribute`](@ref)'s single overwritable slot per kind, [`reads(x)`](@ref) is insertion
order and never overwritten -- many reads of the same kind coexist. Filtering to one kind via
`reads(x, kind_or_name)` sorts by [`read_time`](@ref) instead, making it a usable time series
regardless of recording order.

## Qualitative reads

Constrained (categorical) and free-text qualitative kinds, contrasted directly:

```jldoctest reads
julia> @read Observation
ReadKind(Observation)

julia> @read ColorimetricResult nothing Set(["Positive","Negative"])
ReadKind(ColorimetricResult)

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

```jldoctest reads
julia> read"Absorbance"(Unknown)
Unknown

julia> read"Absorbance"(missing)
missing
```

## Instrument capability gating

There is no dedicated `Instrument` type -- an instrument is a `GenericLocation` or `Labware`
(whichever fits its physical shape) whose `LocationKind` is flagged `is_instrument`, carrying the
per-model capability data ([`performable_operations`](@ref), [`actuatable_attributes`](@ref),
[`readable_types`](@ref)). `record_read!`'s optional `instrument` keyword
routes the call through `_check_capability`: it does nothing when `instrument` is omitted (the
default), otherwise the instrument must have the calling operation in its `performable_operations`
or the call throws `ArgumentError`. CHESS's `Epoch2` plate reader lists `record_read!`; its
`Autoclave` does not:

```jldoctest reads
julia> reader = build_location(loc"Epoch2", "Reader 1");

julia> autoclave = build_location(loc"Autoclave", "Autoclave 1");

julia> record_read!(a1, read"Absorbance"(0.5u"OD"); instrument=reader)

julia> record_read!(a1, read"Absorbance"(0.5u"OD"); instrument=autoclave)
ERROR: ArgumentError: Autoclave 1 cannot perform record_read!
```

This check only asks whether `record_read!` is allowed at all -- `readable_types` is descriptive
`LocationKind` data only, not enforced here. A plate reader could record any registered `ReadKind`
through this gate, not just the ones listed in its own `readable_types`.
