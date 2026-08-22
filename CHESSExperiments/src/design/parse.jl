register_parameter!(:column_map, DesignColumnMap)

"""
    parse_design(path::AbstractString; column_map=DesignColumnMap(), reagent_context=CHESSCore) -> Experiment

Read a CSV design at `path` into an `Experiment`. Applies `column_map`'s header translation (raw
header -> canonical factor name) and value translation (raw value -> canonical value, for
open-vocabulary categorical factors), then validates that every resulting column resolves to either
a reagent CHESSCore already knows or a registered [`Factor`](@ref) -- an unregistered column is a
hard error here, a deliberate departure from [`ParameterKind`](@ref)'s lenient "unregistered keys are
just a raw lookup" stance, since a design has to be fully understood before it's usable.

`column_map` itself is stored as `:column_map` metadata on the returned `Experiment`, so a persisted
design's raw-string interpretation stays auditable rather than known only at parse time.
"""
function parse_design(path::AbstractString; column_map::DesignColumnMap = DesignColumnMap(), reagent_context = CHESSCore)
    raw = CSV.read(path, DataFrame)

    design = DataFrame()
    for col in names(raw)
        canonical = get(column_map.columns, col, Symbol(col))
        design[!, canonical] = raw[!, col]
    end

    factor_names = propertynames(design)
    for name in factor_names
        factor_destination(name; reagent_context = reagent_context) # throws on an unregistered column
    end

    for (cname, valuemap) in column_map.values
        cname in factor_names || continue
        design[!, cname] = [ismissing(v) ? v : get(valuemap, string(v), v) for v in design[!, cname]]
    end

    return Experiment(design; metadata = Dict(:column_map => column_map))
end
