# Compile-time support for the 4-channel Nimbus (`NimbusFourChannel`). Deliberately independent
# from `instruments/Nimbus.jl` -- no calls into that file's `convert_design`/`batch_design`/
# `write_instrument_files`, even where the logic would be channel-count-agnostic -- per the
# project's explicit "separate compiling endpoints" requirement. Reuses only the genuinely
# instrument-agnostic primitives from `compiler/batching.jl` (`DispenseItem`, `split_oversized`,
# `order_batch`/`grid_distance`, `round_with_exact_sum`, `tip_change_flags`) and the package-wide
# well-name helpers from `default_labware.jl` (`well_to_cartesian`/`cartesian_to_well`).
#
# See `Pourfecto/src/instruments/templates/nimbus_4_channel_explanation.txt` and
# `.../esthetically_sticking_multichannel_rounding.csv` for the real reference protocol this
# module's output schema is modeled on.
#
# Compiling model ("tip tied to reagent", established through design discussion after inspecting a
# real example run): each of up to n_channels reagents is permanently assigned to one physical
# channel for a whole continuous tip session (its complete demand, start to finish, before that
# channel's tip changes to a different reagent). Dispense ORDER is decided by a three-phase
# sweep-based pipeline, not per-reagent independent nearest-neighbor tours:
#   1. compute_dispense_windows -- per destination target, pool ALL channels' demand and greedily
#      group it into the fewest simultaneous windows (a channel's row is never constrained on its
#      own; only *simultaneous* multi-channel addressing is constrained by physical spacing).
#   2. order_windows -- nearest-neighbor tour over the resulting windows (reusing order_batch).
#   3. assemble_windows -- realize the ordered windows, inserting per-channel capacity-driven
#      Aspirate/TipPickup/TipDisposal/Blowout events without ever splitting a window's group.
# This replaced an earlier "opportunistic merge only" baseline (each reagent's own independent
# cluster_batches/order_batch tour, cross-channel alignment only discovered after the fact by
# comparing channels' current queue items) once simulation against a real example showed that
# baseline captured very little of the available parallelism (190 dispense rows vs. 123 achievable
# via the sweep, further reduced by nearest-neighbor window ordering). Aspirate-side merging (two
# channels reloading from co-located sources at once) and reagent-to-channel reassignment when
# reagent count exceeds channel count remain explicit, separate follow-up work -- see a relevant
# reference on the latter's tractability: PMC12360158, which reports exact routing solves become
# intractable past ~100 jobs (our own protocols already exceed that).

"""
    nimbus_4ch_well(position::DeckPosition, slot::Int) -> String

Translate a bare linear slot index into a well-name string ("A1", "B3", ...), same convention as
[`nimbus_well`](@ref) in `instruments/Nimbus.jl` -- reimplemented independently here rather than
called into, per this module's "no shared code paths with Nimbus.jl" design decision.
"""
nimbus_4ch_well(position::DeckPosition,slot::Int) = cartesian_to_well(CartesianIndices(slots(position))[slot])

## Waste conical -- same physical reserved slot as single-channel Nimbus (same real hardware),
## defined independently so this file has no reference into Nimbus.jl's own bindings.
const nimbus_4ch_waste_conical = build_location(CHESSCore.location_kinds[:Conical50],"NimbusFourChannelWasteConical")
const nimbus_4ch_waste_slot = 5
const nimbus_4ch_waste_target = (tuberack50mL_0006_4ch.name,nimbus_4ch_well(tuberack50mL_0006_4ch,nimbus_4ch_waste_slot))

"""
    slotting_greedy(labware::Vector{<:Labware}, config::Configuration{NimbusFourChannel}) -> SlottingDict

Pins [`nimbus_4ch_waste_conical`](@ref) to its fixed physical slot before delegating to the generic
`slotting_greedy`, mirroring single-channel Nimbus's own override (reimplemented independently, per
this module's design decisions).
"""
function slotting_greedy(labware::Vector{<:Labware},config::Configuration{NimbusFourChannel})
    pinned = SlottingDict(nimbus_4ch_waste_conical => (tuberack50mL_0006_4ch,nimbus_4ch_waste_slot))
    return slotting_greedy(vcat(labware,[nimbus_4ch_waste_conical]),config;pinned)
