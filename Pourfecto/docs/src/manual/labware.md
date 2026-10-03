# [Labware](@id pourfecto_labware)

## Creating Labware from Tables

```@meta
CurrentModule = Pourfecto
```
To plan liquid handling workflows, Pourfecto needs to know how `Stock`s are held in physical labware. As for stocks, Pourfecto uses CHESSCore to create `Labware` objects.

Pourfecto creates populated labware from stock tables with added labware columns. This suits source plates, destination plates, tubes, reservoirs, and other labware described in CSV files, spreadsheets, or `DataFrame`s.

```@docs
df_to_labware
labware_to_df
```

### Overview

A labware table is a stock table with three additional columns:

- `labware`
- `name`
- `well`

All other columns are interpreted as stock data and passed to [`df_to_stock`](@ref).

```julia
labware = df_to_labware(df, units)
```

The reverse operation is:

```julia
df, units = labware_to_df(labware)
```

### Required columns

The input dataframe must include:

| Column | Description |
|---|---|
| `labware` | Name of a `LocationKind` registered in `location_kinds`, such as `WP96`. The plate kinds used on this page come from `CHESSLabConstants`, which is loaded with CHESS. See [Registering Lab Constants](https://jensenlab.github.io/CHESS/dev/manual/registering-lab-constants/). |
| `name` | Name of the labware instance |
| `well` | Well identifier, such as `"A1"`, `"B12"`, or `"H2"` |

For example:

```julia
using DataFrames 

DataFrame(
    labware = ["WP96","WP96","WP96"],
    name = ["source_plate", "source_plate", "source_plate"],
    well = ["A1", "A2", "A3"],
    volume = [1000, 1000, 1000],
    water = [1.0, 1.0, 1.0],
)
```

The columns `labware`, `name`, and `well` give the location of each stock. The remaining columns describe the stock in that well.

### Labware codes

The `labware` column holds the name of a `LocationKind` that CHESSCore knows. The available names are the keys of `location_kinds`:

```julia
keys(location_kinds)
```

For each unique `(labware, name)` pair, Pourfecto builds one labware object with `build_location(location_kinds[Symbol(labware_code)], name)`. Rows with the same labware code and name, such as `"WP96"` and `"source_plate"`, are placed on the same object.

### Example: create labware from a volume/concentration table

The following example creates a source plate with three filled wells.

```julia
using DataFrames
using Pourfecto

df = DataFrame(
    labware = ["WP96","WP96","WP96"],
    name = ["source_plate", "source_plate", "source_plate"],
    well = ["A1", "A2", "A3"],
    volume = [1000, 1000, 500],
    water = [100, 80, 0],
    ethanol = [0, 20, 100],
)

units = DataFrame(
    volume = ["µL"],
    water = ["percent"],
    ethanol = ["percent"],
)

source_labware = df_to_labware(df, units)
```

The stock data includes a `volume` column, so the stock portion is read as the `"vc"` volume/concentration format.

The result is a vector of labware objects. Here it holds one 96-well plate named "source_plate" with stocks in wells `A1`, `A2`, and `A3`.

### Example: multiple labware objects in one table

A single dataframe can describe multiple pieces of labware.

```julia
df = DataFrame(
    labware = ["WP96","WP96","WP96","WP96"],
    name = ["source_plate_1", "source_plate_1", "source_plate_2", "source_plate_2"],
    well = ["A1", "A2", "A1", "A2"],
    volume = [1000, 1000, 500, 500],
    water = [100, 50, 0, 25],
    ethanol = [0.0, 50, 100, 75],
)

units = DataFrame(
    volume = ["µL"],
    water = ["percent"],
    ethanol = ["percent"],
)

lws = df_to_labware(df, units)
```

This creates two labware objects:

- `source_plate_1`
- `source_plate_2`

Rows with the same `(labware, name)` pair are placed on the same labware object.

### How `df_to_labware` works

[`df_to_labware`](@ref) performs these steps:

1. Splits the table into labware metadata columns and stock columns.
2. Creates one labware object for each unique `(labware, name)` pair.
3. Parses the stock columns using [`df_to_stock`](@ref).
4. Converts each `well` label, such as `"A1"`, into a well index.
5. Deposits each parsed stock into the corresponding well.

Only the stock columns should appear in the `units` dataframe. The `units` dataframe should not include `labware`, `name`, or `well`.

### Exporting labware to dataframes

Use [`labware_to_df`](@ref) to convert labware objects back into table form.

```julia
df, units = labware_to_df(source_labware)
```

By default, this exports stock contents using the `"vc"` format.

```julia
df, units = labware_to_df(source_labware, "vc")
```

To export using quantity format:

```julia
df, units = labware_to_df(source_labware, "q")
```

The output dataframe contains one row per non-empty well.

## Creating Labware Manually

Labware can also be built and filled directly with CHESSCore's `build_location`, `location_kinds`, and `add_stock!`. This suits examples, tests, and notebooks where a dataframe is unnecessary:

```julia
using Pourfecto, CHESSCore, Unitful

plate = build_location(location_kinds[:DeepWP96], "source_plate")
water_stock = 1u"mL" * string_to_component("water", Liquid)

add_stock!(plate, water_stock, 1, 1)  # adds stock to row 1, column 1; well A1
```

CHESSCore's [Locations](https://jensenlab.github.io/CHESS/dev/manual/core-concepts/) page describes location kinds, wells, and `deposit!`, which `add_stock!` uses.

!!! note
    Some Pourfecto examples set `.stock` directly, as in `children(plate)[row, col].stock = ...`, or add to it, as in `well.stock += ...`, instead of calling `add_stock!` or `deposit!`. This shortcut skips the well-capacity check of `deposit!`. It is appropriate when building a target composition that is known to fit. Use `deposit!` for labware whose existing contents are not known.