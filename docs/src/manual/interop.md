# Interop

`CHESSCore` has two complementary data-interchange formats. The tabular one
(`CHESSCore/src/interop/dataframe_interface.jl`) is for bulk, flat batches of stock definitions --
a wet-lab CSV template. The general one (`CHESSCore/src/interop/location_interchange.jl`) is for a
whole `Location` (or tree of them) with full fidelity -- for tools outside CHESS, and outside Julia
entirely, to consume.

## The tabular format: "vc" vs "q"

Both encode only the *stock* columns of a table -- everything else (`labware`/`name`/`well`, for a
full labware table) is metadata used to place the stock, not part of the format itself.

**"q" (quantity)** -- each reagent column is an absolute quantity (mass, volume, or molar amount).
Exact and unambiguous, with no dependence on a stock having any particular total:

```julia-repl
julia> deposit!(bottle.children[1,1], 10u"g"*paba, 5)

julia> df_q, units_q = labware_to_df(bottle, "q"; reagent_context=[CHESSCore,Main])

julia> lws_q = df_to_labware(df_q, units_q; reagent_context=[CHESSCore,Main])

julia> stock(lws_q[1][df_q.well[1]]) == stock(bottle.children[1,1])
true

julia> CHESSCore.is_committed(lws_q[1])
false
```

**"vc" (volume/concentration)** -- a `"volume"` column plus one relative-concentration column per
reagent. This is the natural shape for a human-authored wet-lab template: "how much total volume,
and what percent (or M, or g/mL) of each reagent." It only works when the stock has a defined total
quantity to relate concentrations to:

```julia-repl
julia> deposit!(bottle2.children[1,1], 100u"mL"*water, 5)

julia> df_vc, units_vc = labware_to_df(bottle2, "vc"; reagent_context=[CHESSCore,Main])

julia> lws_vc = df_to_labware(df_vc, units_vc; reagent_context=[CHESSCore,Main])

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
internally and produces an empty, propertyless reagent instead of the real one -- with no error
shown to say so.

## The general format: `Location`/`Stock` <-> `Dict`

`stock_to_dict`/`dict_to_stock` convert a `Stock` to a plain `Dict` built only from values every
programming language can read (`Dict`/`Vector`/`String`/`Real`/`Nothing`) -- no extra library
needed to write or read it. It mirrors the "q" format's exact quantity shape, not "vc"'s relative
one:

```julia-repl
julia> stock_to_dict(10u"g"*paba; reagent_context=[CHESSCore,Main])
Dict{String, Any}("organisms" => String[], "solids" => Dict{String, Any}("paba" => Dict{String, Any}("amount" => 10, "unit" => "g")), "liquids" => Dict{String, Any}())
```

`attribute_to_dict`/`read_to_dict` share a `"state"` field (`"value"`/`"missing"`/`"unknown"`), with
`"value"` forced to `nothing` unless `state == "value"` -- so a real value is never confused with
`missing` or `Unknown`, the way it could be if one of those were stored as a special string
directly in `"value"`.

## `location_to_dict`/`dict_to_location`: a whole tree at once

Every subtype shares a common set of fields: `kind`, `name`, `is_locked`, `is_active`, its own
`attributes`, and `reads`. Beyond that:

- `GenericLocation`/`Instrument` add a `"children"` list, where each child is converted the same
  way -- children can themselves have children, nested as deep as the real hierarchy goes.
- `Well` adds `"cost"` and `"stock"` (a nested `stock_to_dict`).
- `Labware` is the one non-flat exception: `"wells"` is a nested 2D array matching its shape, so a
  `Labware` and its wells convert to a `Dict` and back as a single unit -- matching how a human
  actually thinks about a plate.
- `Instrument` additionally includes informational-only `actuatable_attributes`/
  `performable_operations`/`readable_types` -- these are never consulted on reconstruction, which
  always re-derives real capability from the resolved `LocationKind` by name.

```julia-repl
julia> root = CHESSCore.GenericLocation(nothing, "interop root", Room)

julia> child = CHESSCore.GenericLocation(nothing, "interop child", Bench)

julia> move_into!(root, child)

julia> set_attribute!(root, Temperature(22u"°C"))

julia> d = location_to_dict(root)

julia> root2 = dict_to_location(d)

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
