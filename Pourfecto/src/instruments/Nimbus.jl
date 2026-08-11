abstract type Nimbus <: InstrumentModel end

piston_nimbus = Piston{ContinuousActuator, MultiRepeater}(
    (25u"µL",1000u"µL"),
    (25u"µL",1000u"µL"),
    1
)

nimbus_head_mask = trues(1,1) 

nimbus_channels = [Channel(1000u"µL")]

nimbus_head = Head{Nimbus}([piston_nimbus],nimbus_channels, nimbus_head_mask)

# Define our available racks
#15 mL tube
tuberack15mL_0001=ConstrainedPosition("TubeRack15ML_0001",Set([:Conical15]),(4,6),true,true,"circle")
# 50 mL tube
tuberack50mL_0001=ConstrainedPosition("TubeRack50ML_0001",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0002=ConstrainedPosition("TubeRack50ML_0002",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0003=ConstrainedPosition("TubeRack50ML_0003",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0004=ConstrainedPosition("TubeRack50ML_0004",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0005=ConstrainedPosition("TubeRack50ML_0005",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0006=ConstrainedPosition("TubeRack50ML_0006",Set([:Conical50]),(2,3),true,true,"circle")

# 2 mL deep well plate
# Explicit kind names, not CHESSCore.LocationKind categories. This constant removes a literal-Set
# duplication (used below twice) and also feeds nimbus_admissible_kinds further down, which Mask uses.
const nimbus_deep_well_kinds = Set([:DeepWP96,:WP96,:DeepReservoir,:DeepWellColumn,:DeepWellRow])
Cos_96_DW_2mL_0001=ConstrainedPosition("Cos_96_DW_2mL_0001",nimbus_deep_well_kinds,(1,1),true,true,"rectangle")
Cos_96_DW_2mL_0002=ConstrainedPosition("Cos_96_DW_2mL_0002",nimbus_deep_well_kinds,(1,1),true,true,"rectangle")

# The union of every kind admitted by any of Nimbus's deck slots -- Mask represents head capability,
# independent of which physical slot a given instance sits in, so it gates on the union, while each
# ConstrainedPosition above keeps its own narrower, slot-specific set unchanged.
const nimbus_admissible_kinds = union(Set([:Conical15,:Conical50]), nimbus_deep_well_kinds)


nimbus_deck = [Cos_96_DW_2mL_0001 tuberack50mL_0001 tuberack50mL_0002 EmptyPosition("tip rack"); tuberack50mL_0003 tuberack50mL_0004 tuberack50mL_0005 tuberack50mL_0006]


register_instrument!(Configuration{Nimbus}(nimbus_head,nimbus_deck,InstrumentSettings("max_tip_use" => 10);kind=CHESSCore.location_kinds[:Nimbus]); name="nimbus")

## Nimbus Masks

const nimbus_mask_rules = [
    MaskRule(nimbus_admissible_kinds, :aspirate, :sliding_window, (;)),
    MaskRule(nimbus_admissible_kinds, :dispense, :sliding_window, (;)),
]
Mask(h::Head{Nimbus},l::Labware) = build_mask_from_rules(h,l,nimbus_mask_rules)
mask_rules_for(::Configuration{Nimbus}) = nimbus_mask_rules



## Nimbus Compiling Functions 

function convert_design(design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware}, slotting::SlottingDict,config::Configuration{Nimbus}) 
    # helper function that converts the design and slotting scheme into operations for the nimbus 
    
    all(map(x-> x[1] in deck(config),values(slotting))) || ArgumentError("All deck positions in the SlottingDict must be present on the deck")
    S=length(sources)
    src_idx = vcat([fill(i,length(sources[i])) for i in 1:S]...)
    within_src_index = vcat([1:length(sources[i]) for i in 1:S]...) 
     T=length(targets)
    tgt_idx = vcat([fill(i,length(targets[i])) for i in 1:T]...)
    within_tgt_index = vcat([1:length(targets[i]) for i in 1:T]...) 

    source_id=String[]
    source_position=Union{String,Integer}[]
    volume=Real[]
    destination_id=String[]
    destination_position=Union{String,Integer}[]
    alphabet=collect('A':'Z')
    for row in 1:nrow(design) #sources
        source = sources[src_idx[row]]
        s_slot , s_pos = slotting[source]
        for col in 1:ncol(design) #destinations
            if design[row,col] == 0 
                continue # skip if no volume transferred 
            end 
            push!(source_id,s_slot.name)
            if length(source) ==1 
                push!(source_position,s_pos)
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(source))[with_src_index[row]])
                push!(source_position,pos)
            end 
            push!(volume,design[row,col])
            destination =targets[tgt_idx[col]]
            d_slot,d_pos = slotting[destination]
            push!(destination_id,d_slot.name)
            if length(destination) == 1 
                push!(destination_position,d_pos)
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(destination))[within_tgt_index[col]])
                push!(destination_position,pos)
            end 
        end 
    end 

    out=DataFrame("Source Labware ID"=>source_id,
        "Source Position ID"=> source_position,
        "Volume (uL)"=> volume,
        "Destination Labware ID"=> destination_id,
        "Destination Position ID"=> destination_position,
    )

    return out
end