end

"""
    convert_design_four_channel(design, sources, targets, slotting, config::Configuration{NimbusFourChannel}) -> DataFrame

Flatten `design` (a source-well x destination-well volume matrix) into a per-transfer row list,
analogous in shape to single-channel Nimbus's `convert_design` but written independently (per this
module's design decisions) and carrying one extra column, `"Destination Kind"` (the destination
labware's `CHESSCore.LocationKind` name), which [`batch_design_four_channel`](@ref) needs to look up
the correct minimum row spacing ([`four_channel_row_spacing`](@ref)) per destination labware.
"""
function convert_design_four_channel(design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},slotting::SlottingDict,config::Configuration{NimbusFourChannel})
    all(map(x-> x[1] in deck(config),values(slotting))) || throw(ArgumentError("All deck positions in the SlottingDict must be present on the deck"))
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
    destination_kind=Symbol[]

    for row in 1:nrow(design)
        source = sources[src_idx[row]]
        s_slot,s_pos = slotting[source]
        for col in 1:ncol(design)
            design[row,col] == 0 && continue
            push!(source_id,s_slot.name)
            if length(source) == 1
                push!(source_position,nimbus_4ch_well(s_slot,s_pos))
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(source))[within_src_index[row]])
                push!(source_position,pos)
            end
            push!(volume,design[row,col])
            destination = targets[tgt_idx[col]]
            d_slot,d_pos = slotting[destination]
            push!(destination_id,d_slot.name)
            if length(destination) == 1
                push!(destination_position,nimbus_4ch_well(d_slot,d_pos))
            else
                pos = cartesian_to_well(CartesianIndices(CHESSCore.children(destination))[within_tgt_index[col]])
                push!(destination_position,pos)
            end
            push!(destination_kind,kind(destination).name)
        end
    end

    return DataFrame("Source Labware ID"=>source_id,
        "Source Position ID"=>source_position,
        "Volume (uL)"=>volume,
        "Destination Labware ID"=>destination_id,
        "Destination Position ID"=>destination_position,
        "Destination Kind"=>destination_kind,
    )
end

"""
    channel_row(offset::Integer, channel::Integer, spacing::Integer) -> Int

The well-row a given physical `channel` (1-indexed, respecting the head's fixed order --
channel 1 always physically above channel 2, above channel 3, above channel 4) sits at, for a
window whose channel-1 row is `offset`: `offset + (channel-1)*spacing`. Used by
[`_dispense_compatible`](@ref) as the compatibility check for whether two channels' current rows
can be addressed simultaneously -- **not** as a constraint on which rows any one channel may visit
(see this file's header comment: under the current "tip tied to reagent" model, a channel's own
schedule is free to visit any row its reagent needs, in any order; only *simultaneous* multi-channel
addressing is constrained by physical spacing).
"""
channel_row(offset::Integer,channel::Integer,spacing::Integer) = offset + (channel-1)*spacing

"""
    DispenseWindow(labware_id, dest_kind, column, offset, active)

One physically-simultaneous dispense action: `active` is a list of `(channel, item::DispenseItem)`
pairs, one per participating channel, all sharing `column` and satisfying the spacing relationship
`item.position[1] == offset + (channel-1)*spacing` (see [`channel_row`](@ref)) for every channel in
`active`. Produced by [`compute_dispense_windows`](@ref), consumed (after [`order_windows`](@ref)
picks a visiting sequence) by the assembly step in [`batch_design_four_channel`](@ref).
"""
struct DispenseWindow
    labware_id::String
    dest_kind::Symbol
    column::Int
    offset::Int
    active::Vector{Tuple{Int,DispenseItem}}
end

