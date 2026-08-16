
function get_location_info(id::Integer)
    loc_info=query_db("SELECT * FROM Locations WHERE ID =?",(id,))
    if nrow(loc_info) == 0
        error("location id not found")
    end
    out=loc_info[1,:]
    name=string(out["Name"])
    k=location_kinds[Symbol(out["Type"])]
    constructor(location_id,nm)=concretetype(k)(location_id,nm,k)
    return name, constructor
end


"""
    location_reconstruction_index

Default (empty) value for `reconstruct_contents`'s `loc_index` accumulator: a map from `LocationID`
to every `(SequenceID, Location)` snapshot recorded for it during a single reconstruction pass.

This used to be a single `DataFrame` scanned in full (`filter` + `sort`) on every lookup via
`find_most_recent_location` -- correct, but with a reconstruction touching N locations across the
replay, that meant up to 2N linear scans of a structure that itself grows to ~2N rows, i.e. O(N²)
total work. A well fed by a heavily-reused hub location (thousands of transfers touch that hub over
a lab's lifetime) turned this into the dominant cost of reconstruction -- see the reconstruction
scaling benchmark's REPORT.md for the measurement (99.8% of wall time in this bookkeeping, only 0.2%
in the SQL query that finds the transfers in the first place). Keying by `LocationID` up front makes
each lookup scan only that *one* location's own (typically small) history instead of everything ever
touched in the whole reconstruction.

**Invariant: each location's entry vector is always appended in non-decreasing `SequenceID` order.**
Every `push_location!` call site in `reconstruct_contents.jl` is either a pre-replay-loop bootstrap
entry (`seq <= foot`) or a replay-loop entry (`seq == row.SequenceID`, with `transfers` fetched at
`SequenceID >= foot+1` and iterated in ascending `SequenceID` order). `find_most_recent_location`
relies on this invariant to binary-search each location's vector instead of scanning it -- see its
docstring. Any future `push_location!` call site must preserve non-decreasing order per location, or
that binary search silently returns wrong results instead of erroring.
"""
const location_reconstruction_index=Dict{Integer,Vector{Tuple{Integer,Location}}}()

"""
    push_location!(index, location_id, sequence_id, loc)

Record a `(sequence_id, loc)` snapshot for `location_id` in a `loc_index` accumulator (see
[`location_reconstruction_index`](@ref)). The `push!(all_locs, (id, seq, loc))` counterpart from the
old `DataFrame`-based accumulator.
"""
function push_location!(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer,loc::Location)
    entries = get!(() -> Tuple{Integer,Location}[], index, location_id)
    push!(entries, (sequence_id, loc))
    return nothing
end

"""
    find_most_recent_location(index, location_id)

Return the most recently pushed `Location` for `location_id` in a `loc_index` accumulator (see
[`location_reconstruction_index`](@ref)), or `nothing` if it has no entries. Relies on that type's
documented sortedness invariant: since entries are always appended in non-decreasing `SequenceID`
order, the most recent one is simply the last one -- O(1), no scan needed.
"""
function find_most_recent_location(index::Dict{<:Integer,<:Vector},location_id::Integer)
    haskey(index,location_id) || return nothing
    entries = index[location_id]
    isempty(entries) && return nothing
    return entries[end][2]
end

"""
    find_most_recent_location(index, location_id, sequence_id)

Return the most recently pushed `Location` for `location_id` with `SequenceID <= sequence_id`, or
`nothing` if none qualifies. Relies on the same sortedness invariant as the 2-arg method: since
entries are always appended in non-decreasing `SequenceID` order, a binary search
(`searchsortedlast`) finds the rightmost qualifying entry in O(log k) instead of a linear scan. Ties
(more than one entry at the same `sequence_id`) resolve to the last one pushed, matching the
insertion-order tie-breaking a linear max-scan would produce.
"""
function find_most_recent_location(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer)
    haskey(index,location_id) || return nothing
    entries = index[location_id]
    idx = searchsortedlast(entries, (sequence_id, nothing); by=first)
    idx == 0 && return nothing
    return entries[idx][2]
end