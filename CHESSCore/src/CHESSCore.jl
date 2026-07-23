module CHESSCore

using
    Unitful, # unit tracking and conversion
    UnitfulParsableString, # parse string unit symbols as Unitful units
    AbstractTrees, # used for computing and storing movements
    UUIDs, # used for generating default labware names
    DataFrames, # DataFrame<->domain-object interop
    Dates, # Read's own recorded time
    StringDistances # used for computing chemical and organism hints
import Base: +,-,*,/,convert, show ,sort , promote_rule,round , in, ==,empty!, hash, isapprox # all overloaded by this package
import AbstractTrees: children,parent,nodevalue


include("./Units/JensenLabUnits.jl")

    using .JensenLabUnits
    Unitful.register(JensenLabUnits)

Unitful.promote_unit(::S,::T) where {S<:Unitful.VolumeUnits,T<:Unitful.VolumeUnits} = u"mL"
Unitful.promote_unit(::S,::T) where {S<:Unitful.MassUnits,T<:Unitful.MassUnits} = u"g"


const labmodules = Vector{Module}()

function _chemprops(m::Module)
    #A hidden symbol which will be automatically attached to any module defining chemicals, allowing CHESSCore.register() to merge in the units from that module
    chemprops_name = Symbol("#JLIMS_chemmprops")
    if isdefined(m,chemprops_name)
        getproperty(m,chemprops_name)
    else
        Core.eval(m,:(const $chemprops_name = Dict{Symbol,Tuple{Union{Unitful.MolarMass,Missing},Union{Unitful.Density,Missing},Union{Integer,Missing}}}()))
    end
end

const chemprops = _chemprops(CHESSCore)

function _orgprops(m::Module)
    orgprops_name=Symbol("#JLIMS_orgprops")
    if isdefined(m,orgprops_name)
        getproperty(m,orgprops_name)
    else
        Core.eval(m , :(const $orgprops_name = Dict{Symbol, Tuple{String,String,String}}()))
    end
end

const orgprops = _orgprops(CHESSCore)


include("./exceptions.jl")
include("./user.jl")
include("./environments/Attributes.jl")
include("./environments/Reads.jl")


include("./locations/LocationKind.jl")
include("./locations/Location.jl")
include("./locations/Occupancy.jl")
include("./environments/Environment.jl")
include("./locations/Instrument.jl")
include("./operations/capability.jl")
include("./locations/Labware.jl")
include("./stocks/Chemicals.jl")
include("./stocks/Organisms.jl")
include("./stocks/Stocks.jl")
include("./stocks/StockDisplay.jl")
include("./stocks/Recipe.jl")
include("./locations/Well.jl")
include("./locations/LocationDisplay.jl")
include("./locations/build_location.jl")

include("./operations/movement.jl")
include("./operations/transfer.jl")
include("./operations/attributes.jl")
include("./operations/reads.jl")
include("./operations/mixing.jl")

include("./interop/stock_utils.jl")
include("./interop/dataframe_interface.jl")
include("./interop/location_interchange.jl")
include("./interop/registry_summary.jl")

export WellCapacityError, MixingError, LockedLocationError, AlreadyLocatedInError,OccupancyError #exceptions
export FixedMembershipError, AmbiguousOccupancyRuleError, ChildNotFoundError, AmbiguousChildNameError, UncommittedLocationError
export JensenLabUnits # custom units
export Attribute, AttributeDict,set_attribute! ,attribute_unit, attribute_kind
export AttributeKind, attribute_kinds, Unknown, UnknownValue, isunknown
export Read, ReadKind, read_kinds, @read, @read_str, read_kind, read_unit, read_time, reads, record_read!
export is_quantitative, is_qualitative
export LocationKind, location_kinds, concretetype, @location_kind, @loc_str
export Reagent,Solid,Liquid,Gas # physical-form types
export Chemical,H⁺,OH⁻,Formula # chemical-identity types
export charge, CompositionRule, composition, set_composition!, composition_rules
export Organism # Organism type
export Stock,Empty, Mixture, Solution, Culture, @stock, @stock_str, stock_recipes # Stock types
export Location, GenericLocation, Labware, Well #location types
export Instrument, actuatable_attributes, performable_operations, readable_types
export @chemical, @reagent, @reagent_formula, @organism , @attribute, @chem_str, @rgt_str, @org_str, @attr_str # macros for constants
export set_occupancy_cost!, occupancy_rules, kind, is_committed, build_location, plate_namer, childtype
# chemicals/reagents
export molecular_weight, density, pubchemid , chemparse, reagentparse, symbol
# Organisms
export genus, species, strain , orgparse
# Stocks
export solids, liquids, reagents, organisms, volume_estimate, quantity, reagent_display
export total_concentration, pH, net_hydrogen_ion_concentration
export Recipe, recipe, mass, molar_amount, volume
# locations
export location_id, name, is_locked, unlock!,lock!,toggle_lock!, ancestors, get_all_within, environment,attributes , is_active, activate!, deactivate!, toggle_activity!
export parent_cost, child_cost, occupancy, occupancy_cost , children, children_named
# `parent` is deliberately not exported here -- Base.parent (extended for Location in Location.jl)
# is already visible everywhere by default; exporting it too collides with Base's own unrelated
# `parent` generic (see the comment above Base.parent(x::Location) in Location.jl).
export can_move_into, move_into!
#labware
export shape, vendor, catalog, wells
#wells
export wellcapacity, stock, cost,  sterilize!,transfer!, drain!,deposit!,withdraw!
# dataframe interop
export df_to_stock, stock_to_df, df_to_labware, labware_to_df
# location <-> dict interop (JSON-safe, for tools outside CHESS)
export location_to_dict, dict_to_location, stock_to_dict, dict_to_stock
export attribute_to_dict, dict_to_attribute, read_to_dict, dict_to_read
export string_to_reagent, reagent_to_string, reagent_df, all_reagents, concentration
export vc_to_stock, stock_to_vc, q_to_stock, stock_to_q
export registry_summary
end # module CHESSCore