"""
    compute_dispense_windows(demand_by_channel::Dict{Int,Vector{DispenseItem}}, n_channels::Integer,
                              labware_id::AbstractString, dest_kind::Symbol, spacing::Integer) -> Vector{DispenseWindow}

Phase 1 of the sweep-based dispense-ordering pipeline: greedily group the pending demand for one
`(destination labware, destination kind)` target, **pooled across every channel** that has demand
there (not per-reagent), into the fewest possible simultaneous windows. `demand_by_channel[c]` is
channel `c`'s already-`split_oversized` `DispenseItem`s for this target (missing/empty for an
unassigned or unaffected channel).

For each column with any pending demand: repeatedly pick the window offset that currently
satisfies the most not-yet-claimed `(channel, row)` pairs (ties broken by iteration order),
claim those channels' items, and repeat until every item in that column is claimed. This is a
greedy, not provably-optimal, per-column set cover -- the same heuristic validated by simulation
against the real 4-reagent/50%-coverage example (593 -> 123 dispense-row reduction) -- matching
this project's existing precedent of `cluster_batches` also being a heuristic, not an exact solver.
Windows are returned in an arbitrary (column-major) order; see [`order_windows`](@ref) for the
actual visiting sequence.
"""
function compute_dispense_windows(demand_by_channel::Dict{Int,Vector{DispenseItem}}, n_channels::Integer,
    labware_id::AbstractString, dest_kind::Symbol, spacing::Integer)
    windows = DispenseWindow[]
    columns = sort(unique(it.position[2] for items in values(demand_by_channel) for it in items))
    for col in columns
        # pending[c]: this channel's still-unclaimed items at this column (list, not set, so a
        # channel with >1 item at the same well -- possible after split_oversized -- is handled
        # correctly, one occurrence claimed per window rather than being collapsed).
        pending = Dict{Int,Vector{DispenseItem}}()
        for c in 1:n_channels
            haskey(demand_by_channel,c) || continue
            items = filter(it -> it.position[2] == col, demand_by_channel[c])
            isempty(items) || (pending[c] = items)
        end
        isempty(pending) && continue
        claimed = Dict{Int,Vector{Bool}}(c => falses(length(v)) for (c,v) in pending)

        while any(!all(claimed[c]) for c in keys(pending))
            candidates = Set{Int}()
            for (c,items) in pending, (idx,it) in enumerate(items)
                claimed[c][idx] && continue
                push!(candidates, it.position[1] - (c-1)*spacing)
            end
            best_offset = 0; best_hits = Tuple{Int,Int,DispenseItem}[]
            for offset in candidates
                hits = Tuple{Int,Int,DispenseItem}[]
                for (c,items) in pending
                    row_c = offset + (c-1)*spacing
                    idx = findfirst(i -> !claimed[c][i] && items[i].position[1] == row_c, eachindex(items))
                    isnothing(idx) || push!(hits,(c,idx,items[idx]))
                end
                if length(hits) > length(best_hits)
                    best_offset = offset; best_hits = hits
                end
            end
            for (c,idx,it) in best_hits
                claimed[c][idx] = true
            end
            push!(windows, DispenseWindow(labware_id,dest_kind,col,best_offset,[(c,it) for (c,idx,it) in best_hits]))
        end
    end
    return windows
end

"""
    order_windows(windows::Vector{DispenseWindow}; method::Symbol=:greedy) -> Vector{DispenseWindow}

Phase 2: find a nearest-neighbor visiting order over `windows` that minimizes total Euclidean
travel distance between consecutive windows, treating each window as a point at `(offset,column)`.
Directly reuses `batching.jl`'s existing, unmodified `order_batch`/`grid_distance` (genuinely
instrument-agnostic tour logic) by wrapping each window as a position-bearing `DispenseItem`
stand-in (`.col` repurposed as an index back into `windows`, `.volume` unused). `method` is
`:greedy` (default, unbounded) or `:exact` (optimal, but `order_exact` silently falls back to
greedy with a warning above its existing `_order_exact_max_items` cap).
"""
function order_windows(windows::Vector{DispenseWindow}; method::Symbol=:greedy)
    isempty(windows) && return windows
    stand_ins = [DispenseItem(i,CartesianIndex(w.offset,w.column),0.0) for (i,w) in enumerate(windows)]
    ordered = order_batch(stand_ins,method)
    return [windows[it.col] for it in ordered]
end

