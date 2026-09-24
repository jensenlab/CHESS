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
#      Reload trips are SYNCHRONIZED across channels (compute_synchronized_cycles, Phase 3a):
#      whenever any channel must reload, every channel with outstanding demand reloads at that same
#      window -- ending a cycle early, with unused headroom, if that's what it takes to align --
#      rather than each channel triggering its own isolated trip once its own item happens to come
#      up later in the shared dispense order. A channel's final TipDisposal is deferred the same
#      way, piggybacked onto the next reload trip elsewhere (or one final consolidated wave) instead
#      of firing in isolation. TipPickup/TipDisposal/Blowout always merge across every channel
#      needing the action at the same point in the walk (their target Labware ID is always the same
#      constant); Aspirate merges across channels only when they share the same source Labware ID --
#      none of these four apply the row/column spacing check that Dispense windows use, since
#      (unlike Dispense's rigid simultaneous 4-channel motion) they're position-per-channel commands
#      the Nimbus's own internal logic sequences correctly even when not truly simultaneous.
# This replaced an earlier "opportunistic merge only" baseline (each reagent's own independent
# cluster_batches/order_batch tour, cross-channel alignment only discovered after the fact by
# comparing channels' current queue items) once simulation against a real example showed that
# baseline captured very little of the available parallelism (190 dispense rows vs. 123 achievable
# via the sweep, further reduced by nearest-neighbor window ordering). Reagent-to-channel
# reassignment when reagent count exceeds channel count remains explicit, separate follow-up work --
# see a relevant reference on its tractability: PMC12360158, which reports exact routing solves
# become intractable past ~100 jobs (our own protocols already exceed that).

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
    compute_synchronized_cycles(ordered_windows, channels, channel_items, effective_capacity) ->
        (cycles, trigger_window, disposal_window)

Phase 3a: jointly compute every channel's aspirate-cycle boundaries in **one pass** over
`ordered_windows`, instead of packing each channel's own event sequence independently. Whenever any
channel would run out of pre-loaded capacity for its next item, every channel with outstanding
demand reloads at that **same window** -- ending its current cycle early, with unused headroom, if
that's what it takes to align. This is what lets a channel's `TipPickup`/`Aspirate` fire while the
gantry is already at the tip/source area for another channel, instead of triggering its own later,
isolated trip once its own first (or next) item happens to come up in the shared dispense order.

A channel that exhausts all its demand becomes disposal-due but is never given its own trigger --
its final `TipDisposal` is deferred until the next synchronized reload fires for any other channel
(piggybacked for free), or, if none remains, flushed in one final wave at the last window.

With `synchronized=false` (for benchmarking what synchronization saves), each channel reloads on its
own schedule instead: a trigger refills only the channel(s) that ran out, and a finished channel
disposes right after its own last dispense.

