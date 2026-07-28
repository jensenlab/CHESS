# [Stocks](@id pourfecto_stocks) 

## Creating Stocks from Tables 

```@meta
CurrentModule = Pourfecto
```

Pourfecto represents source and target materials as `JLIMS.Stock` objects. In most workflows, users do not need to construct `Stock`s manually. Instead, stocks can be created from tabular data using [`df_to_stock`](@ref).

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

Pourfecto can turn those reagent names into `JLIMS.Chemical` objects automatically. Registered JLIMS chemicals are used when available. Unknown reagents are created on the fly with missing chemical properties.

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
    that require molecular weight or density may require fully registered JLIMS chemicals.

See also: [`string_to_reagent`](@ref), [`reagent_to_string`](@ref)



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


Stocks can also be created manually with convenient arithmetic syntax from [JLIMS](https://github.com/jensenlab/JLIMS).

This is useful in notebooks, tests, examples, and small workflows where writing a dataframe would be unnecessary.

JLIMS overloads the `*` operator so that quantities and chemicals can be combined directly:

```julia
using JLIMS
using Pourfecto 
using Unitful

sodium_chloride = string_to_reagent("sodium_chloride",Solid)
water = string_to_reagent("water", Liquid) 

10u"mg" * sodium_chloride
1u"mL" * water 
```

Depending on the chemical type and unit, these expressions create solid stocks `Mixture`s or liquid stocks `Solution`s

In general:

- `mass * Solid` creates a Mixture
- `amount * Solid` creates a Mixture
- `volume * Liquid` creates a Solution

---


### Combining stocks

Stocks can be combined using `+`.

For example:

```julia
stock = 900u"µL" * chem"water" + 100u"µL" * chem"ethanol" # assumes "water" and "ethanol" are pre-registered chemicals 
```

This creates a stock containing both water and ethanol.

A more complex example might include both solids and liquids:

```julia
buffer = 1u"mL" * chem"water" + 10u"mg" * chem"sodium_chloride" # assumes "water" and "sodium_chloride" are pre-registered chemicals 
```

---

### Scaling stocks

Stocks can be multiplied by scalar values.

```julia
stock2 = 2 * stock
```

This returns a new stock with all chemical quantities scaled by the given factor.

Scalar multiplication works in either order:

```julia
stock2 = 2 * stock
stock3 = stock * 2
```

Stocks can also be divided by scalars:

```julia
half_stock = stock / 2
```

---

### Rescaling a stock to a target quantity

A stock can be scaled to a target total quantity using:

```julia
target_quantity * stock
```

For example, if `stock` represents a liquid mixture, you can scale it to a final volume:

```julia
small_stock = 100u"µL" * stock
```

or:

```julia
large_stock = 10u"mL" * stock
```

!!! note
    The target quantity must be dimensionally compatible with the stock’s total quantity.
    For example, a liquid stock can be scaled to a volume such as `100u"µL"`, but not
    to an incompatible unit.

---


### Example:  Adding multiple chemicals in a `For` Loop 



```julia
using JLIMS
using Unitful

chem_names = ["A","B","C","D"]
chem_masses = [1,2,3,4]

stock = 1u"mL" * string_to_reagent("water",Liquid) 
for i in eachindex(chem_names)
    stock += (chem_masses[i] *u"mg") * string_to_reagent(chem_names[i],Solid) 
end 

```

This creates a stock containing:

- 1 mL water
- 1 mg A
- 2 mg B
- 3 mg C 
- 4 mg D 

---

### Operator summary

| Expression | Meaning |
|---|---|
| `amount * solid` | Create a `Mixture` from a molar quantity of a solid |
| `mass * solid` | Create a `Mixture` from a mass of a solid |
| `volume * liquid` | Create a `Solution` from a volume of a liquid |
| `num * stock` | Scale all stock components by `num` |
| `stock * num` | Same as `num * stock` |
| `stock / num` | Divide all stock components by `num` |
| `quantity * stock` | Rescale stock to a target total quantity |
| `stock * quantity` | Same as `quantity * stock` |

---


