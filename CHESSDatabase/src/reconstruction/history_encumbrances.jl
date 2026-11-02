#=
Histories with planned (encumbered) operations, `reconstruct_history(...; encumbrances=true)`.

What `reconstruct_*(...; encumbrances=true)` does (see docs/history.md):

  - A protocol is enforced at a sequence point when the newest `ProtocolEnforcement` row visible in the window the
    query reads says so. The cache getters read the window `[0, sequence_id]`; the event getters read
    `[foot, sequence_id]`, `foot` being the slot of the newest cache of the key.
  - The planned rows of the enforced protocols are given the slot `get_last_sequence_id() + EncumbranceID`, after
    every real slot, so they hide every real row of the same key and the highest `EncumbranceID` wins among them.
    The slot orders the rows. It is not the slot at which the value changes: the planned value is in force at every
    sequence point at which its protocol is enforced.

So the value of a key with planned rows changes at the slot of an enforcement row, at a real row, and at a cache
(the window of the event getters moves with it). A key with no planned row has the history it has without
`encumbrances`. For a key with planned rows the history is built at those slots. The value at a slot is taken
from the reconstruction itself, so it is the reconstruction's value, whatever the window rules make of it. Planned
rows are few, and the probing is paid only by the keys they touch.
=#

# The protocols that have a planned row on the facet of `loc`. Empty when nothing is planned for it, and for
# facets that have no planned operations (reads, lots, instrument settings).
function _planned_protocols(facet::Symbol,name::String,loc::Integer)
    sql,params = if facet === :parent
        "SELECT EncumbranceID FROM EncumberedMovements WHERE Child = ? UNION SELECT EncumbranceID FROM EncumberedCachedAncestors WHERE LocationID = ?",(loc,loc)
    elseif facet === :locked
        "SELECT EncumbranceID FROM EncumberedLocks WHERE LocationID = ? UNION SELECT EncumbranceID FROM EncumberedCachedLockActivity WHERE LocationID = ?",(loc,loc)
    elseif facet === :active
        "SELECT EncumbranceID FROM EncumberedActivity WHERE LocationID = ? UNION SELECT EncumbranceID FROM EncumberedCachedLockActivity WHERE LocationID = ?",(loc,loc)
    elseif facet === :attribute
        "SELECT EncumbranceID FROM EncumberedEnvironments WHERE LocationID = ? AND Attribute = ? UNION SELECT EncumbranceID FROM EncumberedCachedEnvironments WHERE LocationID = ?",(loc,name,loc)
    else
        return Int[]
    end
    return _protocols_of(query_db(sql,params).EncumbranceID)
end

function _protocols_of(encumbrance_ids)
    isempty(encumbrance_ids) && return Int[]
    ids = Int.(unique(encumbrance_ids))
    return Int.(query_db("SELECT DISTINCT ProtocolID FROM Encumbrances WHERE ID IN $(_marks(length(ids)))",Tuple(ids)).ProtocolID)
end

# the slot and ledger entry of every enforcement row of `protocols` (every revision, enforced or not)
function _enforcement_rows(protocols::Vector{Int})
    isempty(protocols) && return DataFrame(slot=Int[],ledger_id=Int[],enforced=Int[])
    return query_db("""
        SELECT l.SequenceID AS slot, p.LedgerID AS ledger_id, p.IsEnforced AS enforced
        FROM ProtocolEnforcement p INNER JOIN Ledger l ON l.ID = p.LedgerID
        WHERE p.ProtocolID IN $(_marks(length(protocols))) ORDER BY l.SequenceID, p.ID""",Tuple(protocols))
end

# the value of `facet` of `loc` at the sequence point `at`, as the reconstruction with planned operations gives it
function _probe(facet::Symbol,name::String,loc::Integer,at::Integer,time::DateTime)
    if facet === :parent
        p = CHESSCore.parent(reconstruct_parent(loc,at,time;encumbrances=true))
        return isnothing(p) ? missing : Int(CHESSCore.location_id(p))
    elseif facet === :locked
        return CHESSCore.is_locked(reconstruct_lock(loc,at,time;encumbrances=true))
    elseif facet === :active
        return CHESSCore.is_active(reconstruct_activity(loc,at,time;encumbrances=true))
    end
    # an attribute: its quantity, or missing
    attrs = CHESSCore.attributes(reconstruct_attributes(loc,at,time;encumbrances=true))
    for (k,a) in attrs
        kname = k isa Symbol ? k : hasproperty(k,:name) ? k.name : Symbol(string(k))
        kname === Symbol(name) || continue
        return ismissing(CHESSCore.value(a)) ? missing : CHESSCore.quantity(a)
    end
    return missing