"""
    channel_event_sequence(ordered_windows::Vector{DispenseWindow}, channel::Integer) -> Vector{Tuple{Int,DispenseItem}}

Extract one channel's own `(window_index, item)` pairs from the globally-ordered window sequence,
in that same order -- this is the channel's effective visiting order, now driven by Phase 1/2
(the sweep + nearest-neighbor tour) rather than an independent `cluster_batches`/`order_batch` run.
"""
function channel_event_sequence(ordered_windows::Vector{DispenseWindow}, channel::Integer)
    events = Tuple{Int,DispenseItem}[]
    for (widx,w) in enumerate(ordered_windows), (c,it) in w.active
        c == channel && push!(events,(widx,it))
    end
    return events
end

"""
    pack_into_cycles(events::Vector{Tuple{Int,DispenseItem}}, effective_capacity::Real) -> Vector{Vector{Tuple{Int,DispenseItem}}}

Forward-greedy capacity-bounded chunking of an already-ordered event sequence into aspirate
cycles -- preserves the given order (unlike `cluster_batches`, which reclusters by proximity); the
order itself was already decided by Phase 1/2, so reclustering here would undo that work. Each
item is assumed already `<= effective_capacity` (via `split_oversized`), so every cycle gets at
least one item and the chunking always terminates.
"""
function pack_into_cycles(events::Vector{Tuple{Int,DispenseItem}}, effective_capacity::Real)
    cycles = Vector{Tuple{Int,DispenseItem}}[]
    current = Tuple{Int,DispenseItem}[]
    used = 0.0
    for (widx,it) in events
        if !isempty(current) && used + it.volume > effective_capacity
            push!(cycles,current)
            current = Tuple{Int,DispenseItem}[]
            used = 0.0
        end
        push!(current,(widx,it))
        used += it.volume
    end
    isempty(current) || push!(cycles,current)
    return cycles
end

# Per-cycle aspirate volume / rounded dispense volumes / trailing-blowout flag / tip-change flag,
# for one channel's cycles -- same rounding/headroom/blowout math as the project's existing
# single-channel Nimbus batch_design (round_with_exact_sum, tip_change_flags for periodic
# max_tip_use refresh), just computed once per channel ahead of the window walk instead of
# interleaved with it.
function channel_cycle_data(cycles::Vector{Vector{Tuple{Int,DispenseItem}}}, source_key::Tuple{String,Union{String,Integer}},
    capacity::Real, volume_precision::Int, insert_blowouts::Bool, dead_volume_buffer::Real, aspirate_buffer::Real, max_tip_use::Int)
    n = length(cycles)
    flags = tip_change_flags(fill(source_key,n),max_tip_use)
    data = NamedTuple{(:aspirate_volume,:rounded,:has_trailing_blowout,:tip_change),Tuple{Float64,Vector{Float64},Bool,Int}}[]
    for (i,cycle) in enumerate(cycles)
        has_trailing_blowout = insert_blowouts && i < n && flags[i+1] == 0
        raw = [it.volume for (widx,it) in cycle]
        values = has_trailing_blowout ? vcat(raw,dead_volume_buffer) : raw
        rounded = round_with_exact_sum(values,volume_precision)
        aspirate_volume = sum(rounded) + aspirate_buffer
        aspirate_volume <= capacity + 1e-9 || throw(ArgumentError("channel_cycle_data: rounded aspirate volume $aspirate_volume µL for source $source_key (cycle $i of $n) exceeds channel capacity $capacity µL"))
        push!(data,(aspirate_volume=aspirate_volume,rounded=rounded,has_trailing_blowout=has_trailing_blowout,tip_change=flags[i]))
    end
    return data
end