`channel_items[c]` is `channel_event_sequence(ordered_windows,c)` for every channel with any demand
(precomputed by the caller). Each item is assumed already `<= effective_capacity` (via
`split_oversized`), so a fresh cycle always accepts at least one item and the walk always
terminates. Returns `cycles::Dict{Int,Vector{Vector{Tuple{Int,DispenseItem}}}}` (same shape
`channel_cycle_data` already consumes), `trigger_window::Dict{Int,Vector{Int}}`
(`trigger_window[c][ci]` is the window at which cycle `ci` of channel `c` starts loading), and
`disposal::Dict{Int,Tuple{Int,Bool}}`: channel `c`'s final tip disposal fires at window `w`, after
that window's dispense if the flag is `true`, or with that window's reload trip (before the
dispense) if `false`.
"""
function compute_synchronized_cycles(ordered_windows::Vector{DispenseWindow}, channels,
    channel_items::Dict{Int,Vector{Tuple{Int,DispenseItem}}}, effective_capacity::Real; synchronized::Bool=true)

    assigned = Dict(c=>0 for c in channels)
    consumed = Dict(c=>0 for c in channels)
    current = Dict{Int,Vector{Tuple{Int,DispenseItem}}}(c=>Tuple{Int,DispenseItem}[] for c in channels)
    current_vol = Dict(c=>0.0 for c in channels)
    cycles = Dict{Int,Vector{Vector{Tuple{Int,DispenseItem}}}}(c=>Vector{Tuple{Int,DispenseItem}}[] for c in channels)
    trigger_window = Dict{Int,Vector{Int}}(c=>Int[] for c in channels)
    disposal = Dict{Int,Tuple{Int,Bool}}()
    pending_disposal = Set{Int}()

    function refill!(c::Int, at_window::Int)
        if !isempty(current[c])
            push!(cycles[c],current[c])
            current[c] = Tuple{Int,DispenseItem}[]
            current_vol[c] = 0.0
        end
        filled = false
        while assigned[c] < length(channel_items[c])
            widx,it = channel_items[c][assigned[c]+1]
            it.volume <= effective_capacity - current_vol[c] || break
            push!(current[c],(widx,it))
            current_vol[c] += it.volume
            assigned[c] += 1
            filled = true
        end
        filled && push!(trigger_window[c],at_window)
    end

    function do_sync!(at_window::Int)
        for c in channels
            haskey(disposal,c) && continue
            assigned[c] < length(channel_items[c]) && refill!(c,at_window)
        end
        for c in pending_disposal
            disposal[c] = (at_window,false)
        end
        empty!(pending_disposal)
    end

    for (w_idx,w) in enumerate(ordered_windows)
        needing = Int[]
        for (c,it) in w.active
            consumed[c] += 1
            consumed[c] > assigned[c] && push!(needing,c)
        end
        if !isempty(needing)
            synchronized ? do_sync!(w_idx) : foreach(c -> refill!(c,w_idx), needing)
        end
        # exhaustion is checked AFTER the reload (it may itself assign a channel's last items). When
        # synchronized, a channel that finishes here always waits for a later sync: this window's
        # reload trip happens before its last dispense, so riding along on it would mean a second
        # trip back to dispose
        for (c,it) in w.active
            if consumed[c] == assigned[c] == length(channel_items[c]) && !haskey(disposal,c) && !(c in pending_disposal)
                synchronized ? push!(pending_disposal,c) : (disposal[c] = (w_idx,true))
            end
        end
    end
    for c in channels
        isempty(current[c]) || push!(cycles[c],current[c])
    end
    for c in pending_disposal
        disposal[c] = (length(ordered_windows),true)
    end

    return cycles, trigger_window, disposal
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
and emit the final wide-schema action rows. Cycle boundaries are decided **jointly** across all
channels by [`compute_synchronized_cycles`](@ref) (Phase 3a) before this walk begins: whenever any
channel needs to reload, every channel with outstanding demand reloads at that same window (ending
a cycle early, with unused headroom, if needed to align) -- so a channel's `TipPickup`/`Aspirate`
fires while the gantry is already at the tip/source area for another channel, rather than
triggering its own later, isolated trip once its own item happens to come up. At each such
synchronized reload window, a trailing `Blowout` for any channel's just-finished cycle (per
`has_trailing_blowout`) is emitted first, then `TipDisposal` (mid-run tip changes **and** any
channel's now-due final disposal, deferred here rather than firing in isolation), then `TipPickup`,
then `Aspirate`, then priming. The window's own `Dispense` row is then emitted exactly as grouped by
Phase 1 -- **the group is never split**, only preceded by whichever channels needed a top-up.

`TipPickup`/`TipDisposal`/`Blowout` always merge across every channel that needs the action at the
same point in the walk, since their target `Labware ID` is always the same constant (`"None"` for
tip actions, the fixed `waste_target` labware for blowout). `Aspirate` merges across channels only
when they share the same source `Labware ID` -- never based on row/column/spacing compatibility;
unlike `Dispense` (a rigid simultaneous 4-channel motion, hence [`compute_dispense_windows`](@ref)'s
spacing check), these are position-per-channel commands whose sequencing the Nimbus's own internal
logic handles when they aren't actually simultaneous. See [`emit_grouped!`](@ref) (local to this
function).

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
    priming::Bool=false, priming_volume::Real=50.0, priming_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    synchronize_reloads::Bool=true)

    channels = [c for c in 1:n_channels if haskey(source_keys_by_channel,c) && !isempty(channel_event_sequence(ordered_windows,c))]
    channel_items = Dict{Int,Vector{Tuple{Int,DispenseItem}}}(c=>channel_event_sequence(ordered_windows,c) for c in channels)
    cycles,trigger_window,disposal = compute_synchronized_cycles(ordered_windows,channels,channel_items,effective_capacity;synchronized=synchronize_reloads)
    cdata = Dict{Int,Any}(c=>channel_cycle_data(cycles[c],source_keys_by_channel[c],capacity,volume_precision,insert_blowouts,dead_volume_buffer,aspirate_buffer,max_tip_use) for c in channels)

    channels_starting_at = Dict{Int,Vector{Tuple{Int,Int}}}()
    for c in channels, (ci,w_idx) in enumerate(trigger_window[c])
        push!(get!(channels_starting_at,w_idx,Tuple{Int,Int}[]),(c,ci))
    end
    # disposals riding along on a reload trip (before the dispense) vs. after that window's dispense
    riding_at = Dict{Int,Vector{Int}}()
    after_at = Dict{Int,Vector{Int}}()
    for (c,(w_idx,after)) in disposal
        push!(get!(after ? after_at : riding_at,w_idx,Int[]),c)
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

    """
        emit_grouped!(action, entries::Vector{Tuple{Int,String,String,Float64}})

    Emit one row per distinct `labware_id` among `entries` (each `(channel, labware_id, position,
    volume)`), merging every channel that shares a `labware_id` into the same row -- this is the
    "same Labware ID merges, otherwise stays separate" rule for `TipPickup`/`TipDisposal`/`Blowout`
    (constant `labware_id`, always one group) and `Aspirate` (varies by channel's actual source,
    multiple groups possible) alike. Distinct labware values keep their first-appearance order.
    """
    function emit_grouped!(action::AbstractString, entries::Vector{Tuple{Int,String,String,Float64}})
        isempty(entries) && return
        order = String[]
        groups = Dict{String,Dict{Int,Tuple{String,Float64}}}()
        for (c,labware,pos,vol) in entries
            if !haskey(groups,labware)
                groups[labware] = Dict{Int,Tuple{String,Float64}}()
                push!(order,labware)
            end
            groups[labware][c] = (pos,vol)
        end
        for labware in order
            emit_row!(action,labware,groups[labware])
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
    for (w_idx,w) in enumerate(ordered_windows)
        starts = get(channels_starting_at,w_idx,Tuple{Int,Int}[])
        riding_disposals = get(riding_at,w_idx,Int[])
        after_disposals = get(after_at,w_idx,Int[])

        if !isempty(starts) || !isempty(riding_disposals)
            blowout_entries = Tuple{Int,String,String,Float64}[]
            dispose_entries = Tuple{Int,String,String,Float64}[]
            pickup_entries = Tuple{Int,String,String,Float64}[]
            aspirate_entries = Tuple{Int,String,String,Float64}[]
            priming_entries = Tuple{Int,String,String,Float64}[]
            for (c,ci) in starts
                if ci > 1 && cdata[c][ci-1].has_trailing_blowout
                    push!(blowout_entries,(c,waste_target[1],string(waste_target[2]),cdata[c][ci-1].rounded[end]))
                end
                key = source_keys_by_channel[c]
                if ci > 1 && cdata[c][ci].tip_change == 1
                    push!(dispose_entries,(c,"None","Dispose",0.0))
                    push!(pickup_entries,(c,"None","Pickup",0.0))
                elseif ci == 1
                    push!(pickup_entries,(c,"None","Pickup",0.0))
                end
                push!(aspirate_entries,(c,key[1],string(key[2]),cdata[c][ci].aspirate_volume))
                if priming
                    ptarget = isnothing(priming_target) ? key : priming_target
                    push!(priming_entries,(c,ptarget[1],string(ptarget[2]),priming_volume))
                end
            end
            for c in riding_disposals
                push!(dispose_entries,(c,"None","Dispose",0.0))
            end
            emit_grouped!("Blowout",blowout_entries)
            emit_grouped!("TipDisposal",dispose_entries)
            emit_grouped!("TipPickup",pickup_entries)
            emit_grouped!("Aspirate",aspirate_entries)
            priming && emit_grouped!("Dispense",priming_entries)
        end

        per_channel = Dict{Int,Tuple{String,Float64}}()
        for (c,it) in w.active
            progress[c] += 1
            ci,within = locate(c,progress[c])
            per_channel[c] = (cartesian_to_well(it.position),cdata[c][ci].rounded[within])
        end
        emit_row!("Dispense",w.labware_id,per_channel)

        # the end-of-run wave (or, unsynchronized, a channel's own last item) disposes AFTER the
        # dispense: physically the tip dispenses first, then is disposed
        if !isempty(after_disposals)
            emit_grouped!("TipDisposal",Tuple{Int,String,String,Float64}[(c,"None","Dispose",0.0) for c in after_disposals])
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

Group `convert_design_four_channel`'s flat transfer list by reagent (source), split the reagents into
groups of up to `n_channels`, and run each group through the three-phase sweep-based
dispense-ordering pipeline below, one group after another. Within a group, each reagent owns one
channel for its whole tip session. Between groups, all tips swap on one trip: a group's last
`TipDisposal` row is immediately followed by the next group's `TipPickup` row.

Reagents are ordered by physical tube position by default ([`source_position_order`](@ref): labware
id, then column, then row) and chunked into consecutive runs of `n_channels`: chunk *k* is group *k*,
and position within the chunk is the channel. So the tube placement chosen by
[`place_labware`](@ref) decides both grouping and channel order, and a 2-row tube rack's A1, B1, A2,
B2 land on channels 1-4 down the head. `channel_order` overrides this with an explicit list of every
source `(labware id, position)` key, chunked the same way; `place_labware` uses it to score candidate
orders before tubes are moved.

`synchronize_reloads=false` turns off synchronized reload trips (see
[`compute_synchronized_cycles`](@ref)), so each channel reloads and disposes on its own schedule;
it exists to benchmark what synchronization saves.

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
    priming::Bool=false, priming_volume::Real=50.0, priming_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nothing,
    channel_order::Union{Nothing,AbstractVector}=nothing, synchronize_reloads::Bool=true)

    capacity, effective_capacity = four_channel_capacities(config;volume_precision,insert_blowouts,waste_target,dead_volume_buffer,aspirate_buffer)
    if priming
        priming_volume > 0 || throw(ArgumentError("batch_design_four_channel: priming_volume must be > 0 when priming=true"))
    end

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
    if isnothing(channel_order)
        sort!(source_keys,by=source_position_order)
    else
        Set(channel_order) == Set(source_keys) && length(channel_order) == length(source_keys) ||
            throw(ArgumentError("batch_design_four_channel: channel_order must list each source (labware id, position) in the transfer list exactly once"))
        source_keys = collect(Tuple{String,Union{String,Integer}},channel_order)
    end

    # consecutive runs of n_channels reagents are groups, run one after another; each group's last
    # TipDisposal row lands right before the next group's TipPickup row, i.e. one swap trip
    groups = [source_keys[i:min(i+n_channels-1,end)] for i in 1:n_channels:length(source_keys)]
    return vcat([batch_group_four_channel(df,row_groups,g,n_channels,config,capacity,effective_capacity;
        volume_precision,insert_blowouts,waste_target,dead_volume_buffer,aspirate_buffer,
        priming,priming_volume,priming_target,synchronize_reloads) for g in groups]...)
end

# (channel capacity, effective capacity) in µL: the effective capacity reserves headroom for the
# aspirate buffer, the dead volume drained by blowouts, and rounding
function four_channel_capacities(config::Configuration{NimbusFourChannel}; volume_precision::Int=1, insert_blowouts::Bool=true,
    waste_target::Union{Nothing,Tuple{AbstractString,Union{AbstractString,Integer}}}=nimbus_4ch_waste_target,
    dead_volume_buffer::Real=20.0, aspirate_buffer::Real=0.01)
    capacity = ustrip(uconvert(u"µL", dispense_channels(head(config))[1].capacity))
    if insert_blowouts
        isnothing(waste_target) && throw(ArgumentError("batch_design_four_channel: insert_blowouts=true requires a waste_target (labware id, position)"))
        dead_volume_buffer > 0 || throw(ArgumentError("batch_design_four_channel: insert_blowouts=true requires dead_volume_buffer > 0"))
    end
    aspirate_buffer >= 0 || throw(ArgumentError("batch_design_four_channel: aspirate_buffer must be >= 0"))
    reserved = aspirate_buffer + (insert_blowouts ? dead_volume_buffer : 0.0) + 0.5 * 10.0^(-volume_precision)
    reserved < capacity || throw(ArgumentError("batch_design_four_channel: aspirate_buffer + dead_volume_buffer + rounding margin ($reserved) must be less than channel capacity ($capacity)"))
    return capacity, capacity - reserved
end

# One reagent's split_oversized demand, per destination (labware id, kind) in first-appearance order.
function reagent_demand(df::DataFrame, rows::AbstractVector{Int}, effective_capacity::Real)
    items = split_oversized([DispenseItem(r,well_to_cartesian(df[r,"Destination Position ID"]),df[r,"Volume (uL)"]) for r in rows],effective_capacity)
    out = Pair{Tuple{String,Symbol},Vector{DispenseItem}}[]
    for it in items
        dest = (df[it.col,"Destination Labware ID"],df[it.col,"Destination Kind"])
        idx = findfirst(p -> p.first == dest,out)
        isnothing(idx) ? push!(out,dest=>[it]) : push!(out[idx].second,it)
    end
    return out
end

# The window pipeline for one group of <= n_channels reagents, channel c running group_keys[c].
function batch_group_four_channel(df::DataFrame, row_groups::Dict, group_keys::AbstractVector, n_channels::Integer,
    config::Configuration{NimbusFourChannel}, capacity::Real, effective_capacity::Real; kwargs...)
    demand_by_dest = Dict{Tuple{String,Symbol},Dict{Int,Vector{DispenseItem}}}()
    dest_order = Tuple{String,Symbol}[]
    for (c,key) in enumerate(group_keys), (dest,items) in reagent_demand(df,row_groups[key],effective_capacity)
        haskey(demand_by_dest,dest) || (demand_by_dest[dest] = Dict{Int,Vector{DispenseItem}}(); push!(dest_order,dest))
        demand_by_dest[dest][c] = items
    end
    ordered_windows = DispenseWindow[]
    for dest in dest_order
        windows = compute_dispense_windows(demand_by_dest[dest],n_channels,dest[1],dest[2],four_channel_row_spacing(dest[2]))
        append!(ordered_windows,order_windows(windows))
    end
    keys_by_channel = Dict{Int,Tuple{String,Union{String,Integer}}}(c=>k for (c,k) in enumerate(group_keys))
    return assemble_windows(ordered_windows,n_channels,keys_by_channel,capacity,effective_capacity;
        max_tip_use=settings(config)["max_tip_use"],kwargs...)
end

"""
    source_position_order(key::Tuple) -> Tuple

