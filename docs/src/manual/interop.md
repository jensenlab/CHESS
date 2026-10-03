# Interop

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSCore` has two data-interchange formats. The tabular format, with [`stock_to_df`](@ref),
[`df_to_stock`](@ref), and their labware counterparts, holds flat batches of stock definitions, such
as a wet-lab CSV template. The general format, with [`location_to_dict`](@ref) and
[`dict_to_location`](@ref), holds a whole `Location` or tree of locations with full fidelity, for
tools outside CHESS and outside Julia.

## The tabular format

The format has two variants, "q" and "vc". Both encode only the stock columns of a table. The other
columns, `labware`, `name`, and `well` in a labware table, place the stock and are not part of the
format.

In the **"q" (quantity)** variant, each reagent column is an absolute quantity: a mass, a volume, or
a molar amount. It is exact and does not depend on the stock having a total. The examples pass
`reagent_context` so that reagent names resolve against the registered reagents of CHESS (see
[Reagent columns](#Reagent-columns-must-match-a-registered-name)):

```jldoctest interop
julia> ctx = [CHESSCore, CHESSLabConstants];

julia> bottle = build_location(loc"Bottle500mL", "Bottle 1");

julia> deposit!(bottle.children[1,1], 10u"g" * rgt"paba", 5)

julia> df_q, units_q = labware_to_df(bottle, "q"; reagent_context=ctx);

julia> df_q
1×4 DataFrame
 Row │ labware      name      well    paba
     │ String       String    String  Int64
─────┼──────────────────────────────────────
   1 │ Bottle500mL  Bottle 1  A1         10

julia> lws_q = df_to_labware(df_q, units_q; reagent_context=ctx);

julia> stock(lws_q[1][df_q.well[1]]) == stock(bottle.children[1,1])
true

julia> CHESSCore.is_committed(lws_q[1])
false
```

The **"vc" (volume/concentration)** variant has a `"volume"` column and one relative-concentration
column for each reagent. It suits a wet-lab template written by a person, which gives the total
volume and the percent, molarity, or g/mL of each reagent. It requires a stock with a defined total
quantity to relate the concentrations to:

```jldoctest interop
julia> bottle2 = build_location(loc"Bottle500mL", "Bottle 2");

julia> deposit!(bottle2.children[1,1], 100u"mL" * rgt"water", 5)

julia> df_vc, units_vc = labware_to_df(bottle2, "vc"; reagent_context=ctx);

julia> df_vc
1×5 DataFrame
 Row │ labware      name      well    volume  water
     │ String       String    String  Int64   Float64
─────┼────────────────────────────────────────────────
   1 │ Bottle500mL  Bottle 2  A1         100    100.0

julia> lws_vc = df_to_labware(df_vc, units_vc; reagent_context=ctx);

julia> stock(lws_vc[1][df_vc.well[1]]) == stock(bottle2.children[1,1])
true
```

`df_to_stock` and `df_to_labware` detect the variant from the presence of a `"volume"` column. Only
the writing functions, `stock_to_df` and `labware_to_df`, take an explicit format argument.

[`q_to_stock`](@ref) and [`vc_to_stock`](@ref) read the stock columns of a table in one variant
directly, and [`stock_to_q`](@ref) and [`stock_to_vc`](@ref) write a vector of stocks as a table and
a units table. `q_to_stock` raises an error for concentration units, and `vc_to_stock` raises an
error for quantity units:

```jldoctest interop
julia> stocks = [10u"g" * rgt"paba", 20u"g" * rgt"paba"];

julia> df, units = stock_to_q(stocks; reagent_context=ctx);

julia> df
2×1 DataFrame
 Row │ paba
     │ Int64
─────┼───────
   1 │    10
   2 │    20

julia> q_to_stock(df, units; reagent_context=ctx) == stocks
true

julia> df_vc, units_vc = stock_to_vc([100u"mL" * rgt"water"]; reagent_context=ctx);

julia> df_vc
1×2 DataFrame
 Row │ volume  water
     │ Int64   Float64
─────┼─────────────────
   1 │    100    100.0
