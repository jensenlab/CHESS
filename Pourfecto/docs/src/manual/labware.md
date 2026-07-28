# [Labware](@id pourfecto_labware)


## Creating Labware from Tables

```@meta
CurrentModule = Pourfecto
```
To plan executable liquid handling workflows, Pourfecto needs information about how `Stock`s are contained in physical labware. Just like for `Stock` objects, Pourfecto uses JLIMS to create `Labware` objects. 

Pourfecto can create populated labware objects from stock tables augmented with labware metadata. This is useful when source plates, destination plates, tubes, reservoirs, or other labware are described in CSV files, spreadsheets, or `DataFrame`s.

```@docs
df_to_labware
labware_to_df
```

---

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

---

### Required columns

The input dataframe must include:

| Column | Description |
|---|---|
| `labware` | Labware type code used by `Pourfecto.generate(labware, name)` |
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

Here, the columns `labware`, `name`, and `well` describe where each stock is located. The remaining columns describe the stock in that well.

---

### Labware codes

The `labware` column should contain a labware code recognized by Pourfecto.

```julia
keys(labwares)
```
returns the available labware codes.

When parsing a table, Pourfecto calls:

```julia
Pourfecto.generate(labware_code, name)
```

for each unique `(labware, name)` pair.

For example, rows with:

```julia
labware = "WP96"
name = "source_plate"
```

will be placed on the same generated labware object.

---

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

Because the stock data includes a `volume` column, Pourfecto interprets the stock portion as the `"vc"` volume/concentration format.

The result is a vector of labware objects. In this example, the vector contains a single 96-well plate named "source_plate" with stocks deposited into wells `A1`, `A2`, and `A3`.

---

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

---


### How `df_to_labware` works

Internally, [`df_to_labware`](@ref) performs the following steps:

1. Splits the table into labware metadata columns and stock columns.
2. Creates one labware object for each unique `(labware, name)` pair.
3. Parses the stock columns using [`df_to_stock`](@ref).
4. Converts each `well` label, such as `"A1"`, into a well index.
5. Deposits each parsed stock into the corresponding well.

Only the stock columns should appear in the `units` dataframe. The `units` dataframe should not include `labware`, `name`, or `well`.

---

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

---

## Creating Labware Manually 


In addition to building labware from tables with [`df_to_labware`](@ref), you can create labware objects directly in Julia with [`generate`](@ref).

This is useful for examples, tests, notebooks, and workflows where you want to programmatically construct source or target labware.

```@docs
generate
```

---


### Adding stocks to labware

Pourfecto provides a convenience function for depositing a `Stock` into a specific well of a `Labware` object.

```@docs
add_stock!
```

This function selects the well at `(row, col)`, deposits the given stock into that well, and returns the modified labware object.

For example:

```julia
using JLIMS
using Unitful
using Pourfecto

plate = generate("DeepWP96", "source_plate")

water_stock = 1u"mL" * chem"water"

add_stock!(plate, water_stock, 1, 1)  # adds stock to row 1, column 1;  well A1
```

The returned object is the same labware object, modified in place:

---

#### Behavior when the well is not empty

If the selected well already contains a stock, `add_stock!` emits a warning and still attempts to deposit the new stock:

```julia
add_stock!(plate, another_stock, 1, 1)
```

This may combine with or otherwise modify the existing well contents depending on the behavior of `JLIMS.deposit!`.

!!! warning
    `add_stock!` does not prevent depositing into non-empty wells. It warns, then proceeds.

---

#### Example: manually fill a source plate

```julia
using JLIMS
using Unitful
using Pourfecto

source_plate = generate("DeepWP96", "source_plate")

stock_a = 1u"mL" * chem"water"
stock_b = 900u"µL" * chem"water" + 100u"µL" * chem"ethanol"

add_stock!(source_plate, stock_a, 1, 1)  # A1
add_stock!(source_plate, stock_b, 1, 2)  # A2
```