Sort key for a source `(labware id, well)`: labware id, then column, then row. Channels are handed
out in this order, so in a 2-row tube rack A1, B1, A2, B2 map to channels 1-4 down the head, and the
two tubes sharing a column always put the lower channel on row A.
"""
function source_position_order(key::Tuple)
    rc = well_to_cartesian(string(key[2]))
    return (string(key[1]), rc[2], rc[1])
end

slot_position_order(s::Tuple{DeckPosition,Int}) = source_position_order((s[1].name, nimbus_4ch_well(s[1],s[2])))

function four_channel_permutations(v::AbstractVector)
    length(v) <= 1 && return [collect(v)]
    return [vcat(v[i],p) for i in eachindex(v) for p in four_channel_permutations(v[setdiff(eachindex(v),i)])]
end

"""
    group_window_count(demands, order, n_channels) -> Int

Dispense windows needed by one group when reagent `order[c]` runs on channel `c`, summed over
destination labware. `demands[i]` is reagent `i`'s [`reagent_demand`](@ref).
"""
function group_window_count(demands::AbstractVector, order::AbstractVector{Int}, n_channels::Integer)
    by_dest = Dict{Tuple{String,Symbol},Dict{Int,Vector{DispenseItem}}}()
    for (c,i) in enumerate(order), (dest,items) in demands[i]
        get!(by_dest,dest,Dict{Int,Vector{DispenseItem}}())[c] = items
    end
    return sum((length(compute_dispense_windows(d,n_channels,dest[1],dest[2],four_channel_row_spacing(dest[2]))) for (dest,d) in by_dest); init=0)
end

"""
    group_reagents(demands, volumes, n_channels, effective_capacity; reload_weight=8.0, max_passes=50) -> Vector{Vector{Int}}