"""
    assemble_windows(ordered_windows, n_channels, source_keys_by_channel, capacity, effective_capacity;
                      volume_precision, insert_blowouts, waste_target, dead_volume_buffer,
                      aspirate_buffer, max_tip_use, priming, priming_volume, priming_target) -> DataFrame

Phase 3: walk `ordered_windows` (Phase 1/2's globally-ordered, already-grouped dispense sequence)
and emit the final wide-schema action rows. For each window, any participating channel that's
about to start a new aspirate cycle (per [`pack_into_cycles`](@ref), computed once per channel
ahead of this walk) gets its `TipPickup`/`Aspirate`/priming emitted **first**, as its own
single-channel row(s); the window's own `Dispense` row is then emitted exactly as grouped by
Phase 1 -- **the group is never split**, only preceded by whichever channels needed a top-up.
Once a channel finishes its last item in a cycle, a trailing `Blowout` is emitted if that cycle's
`has_trailing_blowout` flag is set; once a channel finishes its very last cycle, `TipDisposal` is
emitted immediately (independently per channel, not waiting for the others).

This supersedes `merge_schedules`'s role: since Phase 1 already decided which channels fire
together, this assembly step no longer needs to *discover* alignment via a live compatibility
check -- it just realizes the precomputed plan, inserting per-channel capacity interruptions
without disturbing the groups themselves.
"""
function assemble_windows(ordered_windows::Vector{DispenseWindow}, n_channels::Integer,
    source_keys_by_channel::Dict{Int,Tuple{String,Union{String,Integer}}}, capacity::Real, effective_capacity::Real;
    volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01, max_tip_use::Int,
    priming::Bool=false, priming_volume::Real=50.0, priming_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing)

    cycles = Dict{Int,Vector{Vector{Tuple{Int,DispenseItem}}}}()
    cdata = Dict{Int,Any}()
    for c in 1:n_channels
        haskey(source_keys_by_channel,c) || continue
        events = channel_event_sequence(ordered_windows,c)
        isempty(events) && continue
        cyc = pack_into_cycles(events,effective_capacity)
        cycles[c] = cyc
        cdata[c] = channel_cycle_data(cyc,source_keys_by_channel[c],capacity,volume_precision,insert_blowouts,dead_volume_buffer,aspirate_buffer,max_tip_use)
    end

    out_labware = String[]
    out_positions = [String[] for _ in 1:n_channels]
    out_volumes = [Float64[] for _ in 1:n_channels]
    out_action = String[]
    none_slot() = ("None",0.0)

    function emit_row!(action::AbstractString, labware_for_row::AbstractString, per_channel::Dict{Int,Tuple{String,Float64}})
        push!(out_labware,labware_for_row)
        push!(out_action,action)
        for c in 1:n_channels
            if haskey(per_channel,c)
                pos,vol = per_channel[c]
                push!(out_positions[c],pos); push!(out_volumes[c],vol)
            else
                p,v = none_slot(); push!(out_positions[c],p); push!(out_volumes[c],v)
            end
        end
    end

    # (cycle index, index within that cycle) for a channel's 1-based cumulative progress count
    function locate(c::Int, idx1based::Int)
        cum = 0
        for (ci,cyc) in enumerate(cycles[c])
            idx1based <= cum + length(cyc) && return ci, idx1based - cum
            cum += length(cyc)
        end
        error("assemble_windows: progress index out of range for channel $c")
    end

    progress = zeros(Int,n_channels)
    for w in ordered_windows
        for (c,it) in w.active
            progress[c] += 1
            ci,within = locate(c,progress[c])
            within == 1 || continue
            key = source_keys_by_channel[c]
            if ci > 1 && cdata[c][ci].tip_change == 1
                emit_row!("TipDisposal","None",Dict(c=>("Dispose",0.0)))
                emit_row!("TipPickup","None",Dict(c=>("Pickup",0.0)))
            elseif ci == 1
                emit_row!("TipPickup","None",Dict(c=>("Pickup",0.0)))
            end
            emit_row!("Aspirate",key[1],Dict(c=>(string(key[2]),cdata[c][ci].aspirate_volume)))
            if priming
                ptarget = isnothing(priming_target) ? key : priming_target
                emit_row!("Dispense",ptarget[1],Dict(c=>(string(ptarget[2]),priming_volume)))
            end
        end

        per_channel = Dict{Int,Tuple{String,Float64}}()
        for (c,it) in w.active
            ci,within = locate(c,progress[c])
            per_channel[c] = (cartesian_to_well(it.position),cdata[c][ci].rounded[within])
        end
        emit_row!("Dispense",w.labware_id,per_channel)

        for (c,it) in w.active
            ci,within = locate(c,progress[c])
            within == length(cycles[c][ci]) || continue
            if cdata[c][ci].has_trailing_blowout
                emit_row!("Blowout",waste_target[1],Dict(c=>(string(waste_target[2]),cdata[c][ci].rounded[end])))
            end
            ci == length(cycles[c]) && emit_row!("TipDisposal","None",Dict(c=>("Dispose",0.0)))
        end
    end

    result = DataFrame("Labware ID"=>out_labware)
    for c in 1:n_channels
        result[!,"Labware Position $c"] = out_positions[c]
        result[!,"Volume $c"] = out_volumes[c]
    end
    result[!,"Action"] = out_action
    return result[:, vcat(["Labware ID"],vcat([["Labware Position $c","Volume $c"] for c in 1:n_channels]...),["Action"])]
