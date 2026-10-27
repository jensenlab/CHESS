# Forward tracing: where material went after it was in a well or lot. This is the reverse of
# `trace_contents`, which finds the lots that the material in a well came from. A forward trace follows
# the recorded transfers out of a well, and out of every well they reach, in the order they happened. It is
# computed from the ledger each time and nothing is stored, so an amendment (`update` with `replace` or
# `insert`) changes the next answer, and a trace as of an earlier sequence ID still gives the old one.

# the transfers out of `sources` as of `sequence_id` and `time`, one row per transfer, oldest first
function _transfers_out_of(sources::AbstractVector{<:Integer},sequence_id::Integer,time::DateTime)
    reconstruction_mode[] === :legacy && return _transfers_out_of_global(sources,sequence_id,time)
    out=DataFrame(LedgerID=Int[],SequenceID=Int[],Source=Int[],Destination=Int[])
    pred=_visible_predicate("vl","?","?","?")
    t=db_time(time)
    for chunk in Iterators.partition(sources,_id_chunk)
        rows=query_db("""
            SELECT x.LedgerID AS LedgerID, vl.SequenceID AS SequenceID, x.Source AS Source, x.Destination AS Destination
            FROM Transfers x CROSS JOIN Ledger vl ON vl.ID = x.LedgerID AND $pred
            WHERE x.Source IN $(_marks(length(chunk)))
            """,(typemin(Int64),sequence_id,t,t,chunk...))
        append!(out,rows)
    end
    return out[sortperm(out.SequenceID;alg=MergeSort),:]
end

# the same through a `ledger_subset` over the whole ledger
function _transfers_out_of_global(sources::AbstractVector{<:Integer},sequence_id::Integer,time::DateTime)
    out=DataFrame(LedgerID=Int[],SequenceID=Int[],Source=Int[],Destination=Int[])
    for chunk in Iterators.partition(sources,_id_chunk)
        marks="("*join(fill("?",length(chunk)),",")*")"
        rows=query_db("""
            WITH ledger_subset (ID,SequenceID) AS (
                SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
            SELECT t.LedgerID, l.SequenceID, t.Source, t.Destination
            FROM Transfers t INNER JOIN ledger_subset l ON t.LedgerID = l.ID
            WHERE t.Source IN $marks
            """,(db_time(time),sequence_id,chunk...))
        append!(out,rows)
    end
    return out
end

# Spread from `seeds`, a dictionary from well ID to the sequence ID from which the well's material may
# be passed on. A transfer out of a well at sequence `s` carries the material on only if `s` is no
# earlier than the sequence from which the well has it (strictly later for a well that received it by
# transfer). Each well is kept at the earliest sequence it can be reached, which is repeated until nothing
# changes.
function _spread_forward(seeds::AbstractDict{<:Integer,<:Integer},sequence_id::Integer,time::DateTime)
    reached=Dict{Int,NamedTuple{(:sequence,:ledger,:depth,:via),Tuple{Int,Union{Int,Missing},Int,Union{Int,Missing}}}}()
    frontier=Int[]
    for (w,s) in seeds
        reached[w]=(sequence=s,ledger=missing,depth=0,via=missing)
        push!(frontier,w)
    end
    while !isempty(frontier)
        transfers=_transfers_out_of(frontier,sequence_id,time)
        changed=Set{Int}()
        for r in eachrow(transfers)
            from=reached[r.Source]
            # material arrived by transfer at `from.sequence`, so only later transfers carry it on
            usable = ismissing(from.ledger) ? r.SequenceID >= from.sequence : r.SequenceID > from.sequence
            usable || continue
            cur=get(reached,r.Destination,nothing)
            (isnothing(cur) || r.SequenceID < cur.sequence) || continue
            reached[r.Destination]=(sequence=r.SequenceID,ledger=r.LedgerID,depth=from.depth+1,via=r.Source)
            push!(changed,r.Destination)
        end
        frontier=collect(changed)
    end
    return reached
end

function _forward_result(reached)
    ids=sort!(collect(keys(reached));by=w->(reached[w].sequence,w))
    containers=well_containers(ids)
    return DataFrame(
        WellID=ids,
        ContainerID=Union{Int,Missing}[get(containers,w,missing) for w in ids],
        FirstSequenceID=[reached[w].sequence for w in ids],
        FirstLedgerID=Union{Int,Missing}[reached[w].ledger for w in ids],
        Depth=[reached[w].depth for w in ids],
        ViaWell=Union{Int,Missing}[reached[w].via for w in ids])
end