Split reagents `1:length(demands)` into `ceil(n/n_channels)` groups that run one after another,
minimizing the sum over groups of

    (fewest dispense windows over the group's channel orders) + reload_weight × (reload waves)

A group's reload waves are `ceil(largest reagent volume / effective_capacity)`, since reloads within a
group are synchronized. `reload_weight` is how many dispense motions one reload trip is worth (8
matches instrument timings). Tips used, swap trips and total volume don't depend on the partition, so
they're left out.

Seeded greedily: each group starts from the highest-volume unassigned reagent and repeatedly adds
whichever remaining reagent raises the group's score least, until full. Then pairs of reagents are
swapped between groups until a full pass finds no improvement or `max_passes` is reached. A
swap-only search from an arbitrary seed can stall on plateaus where every single swap scores the same
(two aligned sets that start mixed need two swaps to separate), which the greedy seed avoids. Group
sizes stay as seeded (full groups first, any short group last), which keeps the groups readable from
tube position.
"""
function group_reagents(demands::AbstractVector, volumes::AbstractVector{<:Real}, n_channels::Integer, effective_capacity::Real;
    reload_weight::Real=8.0, max_passes::Int=50)
    cache = Dict{Vector{Int},Float64}()
    score(g) = get!(cache,sort(g)) do
        key = sort(g)
        minimum(group_window_count(demands,p,n_channels) for p in four_channel_permutations(key)) +
            reload_weight * maximum(ceil(volumes[i]/effective_capacity) for i in key)
    end

    unassigned = sortperm(volumes,rev=true)
    groups = Vector{Int}[]
    while !isempty(unassigned)
        group = [popfirst!(unassigned)]
        while length(group) < n_channels && !isempty(unassigned)
            k = argmin(i -> score(vcat(group,unassigned[i])), eachindex(unassigned))
            push!(group,unassigned[k])
            deleteat!(unassigned,k)
        end
        push!(groups,group)
    end
    for _ in 1:max_passes
        improved = false
        for a in 1:length(groups)-1, b in a+1:length(groups), i in eachindex(groups[a]), j in eachindex(groups[b])
            ga,gb = copy(groups[a]),copy(groups[b])
            ga[i],gb[j] = gb[j],ga[i]
            if score(ga) + score(gb) < score(groups[a]) + score(groups[b]) - 1e-9
                groups[a],groups[b] = ga,gb
                improved = true
            end
        end
        improved || break
    end
    return groups
end

"""
    place_labware(slotting, design, sources, targets, config::Configuration{NimbusFourChannel}; reload_weight=8.0) -> SlottingDict

Placement for the 4-channel Nimbus. Grouping and channels follow tube position
([`source_position_order`](@ref), chunked by `n_channels`), so choosing where the reagent tubes sit
also chooses each reagent's group and channel:

1. **Grouping.** With more than `n_channels` reagents, [`group_reagents`](@ref) splits them into
   groups that run one after another, scored by dispense windows plus `reload_weight` × reload waves.
2. **Channel order.** Within each group, every assignment of its reagents to channels (24 at most) is
   compiled with [`batch_design_four_channel`](@ref) and scored by action-row count, which captures
   dispense-window parallelism plus the reload interruptions and window tour that shift with it. The
   lowest wins; ties keep the incoming order.
3. **Tube placement.** The reagents' tubes are re-placed into free 50 mL rack slots, filling whole
   rack columns (both rows free) first, in as few racks as possible, then single slots, and handed out
   in position order: group 1's channels first, then group 2's, and so on. Channels aspirate together
   from one rack column when the lower channel sits on row A, so a crossed column never occurs.

Aspirate cost here depends only on which slots are free, not on grouping or channel order (any two
reagents fit any free column with the lower channel on row A), so optimizing those first and then
placing loses nothing. Returns `slotting` unchanged unless every source is a 50 mL conical, or if not
enough free rack slots exist.
"""
function place_labware(slotting::SlottingDict,design::DataFrame,sources::Vector{<:Labware},targets::Vector{<:Labware},config::Configuration{NimbusFourChannel};
    reload_weight::Real=8.0)
    all(s -> kind(s).name == :Conical50, sources) || return slotting
    df = convert_design_four_channel(design,sources,targets,slotting,config)
    key_of(lw) = (slotting[lw][1].name, nimbus_4ch_well(slotting[lw][1],slotting[lw][2]))
    rows_of = Dict{Tuple{String,String},Vector{Int}}()
    for r in 1:nrow(df)
        push!(get!(rows_of,(df[r,"Source Labware ID"],string(df[r,"Source Position ID"])),Int[]),r)
    end
    reagents = [s for s in sources if haskey(rows_of,key_of(s))]
    isempty(reagents) && return slotting

    n_channels = settings(config)["n_channels"]
    _, effective_capacity = four_channel_capacities(config)
    demands = [reagent_demand(df,rows_of[key_of(r)],effective_capacity) for r in reagents]
    volumes = [sum(df[rows_of[key_of(r)],"Volume (uL)"]) for r in reagents]
    groups = group_reagents(demands,volumes,n_channels,effective_capacity;reload_weight)

    best_order = Labware[]
    for g in groups
        members = reagents[g]
        sub = df[sort(vcat([rows_of[key_of(r)] for r in members]...)),:]
        best = members
        best_score = typemax(Int)
        for order in four_channel_permutations(members)
            score = nrow(batch_design_four_channel(sub,config;channel_order=[key_of(r) for r in order]))
            if score < best_score
                best_score = score
                best = order
            end
        end
        append!(best_order,best)
    end

    occupied = Set(slotting[lw] for lw in keys(slotting) if !(lw in reagents))
    racks = [p for p in deck(config) if can_place(first(reagents),p,config)]
    free_by_column = Dict{Tuple{DeckPosition,Int},Vector{Int}}()
    for p in racks, (slot,ci) in enumerate(CartesianIndices(slots(p)))
        (p,slot) in occupied && continue
        push!(get!(free_by_column,(p,ci[2]),Int[]),slot)
    end
    full_columns(p) = sort([col for ((q,col),free) in free_by_column if q == p && length(free) == 2])

    need = length(reagents)
    chosen = Tuple{DeckPosition,Int}[]
    for p in sort(racks,by=p -> -length(full_columns(p))), col in full_columns(p)
        need >= 2 || break
        append!(chosen,[(p,s) for s in free_by_column[(p,col)]])
        need -= 2
    end
    used_racks = Set(first.(chosen))
    singles = sort([(p,s) for ((p,col),free) in free_by_column for s in free if !((p,s) in chosen)],
        by=x -> (!(x[1] in used_racks), findfirst(==(x[1]),racks), slot_position_order(x)))
    append!(chosen,singles[1:min(need,length(singles))])
    length(chosen) == length(reagents) || return slotting

    sort!(chosen,by=slot_position_order)
    placed = copy(slotting)
    for (c,lw) in enumerate(best_order)
        placed[lw] = chosen[c]
    end
    return placed
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
function write_instrument_files(directory::AbstractString,design::DataFrame,source::Vector{<:Labware},target::Vector{<:Labware},config::Configuration{NimbusFourChannel},slotting::SlottingDict=place_labware(slotting_greedy(vcat(source,target),config),design,source,target,config);
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