"""
    batch_design(df::DataFrame, config::Configuration{Nimbus}; batch_ordering::Symbol=:greedy) -> (DataFrame, Vector{Int}, Vector)

Group `convert_design`'s flat source/destination transfer list into one-to-many
aspirate/dispense batches, bounded by the Nimbus channel's dispense capacity. For each distinct
source well (grouped in first-appearance row order), destination transfers are volume-split
against capacity ([`split_oversized`](@ref)), packed into capacity-bounded, distance-aware
batches ([`cluster_batches`](@ref)), and ordered within each batch
([`order_batch`](@ref); `batch_ordering` is `:greedy` or `:exact`). Each batch is emitted as one
aspirate row (source well, total batch volume) followed by its dispense rows, in the unified
`"Labware ID","Labware Position ID","Volume (uL)","Aspirate","Dispense","Change Tip Before"`
schema (`"Change Tip Before"` is left `0` here; the caller fills it in via
[`tip_change_flags`](@ref)).

Returns `(action_df, aspirate_row_indices, batch_sources)`: `aspirate_row_indices` are the
1-based row indices of `action_df` holding an aspirate action, and `batch_sources[k]` is the
`(labware id, position)` of the k-th batch's source, in emission order -- both needed by the
caller to compute and apply tip-change flags without re-deriving batch boundaries.
"""
function batch_design(df::DataFrame, config::Configuration{Nimbus}; batch_ordering::Symbol=:greedy)
    capacity = ustrip(uconvert(u"µL", dispense_channels(head(config))[1].capacity))

    # group rows by source well, preserving first-appearance order
    source_keys = Tuple{String,Union{String,Integer}}[]
    groups = Dict{Tuple{String,Union{String,Integer}},Vector{Int}}()
    for row in 1:nrow(df)
        key = (df[row,"Source Labware ID"], df[row,"Source Position ID"])
        if !haskey(groups,key)
            groups[key] = Int[]
            push!(source_keys,key)
        end
        push!(groups[key],row)
    end

    labware_id=String[]
    labware_position=Union{String,Integer}[]
    volume=Real[]
    aspirate=Int[]
    dispense=Int[]
    aspirate_row_indices=Int[]
    batch_sources=Tuple{String,Union{String,Integer}}[]

    row_idx=0
    for key in source_keys
        items = map(groups[key]) do r
            pos = df[r,"Destination Position ID"]
            position = pos isa AbstractString ? well_to_cartesian(pos) : CartesianIndex(1,1)
            DispenseItem(r,position,df[r,"Volume (uL)"])
        end
        for batch in cluster_batches(split_oversized(items,capacity),capacity)
            batch = order_batch(batch,batch_ordering)
            push!(labware_id,key[1]); push!(labware_position,key[2])
            push!(volume,sum(item.volume for item in batch)); push!(aspirate,1); push!(dispense,0)
            row_idx += 1
            push!(aspirate_row_indices,row_idx)
            push!(batch_sources,key)
            for item in batch
                push!(labware_id,df[item.col,"Destination Labware ID"])
                push!(labware_position,df[item.col,"Destination Position ID"])
                push!(volume,item.volume); push!(aspirate,0); push!(dispense,1)
                row_idx += 1
            end
        end
    end

    action_df = DataFrame(
        "Labware ID" => labware_id,
        "Labware Position ID" => labware_position,
        "Volume (uL)" => volume,
        "Aspirate" => aspirate,
        "Dispense" => dispense,
        "Change Tip Before" => zeros(Int,row_idx),
    )
    return action_df, aspirate_row_indices, batch_sources
end



"""
    write_instrument_files(directory, design, source, target, config::Configuration{Nimbus}, slotting=slotting_greedy(...); batch_ordering::Symbol=:greedy, kwargs...)

Compile a `design` into a Nimbus protocol CSV written to `directory`. Unlike the generic
compiler fallback, the Nimbus supports one-to-many aspirate/dispense: for each source well, as
many destination dispenses as fit within the channel's capacity are drawn up in a single
aspirate and dispensed together, rather than aspirating once per destination (see
[`batch_design`](@ref) for the batching/ordering pipeline). `batch_ordering` selects how
dispenses within a batch are sequenced -- `:greedy` (default, nearest-neighbor) or `:exact`
(optimal, brute-force -- only tractable for small batches, see [`order_exact`](@ref)) -- and can
be benchmarked against each other by calling `pourfecto`/`compile` with either value.

The written CSV uses a unified action-row schema: `"Labware ID","Labware Position ID",
"Volume (uL)","Aspirate","Dispense","Change Tip Before"`. Each row is either an aspirate action
(source well, `Aspirate=1`) or a dispense action (`Dispense=1`); an aspirate row is always
immediately followed by the dispense rows it feeds, whose volumes sum to the aspirate's volume.
`"Change Tip Before"` is `1` on an aspirate row when the tip should be changed before that
aspirate: always on a source change, and periodically thereafter per the instrument's
`"max_tip_use"` setting (see [`tip_change_flags`](@ref)) -- note `"max_tip_use"` now counts
aspirate *batches*, not individual dispense shots.
"""
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Nimbus},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);batch_ordering::Symbol=:greedy,kwargs...)
    # input error handling
    S,T = size(design)
    S == sum(length.(source)) && T == sum(length.(target)) || ArgumentError("Dimension mismatch between design ($S x $T) and number of wells in the source and target labware ($(sum(length.(source))) x $(sum(length.(target))) )")
    all(map(x-> x in keys(slotting),vcat(source,target)))|| ArgumentError("All labware must be slotted")
    allunique(values(slotting)) || ArgumentError("Only one labware can be assigned to a given slot")
    df=convert_design(design,source,target,slotting,config)

    action_df,aspirate_row_indices,batch_sources = batch_design(df,config;batch_ordering)
    action_df[aspirate_row_indices,"Change Tip Before"] .= tip_change_flags(batch_sources,settings(config)["max_tip_use"])

    if ~isdir(directory)
        mkdir(directory)
    end

    CSV.write(joinpath(directory,basename(directory)*".csv"),action_df)
    return nothing
end
