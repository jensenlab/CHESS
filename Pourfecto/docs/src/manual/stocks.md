# [Stocks](@id pourfecto_stocks) 

!!! note
    This page describes how Pourfecto converts tables to and from CHESSCore's `Stock` type. It
    assumes familiarity with `Stock`, which CHESSCore's
    [Stocks](https://jensenlab.github.io/CHESS/dev/manual/stocks/) page describes.

## Creating Stocks from Tables 

```@meta
CurrentModule = Pourfecto
```

Pourfecto represents source and target materials as CHESSCore `Stock` objects. Most workflows create them from tabular data with [`df_to_stock`](@ref) instead of constructing them by hand. This suits stocks read from CSV files, spreadsheets, notebooks, or forms.

The main stock conversion functions are:

```@docs
df_to_stock
stock_to_df
```

A stock table is represented by two `DataFrame`s:

1. `df`: the main stock data
2. `units`: the units associated with the values in `df`

```julia
stocks = df_to_stock(df, units)
```

The reverse operation is:

```julia
df, units = stock_to_df(stocks)
```

### Supported stock table formats

Pourfecto supports two stock table encodings:

| Format | Description |
|---|---|
| `"vc"` | Volume/Concentration format |
| `"q"` | Quantity format |

[`df_to_stock`](@ref) detects the format. If both `df` and `units` contain a `"volume"` column, the table is a **volume/concentration** table. Otherwise it is a **quantity** table.

### Volume/concentration format

In the volume/concentration format, each row is a stock with a total volume and one or more reagent concentrations. For example:

| volume | reagent_a | reagent_b |
|---:|---:|---:|
| 1000 | 10 | 5 |
| 500 | 20 | 0 |

with a corresponding units table:

| volume | reagent_a | reagent_b |
|---|---|---|
| µL | mM | mM |

Example:

```julia
using DataFrames
using Unitful
using Pourfecto

df = DataFrame(
    volume = [1000, 500],
    sodium_chloride = [10, 20],
    dye = [5, 0],
)

units = DataFrame(
    volume = ["µL"],
    sodium_chloride = ["mM"],
    dye = ["mM"],
)

stocks = df_to_stock(df, units)
```

Both tables contain a `"volume"` column, so this is parsed as a `"vc"` table.

!!! warning
    A reagent cannot be named "volume", because the parser reads that name as the total volume.

### Quantity format

In the quantity format, each row is a stock given directly by the amount of each reagent it contains. For example:

| water | sodium_chloride |
|---:|---:|
| 1000 | 10 |
| 500 | 5 |

with a corresponding units table:

| water | sodium_chloride |
|---|---|
| µL | mg |

Example:

```julia
using DataFrames
using Pourfecto

df = DataFrame(
    water = [1000, 500],
    sodium_chloride = [10, 5],
)

units = DataFrame(
    water = ["µL"],
    sodium_chloride = ["mg"],
)

stocks = df_to_stock(df, units)
```

These tables have no `"volume"` column, so this is parsed as a `"q"` table.

### Reagent names

Reagent names come from the column names. Pourfecto converts each name to a `Reagent` with `string_to_component`. A registered reagent is used when one exists. Otherwise a generic chemical is created with unknown properties, and a warning is shown. In the examples above, the columns `sodium_chloride` and `dye` are read as reagent names.

!!! note
    A reagent that is not registered can be used for planning and scheduling. Calculations that
    need molecular weight or density require a registered reagent.

See also: [Reagents](@ref pourfecto_reagents)

### Converting stocks back to dataframes

Use [`stock_to_df`](@ref) to export stocks back into tabular form.

```julia
df, units = stock_to_df(stocks)
```

By default, this uses the `"vc"` format:

```julia
df, units = stock_to_df(stocks, "vc")
```

To request quantity format:

```julia
df, units = stock_to_df(stocks, "q")
```

## Creating Stocks Manually

Stocks can also be created with CHESSCore's arithmetic. Multiplying a quantity by a reagent builds a stock, adding stocks combines them, multiplying or dividing by a number scales a stock, and multiplying by a quantity rescales it to that total. This suits notebooks, tests, examples, and small workflows where a dataframe is unnecessary:

```julia
using Pourfecto, CHESSCore, Unitful

water = string_to_component("water", Liquid)
sodium_chloride = string_to_component("sodium_chloride", Solid)

buffer = 1u"mL" * water + 10u"mg" * sodium_chloride
scaled = 2 * buffer
```

CHESSCore's [Stocks](https://jensenlab.github.io/CHESS/dev/manual/stocks/) page describes the operations in full.

