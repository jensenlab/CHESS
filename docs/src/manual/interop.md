# Interop

```@meta
DocTestSetup = :(using CHESS)
```

`CHESSCore` has two complementary data-interchange formats. The tabular one
([`stock_to_df`](@ref)/[`df_to_stock`](@ref) and their `labware` counterparts) is for bulk, flat
batches of stock definitions -- a wet-lab CSV template. The general one ([`location_to_dict`](@ref)/
[`dict_to_location`](@ref)) is for a whole `Location` (or tree of them) with full fidelity -- for
tools outside CHESS, and outside Julia entirely, to consume.

## The tabular format: "vc" vs "q"

Both encode only the *stock* columns of a table -- everything else (`labware`/`name`/`well`, for a
full labware table) is metadata used to place the stock, not part of the format itself.

**"q" (quantity)** -- each reagent column is an absolute quantity (mass, volume, or molar amount).
Exact and unambiguous, with no dependence on a stock having any particular total. The examples
pass `reagent_context` so reagent names resolve against CHESS's registered reagents (see
[below](#Reagent-columns-must-match-a-registered-name)):

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

**"vc" (volume/concentration)** -- a `"volume"` column plus one relative-concentration column per
reagent. This is the natural shape for a human-authored wet-lab template: "how much total volume,
and what percent (or M, or g/mL) of each reagent." It only works when the stock has a defined total
quantity to relate concentrations to:

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

`df_to_stock`/`df_to_labware` auto-detect which format they're reading purely by checking for a
`"volume"` column -- there's no explicit format argument on the read side, only on the write side
(`stock_to_df`/`labware_to_df`).

### Reagent columns must match a registered name

A reagent's DataFrame column header is its *registered binding name* (`symbol(r;
reagent_context)`, e.g. `"paba"`), not its display name (`name(r)`, e.g. `"4-aminobenzoic acid"`) --
falling back to the display name only if the symbol can't be found in the given `reagent_context`.
This means `reagent_context` needs to be passed **consistently when converting a stock to a
DataFrame and back**. Leave it out of either call and the fallback happens silently; if the
display name then contains spaces or punctuation that isn't valid in a name, converting back fails
internally and produces an empty, propertyless reagent instead of the real one. CHESS logs a
warning ("reagent ... not registered"), but does not throw an error.

## The general format: `Location`/`Stock` <-> `Dict`

`stock_to_dict`/`dict_to_stock` convert a `Stock` to a plain `Dict` built only from values every
programming language can read (`Dict`/`Vector`/`String`/`Real`/`Nothing`) -- no extra library
needed to write or read it. It mirrors the "q" format's exact quantity shape, not "vc"'s relative
one:

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

`attribute_to_dict`/`read_to_dict` share a `"state"` field (`"value"`/`"missing"`/`"unknown"`), with
`"value"` forced to `nothing` unless `state == "value"` -- so a real value is never confused with
`missing` or `Unknown`, the way it could be if one of those were stored as a special string
directly in `"value"`.

## `location_to_dict`/`dict_to_location`: a whole tree at once

Every subtype shares a common set of fields: `kind`, `name`, `is_locked`, `is_active`, its own
`attributes`, and `reads`. Beyond that:

- `GenericLocation` adds a `"children"` list, where each child is converted the same
  way -- children can themselves have children, nested as deep as the real hierarchy goes.
- `Well` adds `"cost"` and `"stock"` (a nested `stock_to_dict`).
- `Labware` is the one non-flat exception: `"wells"` is a nested 2D array matching its shape, so a
  `Labware` and its wells convert to a `Dict` and back as a single unit -- matching how a human
  actually thinks about a plate.
- Any capability-bearing location (`GenericLocation` or `Labware` with `is_instrument` set on its
  kind) additionally includes informational-only `actuatable_attributes`/
  `performable_operations`/`readable_types` -- these are never consulted on reconstruction, which
  always re-derives real capability from the resolved `LocationKind` by name.

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

Reconstructed locations are compared with `softequal`, not `==` -- `==` would be sensitive to
`location_id`/parent-identity differences that don't matter when checking that a location converted
to a `Dict` and back came out unchanged.

## Both formats are uncommitted-only

Neither format has a field to carry a `location_id` at all -- every reconstruction constructor call
passes `nothing` literally, whether through `build_location` internally or a direct
`Well(nothing,...)`/`Labware(nothing,...)` call. [Committing & Uploading](committing-uploading.md)
covers `commit_location!`, the explicit, separate step to get a real, tracked location out of
either format's result.
