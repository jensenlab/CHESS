#=
The transfer closure by frontier expansion. `get_transfer_ancestors` and `get_transfer_descendents` used to
build `ledger_subset` over the whole ledger and run a recursive query over every transfer in the window (kept as
`_get_transfer_ancestors_global` and `_get_transfer_descendents_global`). Here the closure is walked well by well:
the transfers of a few wells are read through the `Transfers(Source, LedgerID)` / `Transfers(Destination, LedgerID)`
/ `Discards(Source, LedgerID)` indexes, and the visibility rule of `visibility.jl` is applied to those rows only.
The cost depends on the size of the closure and on the lifetime degree of the wells in it, not on the size of
the ledger.

Why the result is the one of the original (the argument is written out in CHESSDatabase/docs/transfer_closure.md and every
point has a test in test/test_transfer_closure.jl):

  Y(w, in)  = visible transfers with Destination = w
  Y(w, out) = visible transfers and discards with Source = w          (a discard has Destination NULL)
  T1  a transfer row is in the original `y` iff its ledger row is visible in the window (Lemma V of visibility.jl),
      so Y is the original `y` restricted to the wells asked for.
  T2  the seeds are Y(l, in) ∪ Y(l, out) for l in `locs`, the base case of the original `x`.
  T3  the original `x` is the least set that contains the seeds and, with a row r, every y with
      y.Destination = r.Source. The loop expands each source once through Y(s, in); everything it adds is in
      that least set, and nothing in the set is missed, because the rows with y.Destination = s are exactly Y(s, in).
  T4  the collateral rows are the y with Source in the wells of x (sources and destinations) whose ledger
      entry is not already in x, which is the union of Y(a, out) over those wells, minus the ledger entries of x.
  T5  the original ends with GROUP BY LedgerID and Max(Core): one row per ledger entry, a core row winning over
      a collateral row; the same is done here, ordered by SequenceID.
  T6  descendants: the original closure runs on all rows of Transfers, with no visibility test, and only the final
      rows are joined to `ledger_subset`. The same is done here: the frontier reads raw rows through the Source
      index, and the rows found are filtered for visibility at the end.

T5 changes for an entry with several transfers or discards (simultaneous ticks, section 6 of the plan): the rows are
identified by their table and row ID, not by the ledger entry. Every row of an entry that is in the closure is
core, every other row of the entry whose Source is a well of the closure is collateral, and none is dropped or
merged with another. The rows come back ordered by slot, then ledger entry, then the order they were recorded in.
For an entry with one transfer this is the original result.

The original is used instead when `encumbrances=true` (the planned transfers are merged in SQL there), when
`reconstruction_mode[]` is `:legacy`, and for more than `LOCAL_KEY_LIMIT` seeds.
=#

# the rows of an edge query, one frame per call, with the columns of the closure
# `RowID` and `Kind` (0 a transfer, 1 a discard) identify the row itself: a ledger entry can hold several transfers
const _EDGE_COLUMNS = "x.LedgerID AS LedgerID, x.Source AS Source, %DEST% AS Destination, x.Quantity AS Quantity, x.Unit AS Unit, x.ID AS RowID, %KIND% AS Kind"

_marks(n) = "(" * join(fill("?",n),",") * ")"

# The visible rows of Transfers (and for `:out` also of Discards) whose Destination (`:in`) or Source (`:out`) is
# in `wells`, with the SequenceID of their ledger row. The key column is read first, the ledger row by primary key.
function _closure_edges(wells::AbstractVector{<:Integer},side::Symbol,starting::Integer,ending::Integer,t::Real)
    pred = _visible_predicate("vl","?","?","?")
    pieces = DataFrame[]
    for chunk in Iterators.partition(wells,_id_chunk)
        sources = side === :in ? (("Transfers","Destination"),) : (("Transfers","Source"),("Discards","Source"))
        for (table,column) in sources
            dest = table == "Discards" ? "NULL" : "x.Destination"
            kind = table == "Discards" ? "1" : "0"
            push!(pieces,query_db("""
                SELECT $(replace(_EDGE_COLUMNS,"%DEST%"=>dest,"%KIND%"=>kind)), vl.SequenceID AS SequenceID
                FROM $table x CROSS JOIN Ledger vl ON vl.ID = x.LedgerID AND $pred
                WHERE x.$column IN $(_marks(length(chunk)))""",(starting,ending,t,t,chunk...)))
        end
    end
    return _vcat_or(pieces,_empty_edges())
end

_vcat_or(pieces::Vector{DataFrame},empty::DataFrame) = isempty(pieces) ? empty : reduce(vcat,pieces)

_empty_edges() = DataFrame(LedgerID=Int[],Source=Int[],Destination=Union{Missing,Int}[],Quantity=Float64[],Unit=String[],RowID=Int[],Kind=Int[],SequenceID=Int[])

_edge_key(r) = (r.Kind,r.RowID)

# the rows of a closure in replay order: by slot, then ledger entry, then the order they were recorded in
function _replay_order(rows::DataFrame)
    isempty(rows) && return rows
    return rows[sortperm(collect(zip(rows.SequenceID,rows.LedgerID,rows.Kind,rows.RowID))),:]
end

# the rows of `rows` not seen before, which are added to `seen`
function _unseen!(seen::Set,rows::DataFrame)
    keep = falses(nrow(rows))
    for (i,r) in enumerate(eachrow(rows))
        k = _edge_key(r)
        k in seen && continue
        push!(seen,k)
        keep[i] = true
    end
    return rows[keep,:]
end

