"""
    struct DesignColumnMap

Per-input, unregistered translation for one parsed design's raw strings -- deliberately *not* a
durable global alias registry, since spreadsheet naming inconsistency (`"Ala"`/`"L-Alanine"`/
`"alanine"`) is lab-specific/one-off enough that a growing global table would risk collisions rather
than convergence. Supplied per [`parse_design`](@ref) call and stored as `Experiment` metadata (under
`:column_map`) so a stored design's raw-string interpretation stays auditable.

Fields:
- `columns::Dict{String,Symbol}`: raw spreadsheet header -> canonical factor name. A header not
  present as a key is assumed to already equal its canonical name.
- `values::Dict{Symbol,Dict{String,Symbol}}`: canonical factor name -> (raw value -> canonical
  value). Only matters for factors whose *values* are themselves free text needing translation
  (open-vocabulary categorical factors like organism/strain) -- not for numeric reagent quantities.
- `units::Dict{Symbol,String}`: canonical factor name -> unit string, one entry per `:reagent`-
  destination factor (confirmed sufficient: one unit per factor, never per-row/per-cell). Feeds the
  unit half of what [`resolve_stock`](@ref) needs to convert a raw value into a real quantity.
"""
struct DesignColumnMap
    columns::Dict{String,Symbol}
    values::Dict{Symbol,Dict{String,Symbol}}
    units::Dict{Symbol,String}
end

DesignColumnMap(;
    columns::AbstractDict = Dict{String,Symbol}(),
    values::AbstractDict = Dict{Symbol,Dict{String,Symbol}}(),
    units::AbstractDict = Dict{Symbol,String}(),
) = DesignColumnMap(Dict{String,Symbol}(columns), Dict{Symbol,Dict{String,Symbol}}(values), Dict{Symbol,String}(units))