end

# the (value, unit) of a probe as a history row holds them. A quantity is written in the unit of a planned row of the
# attribute that it converts to, else in its own unit.
function _probe_row_value(facet::Symbol,name::String,loc::Integer,v)
    v isa Unitful.Quantity || return (v,missing)
    units = String[]
    for r in eachrow(query_db("SELECT DISTINCT Unit FROM EncumberedEnvironments WHERE LocationID = ? AND Attribute = ?",(loc,name)))
        ismissing(r.Unit) || push!(units,String(r.Unit))
    end
    for u in units
        try
            return (Float64(ustrip(Unitful.uconvert(_parse_unit(u),v))),u)
        catch err
            err isa Union{ArgumentError,Unitful.DimensionError,MethodError} || rethrow()
        end
    end
    return (Float64(ustrip(v)),string(Unitful.unit(v)))
end

# true when the value of a real row is what the probe found
function _row_matches(facet::Symbol,r::Union{Nothing,_HRow},v)
    if isnothing(r) || _isvirtual(r)
        facet === :locked && return v === false
        facet === :active && return v === true
        return ismissing(v)
    end
    ismissing(r.value) && return ismissing(v)
    ismissing(v) && return false
    if v isa Unitful.Quantity
        ismissing(r.unit) && return false
        try
            return isapprox(ustrip(Unitful.uconvert(_parse_unit(r.unit),v)),r.value;rtol=1e-9,atol=1e-12)
        catch err
            err isa Union{ArgumentError,Unitful.DimensionError,MethodError} || rethrow()
            return false
        end
    end
    return isequal(r.value,v)
end

# A real row that is back in force after a planned one starts at the slot where the planned row ended, not at its own slot,
# which lies before the planned row's. A blank (the value is unset again once the planned row stops applying) has no row of its
# own; it is written as a row of the enforcement entry that switched the planned row off, so that it is part of the frame.
function _resume(r::_HRow,out::Vector{_HRow},p::Int,enf::DataFrame)
    isempty(out) && return r
    if _isvirtual(r)
        k = findlast(<=(p),enf.slot)
        (k === nothing || (ismissing(out[end].value) && out[end].event == "planned ended")) && return r
        return _HRow(p,enf.ledger_id[k],0,missing,missing,"planned ended",:event,r.origin)
    end
    r.slot > out[end].slot && return r
    return _HRow(p,r.ledger,r.rid,r.value,r.unit,r.event,r.kind,r.origin)
end

const _PLANNED_EVENT = Dict(:parent=>"planned move",:locked=>"planned lock",:active=>"planned activity",:attribute=>"planned set_attribute")

# The timeline of a key with planned rows (`protocols` are the protocols they belong to) over `lo..hi`. It is built at the
# slots at which the value can change: the first slot, the rows of every source of the key, and the enforcement rows.
function _planned_timeline(facet::Symbol,name::String,loc::Integer,lo::Integer,hi::Integer,time::DateTime,protocols::Vector{Int};collapse::Bool=true)
    real = _own_timeline(facet,name,loc,lo,hi,time;collapse=false)
    realpos = [max(r.slot,lo) for r in real]
    enf = _enforcement_rows(protocols)
    points = Set{Int}([lo])
    for src in _history_sources(facet,name,loc)
        for r in _window_rows(src,lo + 1,hi,time,loc)
            push!(points,r.slot)
        end
    end
    for s in enf.slot
        lo < s <= hi && push!(points,s)
    end
    out = _HRow[]
    for p in sort!(collect(points))
        v = _probe(facet,name,loc,p,time)
        r = _row_in_force(real,realpos,p)
        if _row_matches(facet,r,v)
            row = _resume(r === nothing ? _hvirtual(Int(loc)) : r,out,p,enf)
        else
            value,unit = _probe_row_value(facet,name,loc,v)
            k = findlast(i -> enf.slot[i] <= p && enf.enforced[i] == 1,eachindex(enf.slot))
            ledger = k !== nothing ? enf.ledger_id[k] : (r !== nothing && !_isvirtual(r) ? r.ledger : (nrow(enf) > 0 ? enf.ledger_id[1] : 0))
            slot = p == lo ? (k === nothing ? lo : min(lo,enf.slot[k])) : p
            row = _HRow(slot,ledger,0,value,unit,_PLANNED_EVENT[facet],:event,Int(loc))
        end
        if !isempty(out) && out[end].slot == row.slot
            out[end] = row
        elseif isempty(out) || !_same_row(row,out[end])
            push!(out,row)
        end
    end
    _blank_start(out,loc)
    collapse && (out = _collapsed(out))
    return out
