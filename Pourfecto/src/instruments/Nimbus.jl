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
    batch_design(df::DataFrame, config::Configuration{Nimbus}; batch_ordering::Symbol=:greedy,
                 volume_precision::Int=1, insert_blowouts::Bool=false,
                 waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
                 dead_volume_buffer::Real=0.0, polish_clustering::Bool=false,
                 polish_max_iterations::Int=1000) -> DataFrame

Group `convert_design`'s flat source/destination transfer list into one-to-many
aspirate/dispense batches, bounded by the Nimbus channel's dispense capacity, and emit them in
the unified action-row schema `"Labware ID","Labware Position ID","Volume (uL)","Action",
"Change Tip Before"` (`Action` is `"Aspirate"`, `"Dispense"`, or `"Blowout"`).

For each distinct source well (grouped in first-appearance row order), destination transfers are
volume-split against capacity ([`split_oversized`](@ref)), packed into capacity-bounded,
distance-aware batches ([`cluster_batches`](@ref)), and ordered within each batch
([`order_batch`](@ref); `batch_ordering` is `:greedy` or `:exact`).

Volumes are rounded to `volume_precision` decimal places such that each aspirate's own tip-load
cycle sums back to its aspirate volume *exactly* at that precision
([`round_with_exact_sum`](@ref)) -- the last value in the cycle (a dispense, or the blowout when
present) absorbs whatever rounding remainder is needed, rather than every value being rounded
independently, which can otherwise leave a hairline float residual that a strict downstream
`available >= requested` check rejects. If a rounded aspirate volume is ever found to exceed the
channel's true capacity, this throws rather than silently clamping (clamping would silently
reintroduce the same kind of exact-sum mismatch it's meant to prevent).

When `insert_blowouts=true`, a batch that's immediately followed by a re-aspirate under the same
tip (no tip change between them) gets a trailing `Blowout` row at `waste_target`, sized to drain
`dead_volume_buffer` before the next aspirate -- that batch's own aspirate volume is then sized to
cover its dispenses *plus* the buffer (the blowout is the last value in its cycle, so it absorbs
the rounding remainder). `waste_target` (a `(labware id, position)` tuple) and a positive
`dead_volume_buffer` (in µL, `< capacity`) are required when `insert_blowouts=true`. Batch
formation reserves `capacity - dead_volume_buffer` of headroom for *every* batch in this mode
(not just the ones that end up needing a blowout), since which batches need one isn't known until
tip-change flags are computed across the whole design. **This path is opt-in and, per the
generator's own refactor notes, not yet physically validated** -- it changes no behavior unless
explicitly enabled.

When `polish_clustering=true`, an exchange/local-search pass ([`polish_batches`](@ref)) runs on
each source's clustered batches before within-batch ordering, swapping/relocating items between
batches to further reduce total head-travel distance beyond `cluster_batches`'s single greedy
pass, capped at `polish_max_iterations` improving moves. Opt-in; default `false` preserves current
behavior exactly.
"""
function batch_design(df::DataFrame, config::Configuration{Nimbus}; batch_ordering::Symbol=:greedy,
    volume_precision::Int=1, insert_blowouts::Bool=false,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    dead_volume_buffer::Real=0.0, polish_clustering::Bool=false, polish_max_iterations::Int=1000)

    capacity = ustrip(uconvert(u"µL", dispense_channels(head(config))[1].capacity))

    if insert_blowouts
        isnothing(waste_target) && throw(ArgumentError("batch_design: insert_blowouts=true requires a waste_target (labware id, position)"))
        dead_volume_buffer > 0 || throw(ArgumentError("batch_design: insert_blowouts=true requires dead_volume_buffer > 0"))
        dead_volume_buffer < capacity || throw(ArgumentError("batch_design: dead_volume_buffer ($dead_volume_buffer) must be less than channel capacity ($capacity)"))
    end
    effective_capacity = insert_blowouts ? capacity - dead_volume_buffer : capacity

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

    # pass 1: cluster each source's destinations into ordered batches (flat, emission order)
    batches = Vector{DispenseItem}[]
    batch_sources = Tuple{String,Union{String,Integer}}[]
    for key in source_keys
        items = map(groups[key]) do r
            pos = df[r,"Destination Position ID"]
            position = pos isa AbstractString ? well_to_cartesian(pos) : CartesianIndex(1,1)
            DispenseItem(r,position,df[r,"Volume (uL)"])
        end
        clustered = cluster_batches(split_oversized(items,effective_capacity),effective_capacity)
        polished = polish_clustering ? polish_batches(clustered,effective_capacity;max_iterations=polish_max_iterations) : clustered
        for batch in polished
            push!(batches,order_batch(batch,batch_ordering))
            push!(batch_sources,key)
        end
    end

    flags = tip_change_flags(batch_sources,settings(config)["max_tip_use"])

    # pass 2: round each cycle's volumes (folding in a trailing blowout where one is needed) and emit rows
    n = length(batches)
    labware_id=String[]
    labware_position=Union{String,Integer}[]
    volume=Float64[]
    action=String[]
    change_tip=Int[]

    for i in 1:n
        batch = batches[i]
        has_trailing_blowout = insert_blowouts && i < n && flags[i+1] == 0

        raw_volumes = [item.volume for item in batch]
        cycle_values = has_trailing_blowout ? vcat(raw_volumes,dead_volume_buffer) : raw_volumes
        rounded = round_with_exact_sum(cycle_values,volume_precision)
        aspirate_volume = sum(rounded)

        aspirate_volume <= capacity + 1e-9 || throw(ArgumentError("batch_design: rounded aspirate volume $aspirate_volume µL for source $(batch_sources[i]) (batch $i of $n) exceeds channel capacity $capacity µL"))

        push!(labware_id,batch_sources[i][1]); push!(labware_position,batch_sources[i][2])
        push!(volume,aspirate_volume); push!(action,"Aspirate"); push!(change_tip,flags[i])

        for (k,item) in enumerate(batch)
            push!(labware_id,df[item.col,"Destination Labware ID"])
            push!(labware_position,df[item.col,"Destination Position ID"])
            push!(volume,rounded[k]); push!(action,"Dispense"); push!(change_tip,0)
        end

        if has_trailing_blowout
            push!(labware_id,waste_target[1]); push!(labware_position,waste_target[2])
            push!(volume,rounded[end]); push!(action,"Blowout"); push!(change_tip,0)
        end
    end

    return DataFrame(
        "Labware ID" => labware_id,
        "Labware Position ID" => labware_position,
        "Volume (uL)" => volume,
        "Action" => action,
        "Change Tip Before" => change_tip,
    )
end



"""
    write_instrument_files(directory, design, source, target, config::Configuration{Nimbus}, slotting=slotting_greedy(...);
                            batch_ordering::Symbol=:greedy, volume_precision::Int=1, insert_blowouts::Bool=false,
                            waste_target=nothing, dead_volume_buffer::Real=0.0, polish_clustering::Bool=false,
                            polish_max_iterations::Int=1000, kwargs...)