end

"""
    batch_design_four_channel(df::DataFrame, config::Configuration{NimbusFourChannel};
                               n_channels, volume_precision, insert_blowouts, waste_target,
                               dead_volume_buffer, aspirate_buffer, priming, priming_volume,
                               priming_target) -> DataFrame

Group `convert_design_four_channel`'s flat transfer list by reagent (source), assign each reagent
to one physical channel (first-appearance order; **requires reagent count <= n_channels** --
reassignment when there are more distinct reagents than channels is explicit follow-up work, not
supported here), then run the three-phase sweep-based dispense-ordering pipeline:

1. [`compute_dispense_windows`](@ref) -- per `(destination labware, destination kind)` target,
   pooling demand across every channel with items there, greedily group into the fewest possible
   simultaneous windows.
2. [`order_windows`](@ref) -- find a nearest-neighbor visiting order over each target's windows
   (reusing `batching.jl`'s existing tour machinery), concatenated across targets in
   first-appearance order.
3. [`assemble_windows`](@ref) -- realize the ordered windows as the final wide-schema action
   sequence, inserting per-channel capacity-driven `TipPickup`/`Aspirate`/`Blowout`/`TipDisposal`
   events without ever splitting a window's group.

See each function's docstring for the full pipeline detail.
"""
function batch_design_four_channel(df::DataFrame, config::Configuration{NimbusFourChannel};
    n_channels::Int=settings(config)["n_channels"],
    volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_4ch_waste_target,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01,
    priming::Bool=false, priming_volume::Real=50.0, priming_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing)

    capacity = ustrip(uconvert(u"µL", dispense_channels(head(config))[1].capacity))
    rounding_margin = 0.5 * 10.0^(-volume_precision)

    if insert_blowouts
        isnothing(waste_target) && throw(ArgumentError("batch_design_four_channel: insert_blowouts=true requires a waste_target (labware id, position)"))
        dead_volume_buffer > 0 || throw(ArgumentError("batch_design_four_channel: insert_blowouts=true requires dead_volume_buffer > 0"))
    end
    aspirate_buffer >= 0 || throw(ArgumentError("batch_design_four_channel: aspirate_buffer must be >= 0"))
    if priming
        priming_volume > 0 || throw(ArgumentError("batch_design_four_channel: priming_volume must be > 0 when priming=true"))
    end
    reserved = aspirate_buffer + (insert_blowouts ? dead_volume_buffer : 0.0) + rounding_margin
    reserved < capacity || throw(ArgumentError("batch_design_four_channel: aspirate_buffer + dead_volume_buffer + rounding margin ($reserved) must be less than channel capacity ($capacity)"))
    effective_capacity = capacity - reserved

    # group rows by reagent (source), preserving first-appearance order -> channel assignment
    source_keys = Tuple{String,Union{String,Integer}}[]
    row_groups = Dict{Tuple{String,Union{String,Integer}},Vector{Int}}()
    for row in 1:nrow(df)
        key = (df[row,"Source Labware ID"],df[row,"Source Position ID"])
        if !haskey(row_groups,key)
            row_groups[key] = Int[]
            push!(source_keys,key)
        end
        push!(row_groups[key],row)
    end
    length(source_keys) <= n_channels || throw(ArgumentError("batch_design_four_channel: $(length(source_keys)) distinct reagents exceeds the $n_channels available channels -- reassigning channels across more reagents than channels is not yet supported (explicit follow-up work)"))

    source_keys_by_channel = Dict{Int,Tuple{String,Union{String,Integer}}}(c=>source_keys[c] for c in eachindex(source_keys))

    # per-channel, already-split_oversized items, grouped by (destination labware, destination kind)
    demand_by_group = Dict{Tuple{String,Symbol},Dict{Int,Vector{DispenseItem}}}()
    group_order = Tuple{String,Symbol}[]
    for c in eachindex(source_keys)
        rows = row_groups[source_keys[c]]
        items = [DispenseItem(r,well_to_cartesian(df[r,"Destination Position ID"]),df[r,"Volume (uL)"]) for r in rows]
        items = split_oversized(items,effective_capacity)
        for it in items
            key = (df[it.col,"Destination Labware ID"],df[it.col,"Destination Kind"])
            if !haskey(demand_by_group,key)
                demand_by_group[key] = Dict{Int,Vector{DispenseItem}}()
                push!(group_order,key)
            end
            push!(get!(demand_by_group[key],c,DispenseItem[]),it)
        end
    end

    max_tip_use = settings(config)["max_tip_use"]
    ordered_windows = DispenseWindow[]
    for (labware_id,dest_kind) in group_order
        spacing = four_channel_row_spacing(dest_kind)
        windows = compute_dispense_windows(demand_by_group[(labware_id,dest_kind)],n_channels,labware_id,dest_kind,spacing)
        append!(ordered_windows,order_windows(windows))
    end

    return assemble_windows(ordered_windows,n_channels,source_keys_by_channel,capacity,effective_capacity;
        volume_precision,insert_blowouts,waste_target,dead_volume_buffer,aspirate_buffer,max_tip_use,
        priming,priming_volume,priming_target)
