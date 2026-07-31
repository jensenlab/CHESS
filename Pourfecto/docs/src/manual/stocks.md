# [Stocks](@id pourfecto_stocks) 

## Creating Stocks from Tables 

```@meta
CurrentModule = Pourfecto
```

Pourfecto represents source and target materials as CHESSCore `Stock` objects. In most workflows, users do not need to construct `Stock`s manually. Instead, stocks can be created from tabular data using [`df_to_stock`](@ref).

This is useful when reading stocks from CSV files, spreadsheets, notebooks, or user-facing forms.

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

---

### Supported stock table formats

Pourfecto supports two stock table encodings:

| Format | Description |
|---|---|
| `"vc"` | Volume/Concentration format |
| `"q"` | Quantity format |

The parser [`df_to_stock`](@ref) automatically detects which format is being used.

If both `df` and `units` contain a `"volume"` column, Pourfecto treats the table as a **volume/concentration** table.

Otherwise, Pourfecto treats the table as a **quantity** table.

---

### Volume/concentration format

The volume/concentration format is useful when each row represents a stock with a total volume and one or more reagent concentrations.

Conceptually:

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

Because both tables contain a `"volume"` column, Pourfecto parses this as a `"vc"` table.

!!! warning 
    Stocks cannot have reagents with the name "volume", as it will confuse the parser 

---

### Quantity format

The quantity format is useful when each row represents a stock directly by the amount of each reagent it contains.

Conceptually:

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

Because these tables do not contain a `"volume"` column, Pourfecto parses this as a `"q"` table.

---

### Automatic reagent creation

When parsing stock tables, reagent names are usually taken from the column names.

Pourfecto can turn those reagent names into `Reagent` objects automatically, via `string_to_reagent`. Registered reagents are used when available. Unknown reagents are created on the fly with missing chemical properties.

For example, a column named:

```julia
:sodium_chloride
```

or

```julia
:dye
```

can be interpreted as a reagent name.

If the reagent is not registered, Pourfecto will warn and create a generic chemical object.

!!! note
    Unknown reagents can still be used for planning and scheduling. However, calculations
    that require molecular weight or density may require fully registered reagents.

See also: [Reagents](@ref pourfecto_reagents)



---

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

---



## Creating Stocks Manually

Stocks can also be created manually with CHESSCore's arithmetic syntax (`*` to combine a quantity with a reagent, `+` to combine stocks, scalar `*`/`/` to scale, and quantity `*` to rescale to a target total) — useful in notebooks, tests, examples, and small workflows where writing a dataframe would be unnecessary:

```julia
using Pourfecto, CHESSCore, Unitful

water = string_to_reagent("water", Liquid)
sodium_chloride = string_to_reagent("sodium_chloride", Solid)

buffer = 1u"mL" * water + 10u"mg" * sodium_chloride
scaled = 2 * buffer
```

For the full operator reference (`Mixture`/`Solution` construction rules, rescaling semantics, and more), see CHESSCore's [Stocks](https://jensenlab.github.io/CHESS/dev/manual/stocks/) manual page.

---