end

# ------------------------------------------------------------------------------------------ contents

# A well is touched by planned operations when a planned transfer ends in it or in a well that feeds it, or when a planned
# cache of contents is held for one of them.
function _planned_contents_touch(loc::Integer,hi::Integer,time::DateTime)
    nrow(query_db("SELECT 1 FROM EncumberedTransfers LIMIT 1")) + nrow(query_db("SELECT 1 FROM EncumberedCachedContents LIMIT 1")) +
        nrow(query_db("SELECT 1 FROM EncumberedObservations LIMIT 1")) == 0 && return false
    wells = Set{Int}([Int(loc)])
    for r in eachrow(get_transfer_ancestors([Int(loc)],0,hi,time))
        push!(wells,r.Source)
        ismissing(r.Destination) || push!(wells,r.Destination)
    end
    ids = collect(wells)
    for chunk in Iterators.partition(ids,_id_chunk)
        marks = _marks(length(chunk))
        nrow(query_db("SELECT 1 FROM EncumberedTransfers WHERE Destination IN $marks LIMIT 1",Tuple(chunk))) > 0 && return true
        nrow(query_db("SELECT 1 FROM EncumberedCachedContents WHERE LocationID IN $marks LIMIT 1",Tuple(chunk))) > 0 && return true
        nrow(query_db("SELECT 1 FROM EncumberedObservations WHERE LocationID IN $marks LIMIT 1",Tuple(chunk))) > 0 && return true
    end
    return false
end

# The timeline of the stock of a well that planned operations touch. Its value can change at a row of anything that feeds the
# well, at a cache of the well and at an enforcement row of a protocol with a planned transfer or cache.
function _planned_contents_timeline(loc::Integer,lo::Integer,hi::Integer,time::DateTime;collapse::Bool=true)
    real = _contents_timeline(loc,lo,hi,time;collapse=false)
    realpos = [max(r.slot,lo) for r in real]
    protocols = _protocols_of(vcat(query_db("SELECT EncumbranceID FROM EncumberedTransfers").EncumbranceID,
                                   query_db("SELECT EncumbranceID FROM EncumberedCachedContents").EncumbranceID,
                                   query_db("SELECT EncumbranceID FROM EncumberedObservations").EncumbranceID))
    enf = _enforcement_rows(protocols)
    points = Set{Int}([lo])
    anc = get_transfer_ancestors([Int(loc)],0,hi,time;encumbrances=true)
    core = Set{Int}([Int(loc)])
    for r in eachrow(anc)
        1 <= r.SequenceID && lo < r.SequenceID <= hi && push!(points,r.SequenceID)
        r.Core == 1 && union!(core,ismissing(r.Destination) ? (r.Source,) : (r.Source,r.Destination))
    end
    for r in eachrow(get_content_observations(collect(core),lo,hi,time;encumbrances=true))
        lo < r.SequenceID <= hi && push!(points,r.SequenceID)
    end
    for s in get_content_caches(loc,lo,hi,time).SequenceID
        lo < s <= hi && push!(points,s)
    end
    for r in real
        lo < r.slot <= hi && push!(points,r.slot)
    end
    for s in enf.slot
        lo < s <= hi && push!(points,s)
    end
    out = _HRow[]
    for p in sort!(collect(points))
        stock = CHESSCore.stock(reconstruct_contents(loc,p,time;encumbrances=true))
        r = _row_in_force(real,realpos,p)
        same = r !== nothing && !_isvirtual(r) ? _same_stock(r.value,stock) : _same_stock(Empty(),stock)
        if same
            row = _resume(r === nothing ? _hvirtual(Int(loc)) : r,out,p,enf)
        else
            k = findlast(i -> enf.slot[i] <= p && enf.enforced[i] == 1,eachindex(enf.slot))
            ledger = k !== nothing ? enf.ledger_id[k] : (r !== nothing && !_isvirtual(r) ? r.ledger : (nrow(enf) > 0 ? enf.ledger_id[1] : 0))
            slot = p == lo ? (k === nothing ? lo : min(lo,enf.slot[k])) : p
            row = _HRow(slot,ledger,0,stock,missing,"planned transfer",:event,Int(loc))
        end
        if !isempty(out) && out[end].slot == row.slot
            out[end] = row
        elseif isempty(out) || !_same_row(row,out[end])
            push!(out,row)
        end
    end
    isempty(out) && push!(out,_hvirtual(Int(loc)))
    collapse && (out = _collapsed(out))
    return out