"""
    trace_forward(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(); from_sequence=0) -> DataFrame
    trace_forward(lot::Lot, sequence_id=get_last_sequence_id(), time=Dates.now()) -> DataFrame

Find every well that received material from a well, or from the labware received as a lot, as of
`sequence_id` and `time`. This is the reverse of [`trace_contents`](@ref), which finds the lots a well's
material came from. It is the list to check when a lot turns out to be bad, or when a transfer is
corrected with [`update`](@ref).

The result has one row for each well reached, including the starting wells, ordered by when they were
first reached, with columns:

- `WellID`: the well.
- `ContainerID`: the labware the well belongs to (see [`well_container`](@ref)), or `missing` if it is not recorded.
- `FirstSequenceID`: the sequence ID of the first transfer that brought material into the well, or of the start for a starting well.
- `FirstLedgerID`: the ledger entry of that transfer, or `missing` for a starting well.
- `Depth`: the number of transfers between the starting well and this one along that first path.
- `ViaWell`: the well that transfer came from, or `missing` for a starting well. Following `ViaWell` rebuilds the path.

The trace follows the transfers in the order they happened. A transfer out of a well carries the
material on only if it comes after the material arrived, so a transfer out of a well before it received
anything is not followed. `from_sequence` starts a well trace at a later point in the history. A lot
starts from every well of the labware that has the lot as of `sequence_id`, from the beginning of the
history.

The trace follows transfers only. It is slightly larger than the exact set: a transfer carries the
material on even if an observation has since overwritten that component in the well, and a
discard is not a way out. Planned operations (encumbrances) are not followed. The trace is
computed from the ledger each time and is not stored.

See also: [`forward_containers`](@ref), [`forward_runs`](@ref).
"""
function trace_forward(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();from_sequence::Integer=0)
    name,build=get_location_info(location_id)
    build(location_id,name) isa CHESSCore.Well || error("only a well can be traced forward, and location $location_id is not one")
    return _forward_result(_spread_forward(Dict(Int(location_id)=>Int(from_sequence)),sequence_id,time))
end

# the labware that had `lot` observed on it at some point up to `sequence_id` and `time`
function _lot_candidates(lot::Lot,sequence_id::Integer,time::DateTime)
    if reconstruction_mode[] === :legacy
        return query_db("""
            WITH ledger_subset (ID,SequenceID) AS (
                SELECT Max(ID), SequenceID FROM Ledger WHERE Time <= ? AND SequenceID <= ? GROUP BY SequenceID)
            SELECT DISTINCT o.LocationID
            FROM ObservedLots o INNER JOIN ledger_subset l ON o.LedgerID = l.ID INNER JOIN Products p ON o.ProductID = p.ID
            WHERE p.Supplier = ? AND p.CatalogNumber = ? AND o.Lot = ?
            """,(db_time(time),sequence_id,lot.supplier,lot.catalog_number,lot.lot))
    end
    # the product and lot first (ObservedLots(ProductID, Lot)), then the visibility rule on those rows
    return query_db("""
        SELECT DISTINCT o.LocationID
        FROM Products p CROSS JOIN ObservedLots o ON o.ProductID = p.ID
        CROSS JOIN Ledger vl ON vl.ID = o.LedgerID AND $(_visible_predicate("vl","?","?","?"))
        WHERE p.Supplier = ? AND p.CatalogNumber = ? AND o.Lot = ?
        """,(typemin(Int64),sequence_id,db_time(time),db_time(time),lot.supplier,lot.catalog_number,lot.lot))
end

function trace_forward(lot::Lot,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    candidates=_lot_candidates(lot,sequence_id,time)
    seeds=Dict{Int,Int}()
    for labware_id in candidates.LocationID
        current=reconstruct_lot(labware_id,sequence_id,time) # a later observation may have changed the labware's lot
        isnothing(current) && continue
        (current.supplier,current.catalog_number,current.lot)==(lot.supplier,lot.catalog_number,lot.lot) || continue
        for w in container_wells(labware_id).WellID
            seeds[w]=0
        end
    end
    return _forward_result(_spread_forward(seeds,sequence_id,time))
end

"""
    forward_containers(trace::DataFrame) -> DataFrame
    forward_containers(source, args...; kwargs...) -> DataFrame

The labware that holds the wells of a forward trace, with columns `ContainerID`, `WellCount` (the
number of reached wells in it) and `FirstSequenceID` (the earliest sequence at which any of them was
reached). Wells with no recorded labware are left out. The second form runs [`trace_forward`](@ref)
on `source` first.
"""
function forward_containers(trace::DataFrame)
    out=DataFrame(ContainerID=Int[],WellCount=Int[],FirstSequenceID=Int[])
    seen=Dict{Int,Int}()
    for r in eachrow(trace)
        ismissing(r.ContainerID) && continue
        i=get(seen,r.ContainerID,0)
        if i==0
            push!(out,(r.ContainerID,1,r.FirstSequenceID))
            seen[r.ContainerID]=nrow(out)
        else
            out.WellCount[i]+=1
            out.FirstSequenceID[i]=min(out.FirstSequenceID[i],r.FirstSequenceID)
        end
    end
    return out
end
forward_containers(source,args...;kwargs...) = forward_containers(trace_forward(source,args...;kwargs...))

"""
    forward_runs(trace::DataFrame) -> DataFrame
    forward_runs(source, args...; kwargs...) -> DataFrame

The runs recorded on the wells or labware of a forward trace, with columns `RunID`, `ExperimentID` and
`LocationID` (the well or labware the run is recorded on). The second form runs [`trace_forward`](@ref)
on `source` first.
"""
function forward_runs(trace::DataFrame)
    ids=unique(vcat(trace.WellID,collect(skipmissing(trace.ContainerID))))
    out=DataFrame(RunID=Int[],ExperimentID=Int[],LocationID=Int[])
    for chunk in Iterators.partition(ids,_id_chunk)
        marks="("*join(fill("?",length(chunk)),",")*")"
        rows=query_db("SELECT ID AS RunID, ExperimentID, LocationID FROM Runs WHERE LocationID IN $marks",Tuple(chunk))
        append!(out,rows)
    end
    return sort!(out,:RunID)
end
forward_runs(source,args...;kwargs...) = forward_runs(trace_forward(source,args...;kwargs...))
