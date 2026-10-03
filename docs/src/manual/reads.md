# Reads & Instrument Measurements

```@meta
DocTestSetup = :(using CHESS)
```

## Registering what an instrument can measure

A [`ReadKind`](@ref) is either quantitative, with units, or qualitative, with string values that can
be limited to a fixed set. [`@read`](@ref) registers one, as [`@attribute`](@ref) and
[`@location_kind`](@ref) do for their kinds:

```jldoctest reads
julia> @read Conductivity u"mS/cm"
ReadKind(Conductivity)

julia> Conductivity(1.2u"mS/cm")
1.2 mS cm⁻¹
```

CHESS already includes the read kinds that its supported instruments produce, such as
`Absorbance`. [`@read_str`](@ref) recalls a registered kind by name:

```jldoctest reads
julia> read"Absorbance"(0.9u"OD")
0.9 OD
```

## Recording a read

[`record_read!(loc, read; instrument=nothing)`](@ref) appends a [`Read`](@ref) to a location's
collection of reads. The example records reads on well A1 of a new plate:

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

A location holds one [`Attribute`](@ref) per kind, which a new value overwrites. Reads are never
overwritten, so many reads of the same kind coexist. [`reads(x)`](@ref) returns them in the order
they were recorded. Passing a kind or its name, as in `reads(x, kind_or_name)`, returns only that
kind, sorted by [`read_time`](@ref), which gives a time series whatever the recording order.

## Qualitative reads

A qualitative kind is either free text or limited to a fixed set of values:

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

[`is_quantitative`](@ref) and [`is_qualitative`](@ref) tell the two kinds apart, and
[`read_unit`](@ref) returns the canonical unit of a quantitative read:

```jldoctest reads
julia> is_quantitative(Conductivity), is_qualitative(Conductivity)
(true, false)

julia> is_quantitative(ColorimetricResult), is_qualitative(ColorimetricResult)
(false, true)

julia> read_unit(Conductivity(1.2u"mS/cm"))
mS cm⁻¹
```

## `Unknown` and `missing`

As with an [`Attribute`](@ref) (see [Environmental Attributes & Inheritance](attributes.md)),
`missing` means that no reading was attempted or the location was out of scope. `Unknown` means
that a reading was attempted but came back indeterminate, for example from a sensor fault or a
saturation error:

```jldoctest reads
julia> read"Absorbance"(Unknown)
Unknown

julia> read"Absorbance"(missing)
missing
```

## Instrument capability gating

CHESS has no separate instrument type. An instrument is a `GenericLocation` or `Labware`, whichever
fits its physical shape, whose `LocationKind` is flagged `is_instrument`. The kind carries the
capability data for the model: [`performable_operations`](@ref), [`actuatable_attributes`](@ref),
and [`readable_types`](@ref).

The optional `instrument` keyword of `record_read!` checks capability. With no instrument, nothing
is checked. With an instrument, its `performable_operations` must include `record_read!`, or the
call throws `ArgumentError`. CHESS's `Epoch2` plate reader lists `record_read!`, and its
`Autoclave` does not:

```jldoctest reads
julia> reader = build_location(loc"Epoch2", "Reader 1");

julia> autoclave = build_location(loc"Autoclave", "Autoclave 1");

julia> record_read!(a1, read"Absorbance"(0.5u"OD"); instrument=reader)

julia> record_read!(a1, read"Absorbance"(0.5u"OD"); instrument=autoclave)
ERROR: ArgumentError: Autoclave 1 cannot perform record_read!
```

[`is_capable`](@ref) reports whether a location, or a location kind, is capability-bearing. It does
not depend on the type of the location. The plate reader is capable and a plate is not:

```jldoctest reads
julia> is_capable(reader), is_capable(a1)
(true, false)
```

The check asks only whether the instrument may perform `record_read!`. The `readable_types` field
is descriptive and is not enforced, so a plate reader can record any registered `ReadKind`, not
only the ones in its own `readable_types`.