end

_same_stock(a,b) = ismissing(a) ? b isa Empty : (a isa Empty && b isa Empty) || (!(a isa Empty) && !(b isa Empty) && isapprox(a,b;rtol=1e-9))

# ------------------------------------------------------------------------------------------ effective attribute

# The effective value and its origin, as `reconstruct_environment` with planned operations gives them: the nearest
# ancestor-or-self of the returned chain with a value.
function _environment_probe(name::String,loc::Integer,at::Integer,time::DateTime)
    l = reconstruct_environment(loc,at,time;encumbrances=true)
    while !isnothing(l)
        for (k,a) in CHESSCore.attributes(l)
            kname = k isa Symbol ? k : hasproperty(k,:name) ? k.name : Symbol(string(k))
            kname === Symbol(name) || continue
            ismissing(CHESSCore.value(a)) || return (CHESSCore.quantity(a),Int(CHESSCore.location_id(l)))
        end
        l = CHESSCore.parent(l)
    end
    return (missing,Int(loc))
end

# The effective timeline with planned operations. The timeline composed from the planned-aware own timelines of the chain
# members is the same as the reconstruction's unless a planned row is on a member: the reconstruction reads the planned
# rows of a whole chain through one window (from the oldest cache of any member), so the value is taken from the
# reconstruction itself at the slots where it can change.
function _effective_planned(name::String,loc::Integer,lo::Integer,hi::Integer,time::DateTime)
    members = Set{Int}()
    composed = _effective_timeline(name,loc,lo,hi,time,0;encumbrances=true,members=members)
    protocols = Int[]
    for m in members
        append!(protocols,_planned_protocols(:attribute,name,m))
        append!(protocols,_planned_protocols(:parent,"",m))
    end
    protocols = unique!(protocols)
    isempty(protocols) && return composed
    composedpos = [max(r.slot,lo) for r in composed]
    enf = _enforcement_rows(protocols)
    points = Set{Int}([lo])
    for r in composed
        lo < r.slot <= hi && push!(points,r.slot)
    end
    for s in enf.slot
        lo < s <= hi && push!(points,s)
    end
    for m in members, (facet,nm) in ((:attribute,name),(:parent,""))
        for src in _history_sources(facet,nm,m)
            for r in _window_rows(src,lo + 1,hi,time,m)
                push!(points,r.slot)
            end
        end
    end
    out = _HRow[]
    for p in sort!(collect(points))
        v,origin = _environment_probe(name,loc,p,time)
        r = _row_in_force(composed,composedpos,p)
        if r !== nothing && !_isvirtual(r) && _row_matches(:attribute,r,v) && r.origin == origin
            row = _resume(r,out,p,enf)
        elseif r !== nothing && _isvirtual(r) && ismissing(v)
            row = _resume(r,out,p,enf)
        else
            value,unit = _probe_row_value(:attribute,name,origin,v)
            k = findlast(i -> enf.slot[i] <= p && enf.enforced[i] == 1,eachindex(enf.slot))
            ledger = k !== nothing ? enf.ledger_id[k] : (r !== nothing && !_isvirtual(r) ? r.ledger : (nrow(enf) > 0 ? enf.ledger_id[1] : 0))
            slot = p == lo ? (k === nothing ? lo : min(lo,enf.slot[k])) : p
            row = _HRow(slot,ledger,0,value,unit,"planned set_attribute",:event,origin)
        end
        if !isempty(out) && out[end].slot == row.slot
            out[end] = row
        elseif isempty(out) || !_samevalue(row,out[end])
            push!(out,row)
        end
    end
    return _blank_start(out,loc)
end
