"""
    is_registered_reagent(name::Symbol; reagent_context=CHESSCore) -> Bool

Structural check: is `name` a reagent CHESSCore already knows about (via
`CHESSCore.reagentparse`/`reagent_context`)? This is how a `:reagent`-destination column is
recognized -- by looking it up against whatever's already registered, not by registering a
`Factor` per reagent (there could be hundreds).
"""
function is_registered_reagent(name::Symbol; reagent_context = CHESSCore)
    try
        CHESSCore.reagentparse(string(name); reagent_context = reagent_context)
        return true
    catch
        return false
    end
end

"""
    factor_destination(name::Symbol; reagent_context=CHESSCore) -> Symbol

Resolution order for a canonical column name: is it one of [`RESERVED_DESIGN_COLUMNS`](@ref) (returns
`:reserved`)? else is it a reagent CHESSCore already knows? else is it a registered [`Factor`](@ref)?
Throws `ArgumentError` otherwise -- an unregistered column is a hard error, a deliberate departure
from [`ParameterKind`](@ref)'s lenient "unregistered keys are just a raw lookup" stance, since a
design has to be fully understood before it's usable.
"""
function factor_destination(name::Symbol; reagent_context = CHESSCore)
    name in RESERVED_DESIGN_COLUMNS && return :reserved
    is_registered_reagent(name; reagent_context = reagent_context) && return :reagent
    haskey(factor_registry, name) && return destination(factor_registry[name])
    throw(ArgumentError("column :$name is not a registered reagent or Factor"))
end

"""
    classify_columns(names::Vector{Symbol}; reagent_context=CHESSCore)
        -> (reagent=Vector{Symbol}, organism=Vector{Symbol}, condition=Vector{Symbol})

Group a design's (already-canonicalized) column names by [`factor_destination`](@ref).
[`RESERVED_DESIGN_COLUMNS`](@ref) are recognized (don't error) but land in none of these three lists.
"""
function classify_columns(names::AbstractVector{Symbol}; reagent_context = CHESSCore)
    reagent = Symbol[]
    organism = Symbol[]
    condition = Symbol[]
    for n in names
        d = factor_destination(n; reagent_context = reagent_context)
        d === :reagent && push!(reagent, n)
        d === :organism && push!(organism, n)
        d === :condition && push!(condition, n)
    end
    return (reagent = reagent, organism = organism, condition = condition)
end

"""
    _reagent_contribution(qty::Unitful.Quantity, reagent::CHESSCore.Reagent, total_volume)
        -> (contribution::CHESSCore.Stock, consumed_volume::Union{Unitful.Volume,Nothing})

Turn one reagent factor's raw `(value, unit)` quantity into a `Stock` contribution, using
`CHESSCore.Stock`'s own quantity-construction operators (`Unitful.Mass`/`Volume`/`Amount * Reagent`)
rather than `vc_to_stock`/`q_to_stock` -- those DataFrame-interop functions reject molarity outright,
while the underlying `Stock` operators already convert a molar amount via `molecular_weight`. Also
returns how much of `total_volume` this reagent consumed, if it's a liquid given as an absolute
volume -- used by [`resolve_stock`](@ref)'s solvent shortcut.
"""
function _reagent_contribution(qty::Unitful.Quantity, reagent::CHESSCore.Reagent, total_volume)
    u = Unitful.unit(qty)
    if u isa Unitful.MassUnits || u isa Unitful.VolumeUnits || u isa Unitful.AmountUnits
        contribution = qty * reagent
        consumed = (reagent isa CHESSCore.Liquid && u isa Unitful.VolumeUnits) ? uconvert(u"mL", qty) : nothing
        return contribution, consumed
    elseif u isa Unitful.MolarityUnits
        ismissing(total_volume) &&
            throw(ArgumentError("reagent $(reagent) given as a molar concentration but no total_volume was supplied"))
        return (qty * total_volume) * reagent, nothing
    elseif u isa Unitful.DimensionlessUnits || u isa Unitful.DensityUnits
        ismissing(total_volume) &&
            throw(ArgumentError("reagent $(reagent) given as a concentration but no total_volume was supplied " *
                                 "(no liquid reagent/total volume specified; concentrations can't be resolved)"))
        absolute = qty * total_volume
        contribution = absolute * reagent
        consumed = reagent isa CHESSCore.Liquid ? uconvert(u"mL", absolute) : nothing
        return contribution, consumed
    else
        throw(ArgumentError("unsupported unit $u for reagent $(reagent)"))
    end
end

