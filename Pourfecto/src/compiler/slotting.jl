
# slotting functions find a layout for labware on a robot with a particular configuration


"""
    SlottingDict = Dict{Labware,Tuple{DeckPosition,Int}}

Alias for a mapping from each piece of labware to the `(DeckPosition, slot)` it has been assigned to
on an instrument's deck. Produced by [`slotting_greedy`](@ref)/[`packing_greedy`](@ref), and consumed
by [`write_instrument_files`](@ref).
"""
SlottingDict = Dict{Labware,Tuple{DeckPosition,Int}}

"""
    slottingdict_to_df(slotting::SlottingDict) -> DataFrame

Convert a `SlottingDict` describing labware placement into a `DataFrame`.

The input dictionary is expected to map each labware object `s` to a 2-tuple of the form `(deck_position, slot)`, where:

- `deck_position` is an object whose human-readable identifier is given by
  `name(deck_position)`.
- `slot` is a `String` or `Integer` identifying the slot within that deck
  position.

# Arguments
- `slotting::SlottingDict`: Dictionary of labware placement info.

# Returns
- `DataFrame`: A table with columns `Position`, `Slot`, `LabwareID`, and `Name`.
"""
function slottingdict_to_df(slotting::SlottingDict)
    # Pourfecto builds labware via CHESSCore.build_location, which is never committed to a database
    # (see CHESSCore/src/locations/build_location.jl) -- its location_id is always `nothing`, not an
    # Integer, so this must tolerate that rather than assume a committed-location workflow. `missing`
    # (not `nothing`) is used here since that's the sentinel DataFrames/CSV.jl actually knows how to
    # write out (as an empty cell) -- CSV.write errors on a raw `nothing` value.
    labware_ids = Union{Integer,Missing}[]
    labware_names = String[]
    deck_position = String[]
    slot = Union{String,Integer}[]

    for s in keys(slotting)
        push!(labware_ids,something(location_id(s),missing))
        push!(labware_names,CHESSCore.name(s))
        push!(deck_position,slotting[s][1].name)
        push!(slot,slotting[s][2])
    end 
    
    return DataFrame(Position=deck_position,Slot=slot,LabwareID=labware_ids,Name=labware_names)
end 




"""
    slotting_greedy(labware::Vector{<:Labware}, config::Configuration; pinned::SlottingDict=SlottingDict()) -> SlottingDict

Greedily assign each piece of `labware` to an open, admissible deck slot on `config`'s deck. Labware
sharing a name (e.g. the same physical plate used as both a source and a target) is slotted once and
shares that slot. Errors if any labware can't be placed on `config`'s deck at all
(see [`can_place`](@ref)); labware that can be placed but for which no slot remains open is returned
in the `not_placed` local (not currently surfaced -- see [`packing_greedy`](@ref), which calls this
repeatedly to produce one or more slotting solutions covering everything).

`pinned` pre-seeds the result with fixed `labware => (position,slot)` assignments -- e.g. a
permanently-mounted fixture that always occupies the same physical deck slot -- before the greedy
loop runs; those slots are removed from consideration for every other piece of labware, and pinned
labware is skipped by the ordinary placement loop. Empty by default, so existing callers see no
behavior change. See `Nimbus.jl`'s `slotting_greedy(::Vector{<:Labware},::Configuration{Nimbus})`
override for a worked example (a reserved waste-conical slot).
"""
function slotting_greedy(labware::Vector{<:Labware},config::Configuration;pinned::SlottingDict=SlottingDict())

    for lw in labware
        can_place(lw,config) || error("labware type $(typeof(lw)) cannot be placed on a $(CHESSCore.name(config)) deck")
    end

    slotting = SlottingDict()
    open_slots = Set{Tuple{DeckPosition,Int}}()

    for position in deck(config)
        n_slots = prod(slots(position))
        for i in 1:n_slots
            push!(open_slots,(position,i))
        end
    end

    for (lw,s) in pinned
        slotting[lw] = s
        delete!(open_slots,s)
    end

    pinned_names = CHESSCore.name.(collect(keys(pinned)))
    labware_to_place = Labware[] # only place labware with unique names. Some sources can also be targets, so we need to avoid double counting them
    duplicate_labware = Labware[]
    for lw in labware
        CHESSCore.name(lw) in pinned_names && continue # already pinned above
        if !in(CHESSCore.name(lw), CHESSCore.name.(labware_to_place))
            push!(labware_to_place,lw)
        else
            push!(duplicate_labware,lw)
        end
    end


    not_placed=Labware[]
    for lw in labware_to_place
        placed=false
        for s in open_slots
            if can_place(lw,s[1],config)
                slotting[lw]= s
                delete!(open_slots,s)
                placed=true
                break
            end
        end

        if !placed
            push!(not_placed,lw)
        end
    end

    placed_labware = collect(keys(slotting))
    for lw in duplicate_labware
       idx =findfirst(x->CHESSCore.name(lw) == CHESSCore.name(x),placed_labware)
        slotting[lw] = slotting[placed_labware[idx]] # slot the duplicate labware back into the same spot
    end


    return slotting
end



"""
    packing_greedy(pairings::Vector{Tuple{Labware,Labware}}, config::Configuration; kwargs...) -> Vector{SlottingDict}

Produce one or more [`SlottingDict`](@ref) layouts covering every `(source,target)` pairing that must
be co-slotted, by repeatedly calling [`slotting_greedy`](@ref) on the full remaining labware set and
peeling off however many pairings that solution satisfies, until every pairing is covered. Each
returned `SlottingDict` becomes one compiled protocol (see [`compile`](@ref)).

This is the default `packing_method` for [`compile`](@ref) and the extension point instruments should
override only when they have unusual slotting constraints -- e.g. `Cobra` overrides this to always
produce one protocol per pairing (it only has two deck slots and deliberately wants a fresh protocol
whenever the labware pairing changes), rather than greedily co-packing as many pairings as possible
into each protocol the way this generic implementation does.
"""
function packing_greedy(pairings::Vector{Tuple{Labware,Labware}},config::Configuration;kwargs...)

    slotting_dicts=SlottingDict[]
    remaining= pairings
    all_labware=union(remaining...)
    while length(remaining) > 0 
        slotting=slotting_greedy(all_labware,config)
        pairings_remaining = filter(x-> any(map(y->!in(y,keys(slotting)),x)),remaining)
        if pairings_remaining == remaining 
            error("unsolvable packing arrangement, $(pairings_remaining)")
        end 
        push!(slotting_dicts,slotting)
        remaining = pairings_remaining
        if length(remaining)==0 
            break 
        end 
        all_labware = union(remaining...)
    end 
    return slotting_dicts 
end 