```

### Reagent columns must match a registered name

The column header of a reagent is its registered binding name, such as `"paba"`, obtained with
`symbol(r; reagent_context)`. It is not the display name from `name(r)`, such as
`"4-aminobenzoic acid"`. The display name is used only if the symbol cannot be found in the given
`reagent_context`. The `reagent_context` must therefore be passed consistently when a stock is
converted to a DataFrame and back. If it is left out of one call, the fallback happens without a
warning. If the display name then contains spaces or punctuation that is not valid in a name, the
conversion back fails internally and produces an empty reagent with no properties instead of the
real one. CHESS logs a warning ("reagent ... not registered") and does not throw an error.

## Names and objects

Reagents, chemicals, and organisms appear in tables and in dictionaries by name.
[`reagentparse`](@ref), [`chemparse`](@ref), and [`orgparse`](@ref) are the functions behind the
string macros `rgt"..."`, `chem"..."`, and `org"..."`. They take the module or modules to search as a
keyword, which allows the context to be chosen at run time. The string macro `chem"Na+"` accepts ASCII
charge symbols, and `chemparse` needs the registered name, `Na⁺`. [`string_to_component`](@ref) converts a
name to a reagent of a given type or to an organism. It shows a warning and returns a reagent with
only a name when the name is not registered. [`component_to_string`](@ref) is the inverse. It returns
the registered name when it finds the component in the context and the display name otherwise:

```jldoctest interop
julia> reagentparse("water"; reagent_context=ctx)
water

julia> chemparse("Na⁺"; chem_context=ctx)
Na⁺

julia> orgparse("SMU_UA159"; org_context=ctx)
SMU_UA159

julia> string_to_component("water", Liquid; reagent_context=ctx)
water

julia> component_to_string(rgt"water"; reagent_context=ctx)
"water"
```

## The general format

`stock_to_dict` and `dict_to_stock` convert a `Stock` to a plain `Dict` and back. The `Dict` holds
only values that every programming language can read: `Dict`, `Vector`, `String`, `Real`, and
`Nothing`. No extra library is needed to write or read it. It has the exact-quantity shape of the
"q" variant and not the relative shape of "vc":

```jldoctest interop
julia> d = stock_to_dict(10u"g" * rgt"paba"; reagent_context=ctx);

julia> keys(d)
KeySet for a Dict{String, Any} with 3 entries. Keys:
  "organisms"
  "solids"
  "liquids"

julia> d["solids"]
Dict{String, Any} with 1 entry:
  "paba" => Dict{String, Any}("amount"=>10, "unit"=>"g")
```

[`dict_to_attribute`](@ref) and [`dict_to_read`](@ref) are the inverses of `attribute_to_dict` and
`read_to_dict`:

```jldoctest interop
julia> dict_to_attribute(attribute_to_dict(attr"Temperature"(21u"°C")))
21.0 °C

julia> dict_to_read(read_to_dict(read"Absorbance"(0.5u"OD")))
0.5 OD
```

`attribute_to_dict` and `read_to_dict` share a `"state"` field with the value `"value"`,
`"missing"`, or `"unknown"`. The `"value"` field is `nothing` unless the state is `"value"`, so a
real value is never confused with `missing` or `Unknown`, as it could be if one of those were stored
as a special string in `"value"`.

## Locations

`location_to_dict` and `dict_to_location` convert a whole tree of locations at once. Every location
type has the fields `kind`, `name`, `is_locked`, `is_active`, its own `attributes`, and `reads`.
The types add:

- `GenericLocation` adds a `"children"` list, and each child is converted in the same way. Children
  can have children, nested as deep as the hierarchy goes.
- `Well` adds `"cost"` and `"stock"`, which is a nested `stock_to_dict`.
- `Labware` stores `"wells"` as a nested two-dimensional array that matches its shape, so a
  `Labware` and its wells convert to a `Dict` and back as one unit.
- A capability-bearing location, a `GenericLocation` or `Labware` whose kind has `is_instrument`
  set, also has `actuatable_attributes`, `performable_operations`, and `readable_types`. These are
  informational. Reconstruction ignores them and takes the capabilities from the `LocationKind`
  that the name resolves to.

```jldoctest interop
julia> root = build_location(loc"Room", "interop root");

julia> child = build_location(loc"Bench", "interop child");

julia> move_into!(root, child)

julia> set_attribute!(root, attr"Temperature"(22u"°C"))

julia> d = location_to_dict(root);

julia> root2 = dict_to_location(d);

julia> CHESSCore.softequal(root, root2)
true
```

Reconstructed locations are compared with `softequal` and not `==`, because `==` is sensitive to
differences in `location_id` and parent identity that do not matter when checking that a location
survived the conversion unchanged.

## Uncommitted locations

Neither format has a field for a `location_id`. Every reconstruction passes `nothing` as the ID,
whether through `build_location` or a direct call of the `Well` or `Labware` constructor. The
result is an uncommitted location. [Committing & Uploading](committing-uploading.md) describes
`commit_location!`, which commits a location from either format.