"""
    resolve_stock(row, reagent_names, organism_names;
                  units, reagent_context=CHESSCore, org_context=CHESSCore,
                  total_volume=missing, solvent=nothing)
        -> (stock::CHESSCore.Stock, organisms::Dict{Symbol,Any})

Collectively resolve every `:reagent`- and `:organism`-destination factor in one design row into a
single `CHESSCore.Stock` -- this is deliberately just an interface to get every reagent/organism
factor to a `Stock`, not an independent per-factor resolve step (matches how a `Stock`'s composition
is inherently a whole-row concept, and how `vc`/`q`-style tables are conventionally resolved as one
unit in CHESSCore itself).

`units` is a `Dict{Symbol,String}` (one unit per reagent factor -- see [`DesignColumnMap`](@ref)).

`total_volume`/`solvent` implement the solvent shortcut: `solvent` (a reagent name, e.g. `:water`)
fills whatever's left of `total_volume` after every other explicit liquid reagent factor already
present is accounted for -- so a design doesn't have to spell out its solvent as an explicit factor
just to "bring to volume." If a reagent factor needs a total volume (a concentration or molar
amount) and none is supplied, resolution errors rather than silently failing.

Returns the built `Stock` (promoted to a `Culture` if any organism factor resolved) and a
`Dict{Symbol,Any}` recording each organism factor's resolved value per-well -- since Pourfecto
doesn't schedule inoculation, this is what a technician-facing `:well_conditions` record is built
from.
"""
function resolve_stock(
    row,
    reagent_names::AbstractVector{Symbol},
    organism_names::AbstractVector{Symbol};
    units::AbstractDict{Symbol,String} = Dict{Symbol,String}(),
    reagent_context = CHESSCore,
    org_context = CHESSCore,
    total_volume::Union{Unitful.Volume,Missing} = missing,
    solvent::Union{Symbol,Nothing} = nothing,
)
    stock = CHESSCore.Empty()
    liquid_volume_used = 0u"mL"
    for rname in reagent_names
        haskey(units, rname) || throw(ArgumentError("no unit specified for reagent factor :$rname"))
        reagent = CHESSCore.reagentparse(string(rname); reagent_context = reagent_context)
        qty = row[rname] * Unitful.uparse(units[rname])
        contribution, consumed = _reagent_contribution(qty, reagent, total_volume)
        stock += contribution
        consumed === nothing || (liquid_volume_used += consumed)
    end

    if !isnothing(solvent) && !(solvent in reagent_names)
        ismissing(total_volume) && throw(ArgumentError("solvent :$solvent requested but no total_volume was supplied"))
        remaining = total_volume - liquid_volume_used
        remaining < 0u"mL" && throw(ArgumentError(
            "resolved reagent volumes ($liquid_volume_used) exceed total_volume ($total_volume); can't add solvent :$solvent",
        ))
        solvent_reagent = CHESSCore.reagentparse(string(solvent); reagent_context = reagent_context)
        remaining == 0u"mL" || (stock += remaining * solvent_reagent)
    end

    organism_record = Dict{Symbol,Any}()
    for oname in organism_names
        value = row[oname]
        if ismissing(value)
            organism_record[oname] = missing
            continue
        end
        organism = CHESSCore.orgparse(string(value); org_context = org_context)
        stock += organism
        organism_record[oname] = value
    end

    return stock, organism_record
end

"""
    resolve_conditions(row, condition_names) -> Dict{Symbol,Any}

Resolve every `:condition`-destination factor in one design row into a plain
`Dict{Symbol,Any}` -- deliberately never a `CHESSCore.Attribute` (attributes are for things the
physical object can actually be made to have; a plate can't be set to a temperature the way a well
can be inoculated). Validates a `CategoricalFactor`'s value against its registered `levels`.
"""
function resolve_conditions(row, condition_names::AbstractVector{Symbol})
    out = Dict{Symbol,Any}()
    for cname in condition_names
        f = get_factor(cname)
        value = row[cname]
        if f isa CategoricalFactor && !ismissing(value)
            value in factor_levels(f) ||
                throw(ArgumentError("value $(repr(value)) for factor :$cname is not among its registered levels"))
        end
        out[cname] = value
    end
    return out
end

register_parameter!(:plate_conditions, Dict; default = Dict{Any,Dict{Symbol,Any}}())
register_parameter!(:well_conditions, Dict; default = Dict{Any,Dict{Symbol,Any}}())

"""
    populate_well_conditions(experiment; reagent_context=CHESSCore, org_context=CHESSCore) -> Experiment

Populate `:well_conditions` from an already-scheduled `experiment` (one with `:layout` set, via
[`schedule_layout`](@ref) or [`schedule_blocked_layout`](@ref)) -- keyed by `(labware, well)`, holding
each placed row's `:organism`-destination values (reusing [`resolve_stock`](@ref)'s organism
resolution, without building a `Stock`) and every **non-blocking** `:condition`-destination value
(a blocking `:condition` factor is guaranteed uniform per plate and belongs in `:plate_conditions`
instead -- see [`schedule_blocked_layout`](@ref)). Works on any scheduled `Experiment` regardless of
how it was scheduled, since it only reads `:layout` and `experiment.design`, never `RunMaps`/
`PlateMaps` directly.
"""
function populate_well_conditions(experiment::Experiment; reagent_context = CHESSCore, org_context = CHESSCore)
    lay = layout(experiment)
    lay === nothing && throw(ArgumentError("experiment has no :layout yet -- schedule it first"))

    design = experiment.design
    cols = classify_columns(propertynames(design); reagent_context = reagent_context)
    non_blocking_conditions = [c for c in cols.condition if !is_blocking(get_factor(c))]

    well_conditions = Dict{Any,Dict{Symbol,Any}}()
    for row in eachrow(lay)
        (row.run && !ismissing(row.run_index)) || continue
        i = row.run_index
        record = Dict{Symbol,Any}()
        if !isempty(cols.organism)
            _, organism_record = resolve_stock(design[i, :], Symbol[], cols.organism; org_context = org_context)
            merge!(record, organism_record)
        end
        isempty(non_blocking_conditions) || merge!(record, resolve_conditions(design[i, :], non_blocking_conditions))
        isempty(record) || (well_conditions[(row.labware, row.well)] = record)
    end

    return with_parameter(experiment, :well_conditions, well_conditions)
end