Compile a `design` into a Nimbus protocol CSV written to `directory`. Unlike the generic
compiler fallback, the Nimbus supports one-to-many aspirate/dispense: for each source well, as
many destination dispenses as fit within the channel's capacity are drawn up in a single
aspirate and dispensed together, rather than aspirating once per destination (see
[`batch_design`](@ref) for the full batching/rounding/blowout pipeline). `batch_ordering` selects
how dispenses within a batch are sequenced -- `:greedy` (default, nearest-neighbor) or `:exact`
(optimal, brute-force -- only tractable for small batches, see [`order_exact`](@ref)) -- and can
be benchmarked against each other by calling `pourfecto`/`compile` with either value.

The written CSV uses a unified action-row schema: `"Labware ID","Labware Position ID",
"Volume (uL)","Action","Change Tip Before"`, `Action` being `"Aspirate"`, `"Dispense"`, or
`"Blowout"`. An aspirate row is always immediately followed by the rows it feeds (its dispenses,
and a trailing blowout when `insert_blowouts=true` and a re-aspirate follows under the same tip),
whose volumes sum to the aspirate's volume *exactly* at `volume_precision` decimal places (see
[`round_with_exact_sum`](@ref)). `"Change Tip Before"` is `1` on an aspirate row when the tip
should be changed before that aspirate: always on a source change, and periodically thereafter
per the instrument's `"max_tip_use"` setting (see [`tip_change_flags`](@ref)) -- note
`"max_tip_use"` counts aspirate *batches*, not individual dispense shots. It's always `0` on
`Dispense`/`Blowout` rows.

`insert_blowouts`, `waste_target`, and `dead_volume_buffer` control the (opt-in, not yet
physically validated) dead-volume Blowout path -- see [`batch_design`](@ref).

`polish_clustering` (and `polish_max_iterations`) enable an exchange/local-search pass over
`cluster_batches`'s output to further reduce head-travel distance -- see
[`polish_batches`](@ref) and [`batch_design`](@ref). Opt-in; default `false` preserves current
behavior exactly.
"""
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Nimbus},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);
    batch_ordering::Symbol=:greedy, volume_precision::Int=1, insert_blowouts::Bool=false,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    dead_volume_buffer::Real=0.0, polish_clustering::Bool=false, polish_max_iterations::Int=1000, kwargs...)
    # input error handling
    S,T = size(design)
    S == sum(length.(source)) && T == sum(length.(target)) || ArgumentError("Dimension mismatch between design ($S x $T) and number of wells in the source and target labware ($(sum(length.(source))) x $(sum(length.(target))) )")
    all(map(x-> x in keys(slotting),vcat(source,target)))|| ArgumentError("All labware must be slotted")
    allunique(values(slotting)) || ArgumentError("Only one labware can be assigned to a given slot")
    df=convert_design(design,source,target,slotting,config)

    action_df = batch_design(df,config;batch_ordering,volume_precision,insert_blowouts,waste_target,dead_volume_buffer,polish_clustering,polish_max_iterations)

    if ~isdir(directory)
        mkdir(directory)
    end

    CSV.write(joinpath(directory,basename(directory)*".csv"),action_df)
    return nothing
end
