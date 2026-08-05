module Pourfecto

using Unitful, CHESSCore, CHESSLabConstants, AbstractTrees, DataFrames , JuMP , Gurobi , JSON, Plots, Random, CSV , Dates, TextWrap, Preferences

import InteractiveUtils: subtypes
import JSONTables: objecttable, jsontable
import StructUtils: lowerkey
import UUIDs: uuid4
import Plots: plot



include("types.jl")
include("instruments/utils.jl")
include("exceptions.jl")
include("diagnostics.jl")
include("default_labware.jl")
include("mask_utils.jl")
include("dataframe_interface.jl")

include("pourfecto_algorithms/helpers.jl")
include("pourfecto_algorithms/objectives.jl")
include("pourfecto_algorithms/parameter_defaults.jl")
include("pourfecto_algorithms/algorithms.jl")



"""
    configurations

By default, Pourfecto provides an assortment of pre-defined instruments. Use `keys(configurations)` to see available instruments

"""
const configurations= Dict{String,Configuration}()

"""
    register_instrument!(config::Configuration; name::AbstractString, override::Bool=false)

Register `config` in the global [`configurations`](@ref) registry under `name`, making it
discoverable via `configurations["name"]` and usable by name in [`pourfecto`](@ref).

Errors if `name` is already registered unless `override=true` (in which case the previous entry is
replaced and a warning is emitted) -- this guards against two independently-authored instrument
packages accidentally colliding on the same name. `config.kind`'s capability-bearing validation
already happens inside the `Configuration{I}` outer constructor (see [`Configuration`](@ref)); this
function only handles registry-level name bookkeeping, not re-validation.

Third-party instrument packages should call this once per `Configuration` they define, typically at
module top-level (or from `__init__()` if settings need to be read from `Preferences.jl`/environment
state at load time) right after `using Pourfecto`.

# Examples
```jldoctest
julia> abstract type ExInstrument <: InstrumentModel end

julia> piston = Piston{ContinuousActuator,SingleRepeater}((20u"µL",200u"µL"),(20u"µL",200u"µL"),1);

julia> head = Head{ExInstrument}([piston],[Channel(220u"µL")],trues(1,1));

julia> deck = [UnconstrainedPosition("Deck",true,true,"square")];

julia> register_instrument!(Configuration{ExInstrument}(head,deck); name="ex_instrument");

julia> haskey(configurations,"ex_instrument")
true
```
"""
function register_instrument!(config::Configuration; name::AbstractString, override::Bool=false)
    if haskey(configurations, name)
        if !override
            error("an instrument configuration named \"$name\" is already registered; pass override=true to replace it")
        end
        @warn "overwriting existing configuration \"$name\""
    end
    configurations[name] = config
    return config
end


include("./compiler/adverbs_verbs.jl")
include("./compiler/slotting.jl")
include("plotting/plotting.jl")
include("./compiler/helpers.jl")
include("./instruments/SingleChannel.jl")
include("./instruments/EightChannel.jl")
include("./instruments/PlateMaster.jl")
include("./instruments/Cobra.jl")
include("./instruments/Nimbus.jl")
include("./instruments/Mantis.jl")
include("./instruments/Tempest.jl")
include("json_interface.jl")
include("./compiler/compile.jl")
include("test_utils.jl")




"""
        pourfecto(directory::AbstractString,
                source_labware::Vector{<:CHESSCore.Labware},
                target_labware::Vector{<:CHESSCore.Labware},
                configs::Union{Vector{<:AbstractString},Vector{<:Configuration}};
                kwargs...)

Run the Pourfecto algorithm in **planning and scheduling** mode and automatically compile the resulting `Pourcast`(@ref) in `directory`.

If the Pourcast fails a `solution_quality` check, `pourfecto` will produce an error message while saving the `Pourcast` and quality report to the directory
## Arguments
* `directory`: The output directory (will be made if it doesn't already exist)
* `source_labware`: The CHESSCore.Labware objects containing source stocks that pourfecto can use to create the targets
* `target_labware`: The CHESSCore.Labware objects containing target stocks pourfecto is trying to create using the sources
* `configs` : The the Configuration objects **or** String identifiers for instrument configurations pourfecto can use to schedule the planned liquid transfers.

## Keyword Arguments
$(_pourfecto_kw_doc_())
"""
function pourfecto(directory::AbstractString,source_labware::Vector{<:CHESSCore.Labware},target_labware::Vector{<:CHESSCore.Labware},configs::Union{Vector{<:AbstractString},Vector{<:Configuration}};kwargs...)
    pc = pourfecto(source_labware,target_labware,configs;kwargs...)
    if !isdir(directory) 
        mkdir(directory)
    end 
    qual = solution_quality(pc) 
    if any(qual)
        report = solution_quality_report(pc)
        CSV.write(joinpath(directory,"solution_quality_report.csv"),report)
        JSON.json(joinpath(directory,"pourcast.json"),pourcast_to_json(pc))
        message = "Pourcast failed quality control. Aborting compile and reporting errors to $(directory)"
        midline = repeat("-",length(message))
        error("$message \n$midline \n$(report)")
    else
        compile(directory,pc;kwargs...)
    end 
    return pc 
end 



export PriorityDict
export Configuration, Head, Deck

export InstrumentModel # dispatch tag every new instrument subtypes
export Piston, Channel # head-building blocks
export Actuator, ContinuousActuator, DiscreteActuator # actuator hierarchy
export RepeaterStyle, SingleRepeater, MultiRepeater # repeater hierarchy
export DeckPosition, EmptyPosition, UnconstrainedPosition, ConstrainedPosition # deck position hierarchy
export InstrumentSettings

export pistons, aspirate_channels, dispense_channels, channel_routing, aspirate_mask, dispense_mask # Head accessors
export head, deck, settings, slots, labware, can_aspirate, can_dispense # Configuration/DeckPosition accessors

export Mask, MaskRule, build_mask_from_rules, mask_rules_for # the mask/geometry system
export asp, disp, asp_positions, disp_positions # Mask accessors, for a custom hand-written Mask method
export sliding_window_mask, blanket_mask, effective_head_size # mask archetypes/primitives
export compute_positions, compute_mask_sizes

export can_place, can_operate # deck/labware admissibility

export SlottingDict, slotting_greedy, packing_greedy # slotting/packing
export write_instrument_files # compiler extension point (falls back to a generic transfer-table CSV)

export register_instrument! # instrument registration

export configurations, objectives # constants

export set_cobra_path!, JENSENLAB_COBRA_PATH # persistent instrument-specific settings

export reagent_to_string, string_to_reagent # string interface for reagents

export df_to_stock, stock_to_df, df_to_labware, labware_to_df # dataframe interface 

export pourfecto # main pourfecto algorithm

export InfeasibleSolveError # diagnosable solver-infeasibility exception

export Pourcast, flows, transfers , slacks , planned_stocks , target_stocks, source_stocks, target_labware, source_labware, model_solution,scheduling_objective_value,configs ,transfers_by_config , params # pourcast functions 

export json_to_pourcast, pourcast_to_json # json interface 

export plot , plot_flows # visualization 

export compile # compiler 


end # module Pourfecto
