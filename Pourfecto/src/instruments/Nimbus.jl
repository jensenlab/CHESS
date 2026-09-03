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
tuberack15mL_0001=ConstrainedPosition("TubeRack15ML_WellNames_0001",Set([:Conical15]),(4,6),true,true,"circle")
# 50 mL tube
tuberack50mL_0001=ConstrainedPosition("TubeRack50ML_WellNames_0001",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0002=ConstrainedPosition("TubeRack50ML_WellNames_0002",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0003=ConstrainedPosition("TubeRack50ML_WellNames_0003",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0004=ConstrainedPosition("TubeRack50ML_WellNames_0004",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0005=ConstrainedPosition("TubeRack50ML_WellNames_0005",Set([:Conical50]),(2,3),true,true,"circle")
tuberack50mL_0006=ConstrainedPosition("TubeRack50ML_WellNames_0006",Set([:Conical50]),(2,3),true,true,"circle")

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



"""
    nimbus_well(position::DeckPosition, slot::Int) -> String

Translate a bare linear slot index (as produced by the shared, `Int`-typed
[`slotting_greedy`](@ref)/`SlottingDict` machinery) into an unambiguous well-name string (`"A1"`,
`"B3"`, ...) using `position`'s `(rows,cols)` grid shape. This is the fix for a physical
mis-pipetting bug: a bare integer slot number had no documented row-major/column-major convention
tying it to a real tube position on the deck, so it could mean different physical slots to
Pourfecto than to a human reading the Nimbus software/deck layout. Uses the same
`CartesianIndices`/[`cartesian_to_well`](@ref) convention already applied to plate wells elsewhere
in this file (`convert_design`'s `CartesianIndices(CHESSCore.children(...))`), so a rack slot `i`
and a plate well `i` are numbered consistently.
"""
nimbus_well(position::DeckPosition,slot::Int) = cartesian_to_well(CartesianIndices(slots(position))[slot])

## Nimbus Waste Conical
#
# One slot on the physical Nimbus deck permanently holds a Conical50 tube used as liquid waste for
# the Blowout path (see batch_design's insert_blowouts) -- a real, always-present piece of hardware,
# not something chosen per-protocol. TubeRack50ML_WellNames_0006, well A3 is the slot nearest the tip
# rack and waste area on the real deck. This is reserved unconditionally (every Nimbus compile,
# whether or not that particular protocol uses insert_blowouts), since the tube is physically there
# regardless.
#
# nimbus_waste_slot stays a plain Int: it's only used to pin the reserved slot in the shared,
# Int-typed SlottingDict (see slotting_greedy override below). nimbus_waste_target is the value that
# actually reaches the compiled CSV (as a Blowout row's position), so it's translated to a well
# string via nimbus_well.
const nimbus_waste_conical = build_location(CHESSCore.location_kinds[:Conical50],"NimbusWasteConical")
const nimbus_waste_slot = 5
const nimbus_waste_target = (tuberack50mL_0006.name,nimbus_well(tuberack50mL_0006,nimbus_waste_slot))

"""
    slotting_greedy(labware::Vector{<:Labware}, config::Configuration{Nimbus}) -> SlottingDict

Nimbus-specific override: pins [`nimbus_waste_conical`](@ref) to its fixed physical slot
(`TubeRack50ML_WellNames_0006`, well `$(nimbus_well(tuberack50mL_0006,nimbus_waste_slot))`, nearest the tip rack) before delegating
everything else to the generic [`slotting_greedy`](@ref). That slot is a permanent fixture on the
real Nimbus deck -- excluded from ordinary source/target slotting on every compile, independent of
whether the protocol actually uses the Blowout path, exactly like [`Cobra`](@ref)'s
`packing_greedy` override reflects its own instrument-specific deck constraints.
"""
function slotting_greedy(labware::Vector{<:Labware},config::Configuration{Nimbus})
    pinned = SlottingDict(nimbus_waste_conical => (tuberack50mL_0006,nimbus_waste_slot))
    return slotting_greedy(vcat(labware,[nimbus_waste_conical]),config;pinned)
end



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
                push!(source_position,nimbus_well(s_slot,s_pos))
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(source))[with_src_index[row]])
                push!(source_position,pos)
            end 
            push!(volume,design[row,col])
            destination =targets[tgt_idx[col]]
            d_slot,d_pos = slotting[destination]
            push!(destination_id,d_slot.name)
            if length(destination) == 1
                push!(destination_position,nimbus_well(d_slot,d_pos))
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
                 volume_precision::Int=1, insert_blowouts::Bool=true,
                 waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_waste_target,
                 dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01, polish_clustering::Bool=false,
                 polish_max_iterations::Int=1000) -> DataFrame

Group `convert_design`'s flat source/destination transfer list into one-to-many
aspirate/dispense batches, bounded by the Nimbus channel's dispense capacity, and emit them in
the unified action-row schema `"Labware ID","Labware Position ID","Volume (uL)","Action",
"Change Tip Before"` (`Action` is `"Aspirate"`, `"Dispense"`, or `"Blowout"`).

For each distinct source well (grouped in first-appearance row order), destination transfers are
volume-split against capacity ([`split_oversized`](@ref)), packed into capacity-bounded,
distance-aware batches ([`cluster_batches`](@ref)), and ordered within each batch
([`order_batch`](@ref); `batch_ordering` is `:greedy` or `:exact`).

Dispense/Blowout volumes within a cycle are rounded to `volume_precision` decimal places such that
they sum back to the *unbuffered* portion of the aspirate volume *exactly* at that precision
([`round_with_exact_sum`](@ref)) -- the last value in the cycle (a dispense, or the blowout when
present) absorbs whatever rounding remainder is needed, rather than every value being rounded
independently, which can otherwise leave a hairline float residual that a strict downstream
`available >= requested` check rejects.

The `Aspirate` row itself then adds `aspirate_buffer` on top of that rounded sum
(`aspirate_volume = sum(rounded dispense/blowout values) + aspirate_buffer`) -- a small,
*deliberate* physical safety margin against real-world pipetting inaccuracy (an under-aspiration
or a dispense that loses slightly more than its nominal volume can otherwise leave the tip short
for the last action in a cycle, e.g. a `Blowout`). Unlike the dispense/blowout rows, the aspirate
row is **not** re-rounded to `volume_precision` -- doing so could erase a buffer finer than that
resolution (e.g. the default `aspirate_buffer=0.01` vanishes under the default
`volume_precision=1`, since `round(x+0.01,digits=1) == round(x,digits=1)` in general). This is an
**unconditional default** (unlike every other kwarg here, `aspirate_buffer=0.01` changes existing
default output) since the margin should always be present regardless of `insert_blowouts`.

Batch formation reserves headroom for both `aspirate_buffer` and a **rounding margin** (`0.5 *
10.0^(-volume_precision)`, the worst a raw value can round *up* by) in addition to
`dead_volume_buffer` -- without the rounding margin, a raw cycle volume just under
`capacity - aspirate_buffer` could round up to something that, once `aspirate_buffer` is added,
exceeds true capacity, defeating the purpose of reserving headroom at all. If a computed aspirate
volume is nonetheless ever found to exceed the channel's true capacity, this throws rather than
silently clamping (clamping would silently reintroduce the same kind of exact-sum mismatch Bug 1
was fixed to prevent) -- with the margins above, this should not be reachable through normal use.

When `insert_blowouts=true`, a batch that's immediately followed by a re-aspirate under the same
tip (no tip change between them) gets a trailing `Blowout` row at `waste_target`, sized to drain
`dead_volume_buffer` before the next aspirate -- that batch's own aspirate volume is then sized to
cover its dispenses *plus* the buffer (the blowout is the last value in its cycle, so it absorbs
the rounding remainder). `waste_target` defaults to [`nimbus_waste_target`](@ref) -- the
permanently-reserved waste conical (`TubeRack50ML_WellNames_0006`, well `$(nimbus_well(tuberack50mL_0006,nimbus_waste_slot))`, see
[`slotting_greedy`](@ref)'s `Configuration{Nimbus}` override) -- so callers using the default deck
layout don't need to supply it; pass a different `(labware id, position)` tuple to target something
else. A positive `dead_volume_buffer` (in µL, `< capacity`, default `20.0`) is required when
`insert_blowouts=true`. Batch formation reserves headroom for `dead_volume_buffer` for *every*
batch in this mode (not just the ones that end up needing a blowout), since which batches need one
isn't known until tip-change flags are computed across the whole design, on top of the
`aspirate_buffer`/rounding headroom described above. **`insert_blowouts` defaults to `true`**: a
protocol compiled with no blowout-related kwargs at all still gets `Blowout` rows wherever a
re-aspirate happens under the same tip, draining the default `20.0` µL to the reserved waste
conical. Pass `insert_blowouts=false` explicitly to disable it entirely.

When `polish_clustering=true`, an exchange/local-search pass ([`polish_batches`](@ref)) runs on
each source's clustered batches before within-batch ordering, swapping/relocating items between
batches to further reduce total head-travel distance beyond `cluster_batches`'s single greedy
pass, capped at `polish_max_iterations` improving moves. Opt-in; default `false` preserves current
behavior exactly.
"""
function batch_design(df::DataFrame, config::Configuration{Nimbus}; batch_ordering::Symbol=:greedy,
    volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_waste_target,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01, polish_clustering::Bool=false, polish_max_iterations::Int=1000)

    capacity = ustrip(uconvert(u"µL", dispense_channels(head(config))[1].capacity))
    rounding_margin = 0.5 * 10.0^(-volume_precision)

    if insert_blowouts
        isnothing(waste_target) && throw(ArgumentError("batch_design: insert_blowouts=true requires a waste_target (labware id, position)"))
        dead_volume_buffer > 0 || throw(ArgumentError("batch_design: insert_blowouts=true requires dead_volume_buffer > 0"))
    end
    aspirate_buffer >= 0 || throw(ArgumentError("batch_design: aspirate_buffer must be >= 0"))
    reserved = aspirate_buffer + (insert_blowouts ? dead_volume_buffer : 0.0) + rounding_margin
    reserved < capacity || throw(ArgumentError("batch_design: aspirate_buffer + dead_volume_buffer + rounding margin ($reserved) must be less than channel capacity ($capacity)"))
    effective_capacity = capacity - reserved

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
        aspirate_volume = sum(rounded) + aspirate_buffer

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
                            batch_ordering::Symbol=:greedy, volume_precision::Int=1, insert_blowouts::Bool=true,
                            waste_target=nimbus_waste_target, dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01,
                            polish_clustering::Bool=false, polish_max_iterations::Int=1000, kwargs...)

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
whose volumes sum to `aspirate - aspirate_buffer` *exactly* at `volume_precision` decimal places
(see [`round_with_exact_sum`](@ref)) -- the aspirate carries `aspirate_buffer` extra, a small
unconditional physical safety margin (default `0.01` µL) against real-world pipetting inaccuracy
on the last action in a cycle; see [`batch_design`](@ref) for the full precision/headroom
reasoning. `"Change Tip Before"` is `1` on an aspirate row when the tip should be changed before
that aspirate: always on a source change, and periodically thereafter per the instrument's
`"max_tip_use"` setting (see [`tip_change_flags`](@ref)) -- note `"max_tip_use"` counts aspirate
*batches*, not individual dispense shots. It's always `0` on `Dispense`/`Blowout` rows.

`insert_blowouts`, `waste_target`, and `dead_volume_buffer` control the dead-volume Blowout path
-- see [`batch_design`](@ref). **`insert_blowouts` defaults to `true`, with `dead_volume_buffer`
defaulting to `20.0` µL** -- compiling with none of these three kwargs supplied still inserts
`Blowout` rows wherever a re-aspirate happens under the same tip. `waste_target` defaults to the
permanently-reserved waste conical ([`nimbus_waste_target`](@ref)) automatically excluded from
ordinary source/target slotting (see `slotting_greedy`'s `Configuration{Nimbus}` override), so it
doesn't need to be supplied explicitly either. Pass `insert_blowouts=false` to disable the path
entirely.

`polish_clustering` (and `polish_max_iterations`) enable an exchange/local-search pass over
`cluster_batches`'s output to further reduce head-travel distance -- see
[`polish_batches`](@ref) and [`batch_design`](@ref). Opt-in; default `false` preserves current
behavior exactly.
"""
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{Nimbus},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);
    batch_ordering::Symbol=:greedy, volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_waste_target,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01, polish_clustering::Bool=false, polish_max_iterations::Int=1000, kwargs...)
    # input error handling
    S,T = size(design)
    S == sum(length.(source)) && T == sum(length.(target)) || ArgumentError("Dimension mismatch between design ($S x $T) and number of wells in the source and target labware ($(sum(length.(source))) x $(sum(length.(target))) )")
    all(map(x-> x in keys(slotting),vcat(source,target)))|| ArgumentError("All labware must be slotted")
    allunique(values(slotting)) || ArgumentError("Only one labware can be assigned to a given slot")
    df=convert_design(design,source,target,slotting,config)

    action_df = batch_design(df,config;batch_ordering,volume_precision,insert_blowouts,waste_target,dead_volume_buffer,aspirate_buffer,polish_clustering,polish_max_iterations)

    if ~isdir(directory)
        mkdir(directory)
    end

    CSV.write(joinpath(directory,basename(directory)*".csv"),action_df)
    return nothing
end