end

"""
    write_instrument_files(directory, design, source, target, config::Configuration{NimbusFourChannel},
                            slotting=slotting_greedy(...); n_channels, volume_precision,
                            insert_blowouts, waste_target, dead_volume_buffer, aspirate_buffer,
                            priming, priming_volume, priming_target, kwargs...)

Compile a `design` into a 4-channel Nimbus protocol CSV written to `directory`. See
[`batch_design_four_channel`](@ref) for the full sweep/order/assembly pipeline (and for what each
named keyword controls). This is a standalone compile entry point, independent of single-channel
Nimbus's `write_instrument_files` (see this file's header comment).

Named keywords are forwarded to `batch_design_four_channel`; any other keyword (`kwargs...`) is
accepted and silently dropped, not forwarded further -- mirroring single-channel Nimbus's own
`write_instrument_files`. This matters because `pourfecto(directory,...)`'s single-call form
forwards the *same* keyword set to both the solve (e.g. `optimizer=SCIP.Optimizer`) and the
compile stage (`compile(directory,pourcast;kwargs...)`, `Pourfecto/src/compiler/compile.jl:69`) --
without a catch-all here, a solve-only keyword like `optimizer` would otherwise reach
`batch_design_four_channel` (which has no catch-all of its own) and error.
"""
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{NimbusFourChannel},slotting::SlottingDict=slotting_greedy(vcat(source,target),config);
    n_channels::Int=settings(config)["n_channels"],
    volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_4ch_waste_target,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01,
    priming::Bool=false, priming_volume::Real=50.0, priming_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    kwargs...)
    S,T = size(design)
    S == sum(length.(source)) && T == sum(length.(target)) || throw(ArgumentError("Dimension mismatch between design ($S x $T) and number of wells in the source and target labware ($(sum(length.(source))) x $(sum(length.(target))) )"))
    all(map(x-> x in keys(slotting),vcat(source,target))) || throw(ArgumentError("All labware must be slotted"))
    allunique(values(slotting)) || throw(ArgumentError("Only one labware can be assigned to a given slot"))

    df = convert_design_four_channel(design,source,target,slotting,config)
    action_df = batch_design_four_channel(df,config;n_channels,volume_precision,insert_blowouts,waste_target,dead_volume_buffer,aspirate_buffer,priming,priming_volume,priming_target)

    if ~isdir(directory)
        mkdir(directory)
    end

    CSV.write(joinpath(directory,basename(directory)*".csv"),action_df)
    return nothing
end