"""
    get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

Find every transfer relevant to reconstructing `locs`' contents between `starting` and `ending`
sequence points.

The result has a `Core` column (`1`/`0`). `Core=1` rows are the genuine ancestor closure: `locs`
themselves plus every location transitively feeding them (found by following `Source = <already-found
Source>.Destination`). `Core=0` ("collateral") rows are *other* outgoing transfers or discards of a
`Core=1` location, to a destination that never itself feeds back into the closure -- needed so replay can
correctly account for stock a core location sent away to something `reconstruct_contents` doesn't otherwise
care about. Collateral destinations never need their own correct reconstruction -- `reconstruct_contents`
bootstraps them as bare `Empty()` stubs instead of recursing.

The columns are `LedgerID`, `Source`, `Destination` (`missing` for a discard), `Quantity`, `Unit`, `Core` and
`SequenceID`, one row per ledger entry, ordered by `SequenceID`.

The closure is walked well by well through the indexes on `Transfers` and `Discards`, so the time depends on
the transfers of the wells in the closure and not on the length of the ledger. A well that fed many others
(a shared reservoir) contributes all of its transfers as collateral. The original whole-ledger query is used for
`encumbrances=true`, for more than `LOCAL_KEY_LIMIT` locations, and when `reconstruction_mode[]` is `:legacy`.
"""
function get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(locs)) && return _get_transfer_ancestors_global(locs,starting,ending,time;encumbrances=encumbrances)
    t = db_time(time)
    seeds = unique(locs)
    seen = Set{Any}()
    core = DataFrame[]
    first_rows = _unseen!(seen,vcat(_closure_edges(seeds,:in,starting,ending,t),_closure_edges(seeds,:out,starting,ending,t)))
    push!(core,first_rows)
    expanded = Set{Int}()
    frontier = Set{Int}(first_rows.Source)
    while !isempty(frontier)
        todo = collect(setdiff(frontier,expanded))
        union!(expanded,todo)
        isempty(todo) && break
        added = _unseen!(seen,_closure_edges(todo,:in,starting,ending,t))
        push!(core,added)
        frontier = Set{Int}(added.Source)
    end
    x = reduce(vcat,core)
    wells = unique!(Int[x.Source; collect(skipmissing(x.Destination))])
    in_core = Set{Tuple{Int,Int}}(zip(x.Kind,x.RowID))
    collateral = _closure_edges(wells,:out,starting,ending,t)
    collateral = collateral[[!((k,r) in in_core) for (k,r) in zip(collateral.Kind,collateral.RowID)],:]
    x[!,:Core] .= 1
    collateral[!,:Core] .= 0
    all_rows = vcat(x,collateral)
    # every transfer of an entry is kept (a row found as core is not repeated as collateral), oldest first
    all_rows = _replay_order(all_rows)
    return select(all_rows,:LedgerID,:Source,:Destination,:Quantity,:Unit,:Core,:SequenceID)
end

"""
    get_transfer_descendents(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

Find every transfer stemming from `locs` between `starting` and `ending` sequence points: the transfers into or
out of `locs`, and out of every well they reach.

The wells are followed through all recorded transfers whether or not the transfer is visible at `time`, and only
the transfers found are then tested for visibility; so a hidden (superseded or later) transfer can lead to wells
whose own visible transfers are returned. This is how the original query behaved and it is kept.

The columns are `LedgerID`, `EncumbranceID` (`0`), `Source`, `Destination`, `Quantity`, `Unit`, `ID`, `SequenceID` and
`Time`, ordered by `SequenceID`. Discards are not followed.
"""
function get_transfer_descendents(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    _use_global(encumbrances,length(locs)) && return _get_transfer_descendents_global(locs,starting,ending,time;encumbrances=encumbrances)
    t = db_time(time)
    raw(column,wells) = _vcat_or(DataFrame[query_db("""
            SELECT LedgerID, Source, Destination, Quantity, Unit, ID AS RowID, 0 AS Kind FROM Transfers WHERE $column IN $(_marks(length(chunk)))""",Tuple(chunk))
        for chunk in Iterators.partition(wells,_id_chunk)],DataFrame(LedgerID=Int[],Source=Int[],Destination=Int[],Quantity=Float64[],Unit=String[],RowID=Int[],Kind=Int[]))
    seeds = unique(locs)
    seen = Set{Any}()
    found = DataFrame[]
    added = _unseen!(seen,vcat(raw("Destination",seeds),raw("Source",seeds)))
    push!(found,added)
    expanded = Set{Int}()
    frontier = Set{Int}(skipmissing(added.Destination))
    while !isempty(frontier)
        todo = collect(setdiff(frontier,expanded))
        union!(expanded,todo)
        isempty(todo) && break
        added = _unseen!(seen,raw("Source",todo))
        push!(found,added)
        frontier = Set{Int}(skipmissing(added.Destination))
    end
    x = reduce(vcat,found)
    # only now the visibility rule
    pred = _visible_predicate("vl","?","?","?")
    visible = _vcat_or(DataFrame[query_db("""
            SELECT vl.ID AS ID, vl.SequenceID AS SequenceID, vl.Time AS Time FROM Ledger vl
            WHERE vl.ID IN $(_marks(length(chunk))) AND $pred""",(chunk...,starting,ending,t,t))
        for chunk in Iterators.partition(unique(x.LedgerID),_id_chunk)],DataFrame(ID=Int[],SequenceID=Int[],Time=Float64[]))
    x[!,:EncumbranceID] .= 0
    out = innerjoin(x,visible;on=:LedgerID=>:ID)
    out[!,:ID] = out.LedgerID
    out = _replay_order(out)
    return select(out,:LedgerID,:EncumbranceID,:Source,:Destination,:Quantity,:Unit,:ID,:SequenceID,:Time)
end
