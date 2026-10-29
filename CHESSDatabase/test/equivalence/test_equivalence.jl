# Equivalence of the reconstruction code with its frozen original.
#
# For every seed a ledger is generated (generate_ledger.jl) and, at random query points
# (location, sequence_id, time, max_cache, encumbrances), the current function is compared with the same
# function in the frozen `Legacy` module (legacy_reconstruction.jl): function by function (the ledger
# getters, the six cache lookups, the "last write wins" lookups, the transfer closure, observations,
# instrument settings, reads, protocols), then end to end (reconstruct_parent, ..., reconstruct_location).
# Results are compared as sets of rows; a call that throws must throw in both. The visibility rule itself
# (src/reconstruction/visibility.jl) is checked against the `ledger_subset` CTE for every operation table,
# and a mutation test plants wrong rules and requires the check to catch each of them.
#
# Size: CHESS_EQUIV_SEEDS (default 3) seeds, starting at CHESS_EQUIV_SEED_START (default 1), of
# CHESS_EQUIV_OPS (default 250) operations and CHESS_EQUIV_POINTS (default 40) query points each, so seed 3 is the
# one with a backward clock. A seed costs about 15 s to generate and 15 s to check, so the default run takes
# about 100 s. `find_locations(kind, active)` walks every location of a kind one by one and costs as much as all
# other checks together; the default run does it at every CHESS_EQUIV_KIND_EVERY-th (default 4) point. The
# nightly workflow (.github/workflows/equivalence-nightly.yml) runs 500 seeds of 3000 operations in shards, with
# every point, and sets CHESS_EQUIV_KIND_EVERY=1.
# On a mismatch the failing seed, query point and a reduced recipe are printed.

using Random, Test

include("legacy_reconstruction.jl")
include("generate_ledger.jl")

const EQV_SEEDS = parse(Int,get(ENV,"CHESS_EQUIV_SEEDS","3"))
const EQV_SEED_START = parse(Int,get(ENV,"CHESS_EQUIV_SEED_START","1"))   # the nightly job splits the seeds over shards
const EQV_OPS = parse(Int,get(ENV,"CHESS_EQUIV_OPS","250"))
const EQV_POINTS = parse(Int,get(ENV,"CHESS_EQUIV_POINTS","40"))
const EQV_KIND_EVERY = parse(Int,get(ENV,"CHESS_EQUIV_KIND_EVERY","4"))   # the costly find_locations(kind, active) check on every n-th point
const EQV_COSTLY = ["find_locations(kind, active)"]
const EQV_REDUCE_TRIALS = parse(Int,get(ENV,"CHESS_EQUIV_REDUCE_TRIALS","120"))

# ---------------------------------------------------------------------------------------------- comparison

# a hashable, order-insensitive picture of a result
eqv_canon(x::DataFrame) = (names(x),sort!([join(string.(Tuple(r)),"\u1f") for r in eachrow(x)]))
eqv_canon(x::AbstractVector) = [eqv_canon(v) for v in x]
eqv_canon(x) = string(x)

# call `f`; a throw becomes a value that must match the other implementation's throw
function eqv_try(f)
    try
        return (:ok,f())
    catch err
        err isa InterruptException && rethrow()
        return (:err,string(typeof(err)))
    end
end

# how often the comparisons were informative: a result with rows, an empty one, or both sides throwing
const EQV_STATS = Dict(:nonempty=>0,:empty=>0,:both_err=>0)
_eqv_empty(x::DataFrame) = nrow(x) == 0
_eqv_empty(x) = x isa Union{Missing,Nothing} || (x isa AbstractVector && isempty(x))

function eqv_same(a,b;canon=eqv_canon)
    a[1] === b[1] || return false
    if a[1] === :err
        EQV_STATS[:both_err] += 1
        return a[2] == b[2]
    end
    EQV_STATS[_eqv_empty(a[2]) ? :empty : :nonempty] += 1
    return canon(a[2]) == canon(b[2])
end

# what the closure comparisons covered, counted on the current implementation's results: results with rows,
# with collateral rows, with a discard, with a chain of at least three sources, with collateral from the hub
const EQV_CLOSURE_STATS = Dict(:ancestors=>0,:collateral=>0,:discard=>0,:chain=>0,:hub_collateral=>0,:descendants=>0)
const EQV_HUB = Ref(0)
function eqv_tally(M,df,kind)
    (M === CHESSDatabase && df isa DataFrame && nrow(df) > 0) || return df
    if kind === :ancestors
        EQV_CLOSURE_STATS[:ancestors] += 1
        coll = df[df.Core .== 0,:]
        nrow(coll) > 0 && (EQV_CLOSURE_STATS[:collateral] += 1)
        any(ismissing,df.Destination) && (EQV_CLOSURE_STATS[:discard] += 1)
        length(unique(df[df.Core .== 1,:Source])) >= 3 && (EQV_CLOSURE_STATS[:chain] += 1)
        any(coll.Source .== EQV_HUB[]) && (EQV_CLOSURE_STATS[:hub_collateral] += 1)
    else
        EQV_CLOSURE_STATS[:descendants] += 1
    end
    return df
end

# caches also have to come back in the same SequenceID order: callers take `caches[end,:]`
eqv_cache_canon(x::DataFrame) = (eqv_canon(x),x.SequenceID)

eqv_stock_summary(s) = sort!([(string(k),round(Float64(ustrip(uconvert(unit(v) isa Unitful.MassUnits ? u"g" : unit(v) isa Unitful.VolumeUnits ? u"µL" : unit(v),v)));sigdigits=9))
    for (k,v) in merge(Dict{Any,Any}(),solids(s),liquids(s),organisms(s))];by=string)

function eqv_snapshot(loc)
    parts = Any[]
    x = loc
    depth = 0
    while !isnothing(x) && depth < 12
        attrs = sort!([(string(k),string(CHESSCore.value(a))) for (k,a) in CHESSCore.attributes(x)])
        push!(parts,(:node,location_id(x),string(typeof(x)),attrs))
        x = CHESSCore.parent(x)
        depth += 1
    end
    c = children(loc)
    push!(parts,(:children,c isa AbstractMatrix ? [isassigned(c,i) ? location_id(c[i]) : nothing for i in eachindex(c)] : sort!(location_id.(collect(c)))))
    if loc isa CHESSCore.Well
        push!(parts,(:stock,eqv_stock_summary(CHESSCore.stock(loc))))
    end
    hasproperty(loc,:is_locked) && push!(parts,(:locked,CHESSCore.is_locked(loc)))
    hasproperty(loc,:lot) && push!(parts,(:lot,string(loc.lot)))
    push!(parts,(:active,CHESSCore.is_active(loc)))
    push!(parts,(:reads,sort!(string.(collect(CHESSCore.reads(loc))))))
    return parts
end


# What a depth fills (section 5 of the plan), as a value to compare with the same fields of the full reconstruction.
function eqv_depth_view(loc,d::Int)
    parts = Any[(:id,location_id(loc),string(typeof(loc)),CHESSCore.name(loc))]
    if d >= 1
        prt = CHESSCore.parent(loc)
        push!(parts,(:parent,isnothing(prt) ? nothing : location_id(prt)),(:active,CHESSCore.is_active(loc)))
        hasproperty(loc,:is_locked) && push!(parts,(:locked,CHESSCore.is_locked(loc)))
        hasproperty(loc,:lot) && push!(parts,(:lot,string(loc.lot)))
    end
    if d >= 2
        x = loc; n = 0
        while !isnothing(x) && n < 12
            push!(parts,(:node,location_id(x),sort!([(string(k),string(CHESSCore.value(a))) for (k,a) in CHESSCore.attributes(x)])))
            x = CHESSCore.parent(x); n += 1
        end
    end
    if d >= 3
        c = children(loc)
        push!(parts,(:children,c isa AbstractMatrix ? [isassigned(c,i) ? location_id(c[i]) : nothing for i in eachindex(c)] : sort!(location_id.(collect(c)))))
        loc isa CHESSCore.Well && push!(parts,(:stock,eqv_stock_summary(CHESSCore.stock(loc))))
    end
    d >= 5 && push!(parts,(:reads,sort!(string.(collect(CHESSCore.reads(loc))))))
    return parts
end


# The location a depth below 3 should return, put together from the frozen per-field functions (each of which is
# compared with the current one by the other checks): the full reconstruction can throw in its contents, which
# says nothing about the fields of the lower depths.
function eqv_legacy_pieces(p,d::Int)
    n,t = CHESSDatabase.get_location_info(p.loc)
    loc = d >= 2 ? Legacy.reconstruct_environment(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc) : t(p.loc,n)
    if d == 1
        loc.parent = CHESSCore.parent(Legacy.reconstruct_parent(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))
    end
    if d >= 1
        loc.is_active = CHESSCore.is_active(Legacy.reconstruct_activity(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))
        hasproperty(loc,:is_locked) && (loc.is_locked = CHESSCore.is_locked(Legacy.reconstruct_lock(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc)))
        hasproperty(loc,:lot) && (loc.lot = Legacy.reconstruct_lot(p.loc,p.seq,eqv_time(p)))
    end
    return loc
end

# the depths whose fields must equal those of the full reconstruction at the same point
const EQV_DEPTHS = (0,1,2,5)
# depth 5 costs as much as the full reconstruction, so it is checked at one point in four
eqv_depths(p) = p.loc % 4 == 0 ? EQV_DEPTHS : EQV_DEPTHS[1:3]

# ------------------------------------------------------------------------------------------ query points

struct EqvPoint
    loc::Int; loc2::Int; start::Int; seq::Int; tsec::Float64; max_cache::Int; enc::Bool
end
Base.show(io::IO,p::EqvPoint) = print(io,"(location=$(p.loc), other=$(p.loc2), starting=$(p.start), sequence_id=$(p.seq), time=origin+$(p.tsec)s, max_cache=$(p.max_cache), encumbrances=$(p.enc))")
eqv_time(p::EqvPoint) = eqv_clock_time(p.tsec)

# Locations, slots and times where something interesting happens: the slots that have been amended (more than
# one ledger row), the locations their operations touch, and the times at which each revision was written.
function eqv_hotspots()
    amended = query_db("SELECT SequenceID FROM Ledger GROUP BY SequenceID HAVING COUNT(*) > 1").SequenceID
    isempty(amended) && return (slots=Int[],times=Float64[],locations=Int[])
    list = join(amended,",")
    ids = query_db("SELECT ID, Time FROM Ledger WHERE SequenceID IN ($list)")
    idlist = join(ids.ID,",")
    locs = Int[]
    for (tbl,cols) in (("Transfers",["Source","Destination"]),("Movements",["Child","Parent"]),("EnvironmentAttributes",["LocationID"]),
            ("Locks",["LocationID"]),("Activity",["LocationID"]),("Reads",["LocationID"]),("ObservedParents",["Child"]),("ObservedAttributes",["LocationID"]))
        for c in cols
            append!(locs,skipmissing(query_db("SELECT DISTINCT $c AS id FROM $tbl WHERE LedgerID IN ($idlist)").id))
        end
    end
    return (slots=Int.(amended),times=Float64.(ids.Time .- EQV_CLOCK_ORIGIN),locations=unique(locs))
end

# Wells that take part in transfers and discards (most queries about a random location find nothing to follow), the
# hub reservoir that feeds most of them, and the wells the hub fed, which are downstream of a large closure.
function eqv_transfer_wells(w::EqvWorld)
    ends = query_db("SELECT DISTINCT Source AS id FROM Transfers UNION SELECT DISTINCT Destination FROM Transfers UNION SELECT DISTINCT Source FROM Discards").id
    return Int.(collect(skipmissing(ends)))
end

function eqv_points(rng,w::EqvWorld,n)
    maxid = query_db("SELECT Max(ID) FROM Ledger")[1,1]
    maxseq = query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
    hot = eqv_hotspots()
    twells = eqv_transfer_wells(w)
    hub = location_id(w.reservoirs[1])
    pts = EqvPoint[]
    for k in 1:n
        seq = rand(rng) < 0.25 ? maxseq : rand(rng,1:maxseq+2)
        tsec = rand(rng) < 0.3 ? Float64(rand(rng,0:maxid+1)) : rand(rng)*(maxid+2)   # integers hit a row's Time exactly
        rand(rng) < 0.2 && (tsec = Float64(maxid+100))                                    # "now"
        loc,loc2 = rand(rng,w.locations),rand(rng,w.locations)
        if !isempty(hot.slots) && k % 2 == 0          # every other point looks at an amended slot
            seq = rand(rng,hot.slots) + rand(rng,-1:3)
            tsec = rand(rng,hot.times) + rand(rng,(-1.0,-0.5,0.0,0.5,1.0))
            loc = rand(rng,hot.locations); loc2 = rand(rng,hot.locations)
        end
        if !isempty(twells) && k % 3 == 1             # a third of the points follow transfers, some of them from the hub
            loc = rand(rng) < 0.15 ? hub : rand(rng,twells); loc2 = rand(rng,twells)
            rand(rng) < 0.5 && (seq = rand(rng) < 0.5 ? maxseq : seq)
        end
        seq = clamp(seq,1,maxseq+2)
        push!(pts,EqvPoint(loc,loc2,rand(rng) < 0.5 ? 0 : rand(rng,0:seq),seq,tsec,rand(rng,0:seq),rand(rng) < 0.25))
    end
    return pts
end

# --------------------------------------------------------------------------------------- the comparisons

# (name, canon, call) where call(M, p) runs the function from module M (CHESSDatabase or Legacy) at point p
# Intended differences from `Legacy` (decision D5). Each entry is checked by its own test; here the oracle side is
# rebuilt from the frozen `Legacy` function it differs from, so the comparison still covers everything else.
#   transfers_touched_by without encumbrances: Legacy reads an EncumbranceID column that its ancestors query only
#   has with encumbrances=true and throws (ArgumentError) whenever there is a row to read. The intended result is
#   the same list with EncumbranceID 0 (test: "transfers_touch and transfers_touched_by" in test_transfer_closure.jl).
#   get_reads, superseded reads (D5): Legacy returns the reads of every revision of a slot, including those of a
#   revision a later amendment replaced. The intended result is the reads of the visible revisions only. The method
#   below adds that rule to `Legacy` for the Int/Int/DateTime call every comparison and `Legacy.reconstruct_reads!` make,
#   written as the original `ledger_subset` query so that it does not depend on `visible_join` (test: "get_reads hides
#   superseded reads" in test_local_series.jl). The frozen file is not edited.
#   push_location! out of order (found by the first deep run with the depth checks): Legacy appends an entry older than
#   the last one of a location, which breaks the sort order its binary search needs, and reconstruct_contents then throws a
#   MethodError (transfer with a missing destination) or reads a wrong snapshot. The intended result is the one the
#   method below gives: the entry is inserted in order. Tests: "push_location! keeps each history sorted" in
#   test_reconstruct_contents_order.jl and "reconstruct_contents with a cache at the slot before a transfer" below.
function Legacy.push_location!(index::Dict{<:Integer,<:Vector},location_id::Integer,sequence_id::Integer,loc::Location)
    entries = get!(() -> Tuple{Integer,Location}[], index, location_id)
    if isempty(entries) || entries[end][1] <= sequence_id
        push!(entries, (sequence_id, loc))
    else
        insert!(entries, searchsortedlast(entries, (sequence_id, nothing); by=first) + 1, (sequence_id, loc))
    end
    return nothing
end

function Legacy.get_reads(location_id::Int,sequence_id::Int,time::DateTime)
    lt = db_time(time)
    return query_db("""
        WITH ledger_subset (ID,SequenceID,Time) AS (SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $lt AND SequenceID BETWEEN 0 AND $sequence_id GROUP BY SequenceID)
        SELECT r.* FROM Reads r INNER JOIN ledger_subset l ON r.LedgerID = l.ID WHERE r.LocationID = $location_id ORDER BY r.ID""")
end

# the middle third of the times of the reads of the location, from the oracle's rows (the same for both sides)
function eqv_reads_window(p)
    df = Legacy.get_reads(p.loc,p.seq,eqv_time(p))
    nrow(df) < 3 && return (since=nothing,until=nothing)
    keys = sort!([Float64(something(r.InstrumentTime,r.Time)) for r in eachrow(df)])
    return (since=CHESSDatabase.julia_time(keys[cld(length(keys),3)]),until=CHESSDatabase.julia_time(keys[cld(2length(keys),3)]))
end

# a page of reads: the oracle side sorts and slices what `Legacy.get_reads` returns
function eqv_reads_page(M,p;limit,offset,newest_first,since=nothing,until=nothing)
    if M === Legacy
        df = Legacy.get_reads(p.loc,p.seq,eqv_time(p))
        key(r) = something(r.InstrumentTime,r.Time)
        rows = collect(eachrow(df))
        isnothing(since) || filter!(r->key(r) >= db_time(since),rows)
        isnothing(until) || filter!(r->key(r) <= db_time(until),rows)
        sort!(rows;by=r->(key(r),r.ID),rev=newest_first)
        rows = rows[min(offset+1,end+1):min(offset+limit,end)]
        return isempty(rows) ? df[1:0,:] : DataFrame(rows)
    end
    return M.get_reads(p.loc,p.seq,eqv_time(p);limit=limit,offset=offset,newest_first=newest_first,since=since,until=until)
end

function eqv_touched_by(M,p)
    if M === Legacy && !p.enc
        out = Legacy.get_transfer_ancestors([p.loc],p.start,p.seq,eqv_time(p);encumbrances=false)
        return Tuple{Integer,Integer,Integer}[(r.Destination,r.LedgerID,0) for r in eachrow(out) if !ismissing(r.Destination)]
    end
    return M.transfers_touched_by(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)
end

const EQV_FUNCTION_CHECKS = Tuple{String,Function,Function}[
    ("get_parent_caches",eqv_cache_canon,(M,p)->M.get_parent_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_child_caches",eqv_cache_canon,(M,p)->M.get_child_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_content_caches",eqv_cache_canon,(M,p)->M.get_content_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_attribute_caches",eqv_cache_canon,(M,p)->M.get_attribute_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_lock_caches",eqv_cache_canon,(M,p)->M.get_lock_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_activity_caches",eqv_cache_canon,(M,p)->M.get_activity_caches(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_last_movement_as_child",eqv_canon,(M,p)->M.get_last_movement_as_child([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_last_movements_as_parent",eqv_canon,(M,p)->M.get_last_movements_as_parent([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_child_movements",eqv_canon,(M,p)->M.get_child_movements([p.loc],Dict{Integer,Integer}(p.loc2=>p.loc),p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_locks",eqv_canon,(M,p)->M.get_locks([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_activity",eqv_canon,(M,p)->M.get_activity([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_environment_attributes",eqv_canon,(M,p)->M.get_environment_attributes([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_transfer_ancestors",eqv_canon,(M,p)->eqv_tally(M,M.get_transfer_ancestors([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc),:ancestors)),
    ("get_transfer_descendents",eqv_canon,(M,p)->eqv_tally(M,M.get_transfer_descendents([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc),:descendants)),
    ("transfers_touch",eqv_canon,(M,p)->M.transfers_touch(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("transfers_touched_by",eqv_canon,(M,p)->eqv_touched_by(M,p)),
    ("get_reads(page, newest first)",eqv_canon,(M,p)->eqv_reads_page(M,p;limit=3,offset=1,newest_first=true)),
    ("get_reads(since, until)",eqv_canon,(M,p)->eqv_reads_page(M,p;limit=1000,offset=0,newest_first=false,eqv_reads_window(p)...)),
    ("get_content_observations",eqv_canon,(M,p)->M.get_content_observations([p.loc,p.loc2],p.start,p.seq,eqv_time(p))),
    ("observation_discrepancies",eqv_canon,(M,p)->M.observation_discrepancies([p.loc,p.loc2];sequence_id=p.seq,time=eqv_time(p))),
    ("get_instrument_settings",eqv_canon,(M,p)->M.get_instrument_settings(p.loc,p.seq,eqv_time(p))),
    ("get_reads",eqv_canon,(M,p)->M.get_reads(p.loc,p.seq,eqv_time(p))),
    ("get_all_protocols",eqv_canon,(M,p)->M.get_all_protocols(p.seq,eqv_time(p);enforced_only=p.enc)),
    ("reconstruct_lot",eqv_canon,(M,p)->M.reconstruct_lot(p.loc,p.seq,eqv_time(p))),
    ("trace_forward(well)",eqv_canon,(M,p)->M.trace_forward(p.loc,p.seq,eqv_time(p))),
    ("trace_forward(lot)",eqv_canon,(M,p)->M.trace_forward(Lot("EQV Supplier","EQV-$(p.loc % 2)","LOT$(p.loc2 % 4)"),p.seq,eqv_time(p))),
    ("trace_contents",eqv_canon,(M,p)->M.trace_contents(p.loc,p.seq,eqv_time(p))),
    ("reconstruct_cost",eqv_canon,(M,p)->M.reconstruct_cost(p.loc,p.seq,eqv_time(p))),
    ("find_locations()",eqv_canon,(M,p)->M.find_locations(;sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(parent)",eqv_canon,(M,p)->M.find_locations(;parent=p.loc,sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(kind, active)",eqv_canon,(M,p)->M.find_locations(;kind=p.enc ? :WP96 : :Well200,active=p.loc2 % 2 == 0,sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(no parent)",eqv_canon,(M,p)->M.find_locations(;parent=nothing,kind=:WP96,sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(name)",eqv_canon,(M,p)->M.find_locations(;name=query_db("SELECT Name FROM Locations WHERE ID = ?",(p.loc,)).Name[1],sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(name, ignorecase)",eqv_canon,(M,p)->M.find_locations(;name=uppercase(query_db("SELECT Name FROM Locations WHERE ID = ?",(p.loc,)).Name[1]),ignorecase=true,sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(barcode)",eqv_canon,(M,p)->M.find_locations(;barcode=get(query_db("SELECT Barcode FROM Barcodes WHERE LocationID = ?",(p.loc,)).Barcode,1,"none"),sequence_id=p.seq,time=eqv_time(p))),
    ("find_locations(parent, limit)",eqv_canon,(M,p)->M.find_locations(;parent=p.loc,limit=3,offset=1,sequence_id=p.seq,time=eqv_time(p))),
    ("descendants",eqv_canon,(M,p)->M.descendants(p.loc;sequence_id=p.seq,time=eqv_time(p))),
    ("descendants(kinds, depth)",eqv_canon,(M,p)->M.descendants(p.loc;kinds=[:Well200],max_depth=2,sequence_id=p.seq,time=eqv_time(p))),
    ("get_last_sequence_id",eqv_canon,(M,p)->M.get_last_sequence_id(eqv_time(p))),
    ("get_last_ledger_id(time)",eqv_canon,(M,p)->M.get_last_ledger_id(eqv_time(p))),
    ("get_last_ledger_id(slot,time)",eqv_canon,(M,p)->M.get_last_ledger_id(p.seq,eqv_time(p))),
    ("get_all_ledger_ids",eqv_canon,(M,p)->M.get_all_ledger_ids(p.seq,eqv_time(p))),
]

# end to end; the result is a snapshot of the reconstructed location
const EQV_END_TO_END = Tuple{String,Function}[
    ("reconstruct_parent",(M,p)->eqv_snapshot(M.reconstruct_parent(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_children",(M,p)->eqv_snapshot(M.reconstruct_children(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_attributes",(M,p)->eqv_snapshot(M.reconstruct_attributes(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_environment",(M,p)->eqv_snapshot(M.reconstruct_environment(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_contents",(M,p)->eqv_snapshot(M.reconstruct_contents(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_lock",(M,p)->eqv_snapshot(M.reconstruct_lock(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_activity",(M,p)->eqv_snapshot(M.reconstruct_activity(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_reads",(M,p)->eqv_snapshot(M.reconstruct_reads(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
    ("reconstruct_location",(M,p)->eqv_snapshot(M.reconstruct_location(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc))),
]

struct EqvMismatch
    check::String; point::EqvPoint
end

"""
    eqv_check_point(p; end_to_end=true) -> Vector{EqvMismatch}

Every disagreement between the current functions and `Legacy` at query point `p`.
"""
function eqv_check_point(p::EqvPoint;end_to_end::Bool=true,only::Union{Nothing,String}=nothing,skip::Vector{String}=String[])
    out = EqvMismatch[]
    for (name,canon,call) in EQV_FUNCTION_CHECKS
        isnothing(only) || name == only || continue
        name in skip && continue
        new = eqv_try(()->call(CHESSDatabase,p)); old = eqv_try(()->call(Legacy,p))
        eqv_same(new,old;canon=canon) || push!(out,EqvMismatch(name,p))
    end
    if end_to_end
        for (name,call) in EQV_END_TO_END
            isnothing(only) || name == only || continue
            new = eqv_try(()->call(CHESSDatabase,p)); old = eqv_try(()->call(Legacy,p))
            eqv_same(new,old;canon=identity) || push!(out,EqvMismatch(name,p))
        end
        if isnothing(only) || startswith(only,"reconstruct_location(depth")
            full = nothing   # the full reconstruction, made once and only when a depth is compared with it
            for d in eqv_depths(p)
                name = "reconstruct_location(depth=$d)"
                (isnothing(only) || only == name) || continue
                new = eqv_try(()->eqv_depth_view(CHESSDatabase.reconstruct_location(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc,depth=d),d))
                if d <= 2
                    # the fields of a depth below 3 do not depend on the contents, which can make the full reconstruction throw
                    old = eqv_try(()->eqv_depth_view(eqv_legacy_pieces(p,d),d))
                else
                    isnothing(full) && (full = eqv_try(()->Legacy.reconstruct_location(p.loc,p.seq,eqv_time(p),p.max_cache;encumbrances=p.enc)))
                    old = full[1] === :err ? full : eqv_try(()->eqv_depth_view(full[2],d))
                end
                eqv_same(new,old;canon=identity) || push!(out,EqvMismatch(name,p))
            end
        end
    end
    return out
end

# ------------------------------------------------------------------------------------- the history property
#
# For every facet, every slot s and every time t: the value at s of reconstruct_history(...; time=t) equals the matching
# reconstruct_* at (s, t). A history is computed once per (location, facet, time) over the whole ledger and compared at
# a sample of slots (CHESS_EQUIV_HISTORY_SLOTS=all checks every slot): its own change points and their neighbours,
# the first and last slots, and random ones.

const EQV_HISTORY_LOCS = parse(Int,get(ENV,"CHESS_EQUIV_HISTORY_LOCS","4"))
const EQV_HISTORY_SLOTS = get(ENV,"CHESS_EQUIV_HISTORY_SLOTS","2")
# the fraction of histories that are also read page by page (tiny pages and windows) and without collapse
const EQV_HISTORY_PAGED = parse(Float64,get(ENV,"CHESS_EQUIV_HISTORY_PAGED","0"))
const EQV_HISTORY_CONTENTS_SLOTS = parse(Int,get(ENV,"CHESS_EQUIV_HISTORY_CONTENTS_SLOTS","3"))
const EQV_HISTORY_ENC = get(ENV,"CHESS_EQUIV_HISTORY_ENC","1") != "0"   # the same property with planned operations (encumbrances=true)
const EQV_HISTORY_TIMES = parse(Int,get(ENV,"CHESS_EQUIV_HISTORY_TIMES","2"))
const EQV_HISTORY_STATS = Dict{Symbol,Real}(:histories=>0,:rows=>0,:slots=>0,:effective_from_ancestor=>0,:paged=>0,:seconds=>0.0,:build_seconds=>0.0)

struct EqvHistoryMismatch
    loc::Int; facet::Any; slot::Int; tsec::Float64; got::Any; want::Any
end

function eqv_attr_quantity(dict,name::String)
    for (k,a) in dict
        kname = k isa Symbol ? k : hasproperty(k,:name) ? k.name : Symbol(string(k))
        kname === Symbol(name) || continue
        return ismissing(CHESSCore.value(a)) ? missing : CHESSCore.quantity(a)
    end
    return missing
end

eqv_history_unit(u) = ismissing(u) ? Unitful.NoUnits : CHESSDatabase._parse_unit(u)

# true when the history's value `got` and the reconstruction's value `want` are the same
function eqv_history_equal(got,unit,want)
    if ismissing(got) || ismissing(want)
        return ismissing(got) && ismissing(want)
    end
    want isa Unitful.Quantity || return got == want
    u = eqv_history_unit(unit)
    return isapprox(ustrip(uconvert(u,want)),got;rtol=1e-9,atol=1e-9)
end

# (facet, label, oracle(id, s, time) -> value) for the facets of a location
function eqv_history_facets(id::Int;enc::Bool=false)
    n,t = CHESSDatabase.get_location_info(id)
    blank = t(id,n)
    out = Tuple{Any,String,Function}[]
    for name in ("Temperature","Humidity")
        push!(out,(Symbol(name),name * " effective",(i,s,tm)->eqv_attr_quantity(CHESSCore.environment(CHESSDatabase.reconstruct_environment(i,s,tm;encumbrances=enc)),name)))
        push!(out,(Symbol(name),name * " own",(i,s,tm)->eqv_attr_quantity(CHESSCore.attributes(CHESSDatabase.reconstruct_attributes(i,s,tm;encumbrances=enc)),name)))
    end
    push!(out,(:parent,"parent",(i,s,tm)->(prt = CHESSCore.parent(CHESSDatabase.reconstruct_parent(i,s,tm;encumbrances=enc)); isnothing(prt) ? missing : location_id(prt))))
    hasproperty(blank,:is_locked) && push!(out,(:locked,"locked",(i,s,tm)->CHESSCore.is_locked(CHESSDatabase.reconstruct_lock(i,s,tm;encumbrances=enc))))
    push!(out,(:active,"active",(i,s,tm)->CHESSCore.is_active(CHESSDatabase.reconstruct_activity(i,s,tm;encumbrances=enc))))
    hasproperty(blank,:lot) && push!(out,(:lot,"lot",(i,s,tm)->(l = CHESSDatabase.reconstruct_lot(i,s,tm); isnothing(l) ? missing : "$(l.supplier) $(l.catalog_number) lot $(l.lot)")))
    blank isa CHESSCore.Well && push!(out,(:contents,"contents",(i,s,tm)->eqv_stock_summary(CHESSCore.stock(CHESSDatabase.reconstruct_contents(i,s,tm;encumbrances=enc)))))
    return out
end

function eqv_history_setting_facets(;enc::Bool=false)
    names = String.(query_db("SELECT DISTINCT Setting FROM InstrumentSettings").Setting)
    return [((:setting,nm),"setting $nm",(i,s,tm)->(r = CHESSDatabase.get_instrument_settings(i,s,tm); k = findfirst(==(nm),r.Setting); isnothing(k) ? missing : r.Value[k])) for nm in names]
end

function eqv_history_slot_sample(rng,h::DataFrame,maxseq::Int)
    EQV_HISTORY_SLOTS == "all" && return collect(0:maxseq)
    near = Int[0,maxseq]
    for s in h.SequenceID
        append!(near,(s - 1,s,s + 1))
    end
    append!(near,rand(rng,0:maxseq,parse(Int,EQV_HISTORY_SLOTS)))
    return sort!(unique!(filter(s -> 0 <= s <= maxseq,near)))
end

# The locations that planned operations are on: the child of a planned movement, a location with a planned lock, activity
# or attribute, the destination of a planned transfer, and the wells and plates below them that see the change.
function eqv_planned_locations(rng,w::EqvWorld)
    ids = Int[]
    for (tbl,col) in (("EncumberedMovements","Child"),("EncumberedLocks","LocationID"),("EncumberedActivity","LocationID"),
                      ("EncumberedEnvironments","LocationID"),("EncumberedTransfers","Destination"))
        append!(ids,Int.(skipmissing(query_db("SELECT DISTINCT $col AS id FROM $tbl").id)))
    end
    # the world's own locations only: the fixture database has planned operations of its own on locations the ledger does not move
    ids = filter(in(w.locations),unique(ids))
    n = parse(Int,get(ENV,"CHESS_EQUIV_HISTORY_PLANNED","3"))
    return length(ids) <= n ? ids : rand(rng,ids,n)
end

function eqv_check_history(rng,w::EqvWorld;enc::Bool=false)
    t_start = time()
    out = EqvHistoryMismatch[]
    maxseq = query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
    maxid = query_db("SELECT Max(ID) FROM Ledger")[1,1]
    hot = eqv_hotspots()
    ids = Int[location_id(w.wells[1]),location_id(w.shelves[1]),location_id(w.plates[1]),location_id(w.bottles[1])]
    append!(ids,rand(rng,w.locations,max(EQV_HISTORY_LOCS - length(ids),0)))
    !isempty(hot.locations) && push!(ids,rand(rng,hot.locations))
    enc && append!(ids,eqv_planned_locations(rng,w))
    times = Float64[maxid + 100.0]
    append!(times,isempty(hot.times) ? rand(rng,EQV_HISTORY_TIMES - 1) .* (maxid + 2) : rand(rng,hot.times,EQV_HISTORY_TIMES - 1) .+ rand(rng,(-0.5,0.0,0.5),EQV_HISTORY_TIMES - 1))
    reader = location_id(w.reader)
    for tsec in unique(times)
        tm = eqv_clock_time(tsec)
        for id in unique(ids)
            for (facet,label,oracle) in eqv_history_facets(id;enc=enc)
                eff = endswith(label,"effective") ? true : (endswith(label,"own") ? false : nothing)
                t_build = time()
                h = CHESSDatabase.reconstruct_history(id,facet;from=0,to=maxseq,time=tm,effective=eff,encumbrances=enc)
                EQV_HISTORY_STATS[:build_seconds] += time() - t_build
                eqv_history_check!(out,rng,h,id,label,oracle,tm,tsec,maxseq;enc=enc)
                eff === true && any(!=(id),h.Origin) && (EQV_HISTORY_STATS[:effective_from_ancestor] += 1)
            end
        end
        enc || for (facet,label,oracle) in eqv_history_setting_facets()   # instrument settings have no planned operations
            h = CHESSDatabase.reconstruct_history(reader,facet;from=0,to=maxseq,time=tm)
            eqv_history_check!(out,rng,h,reader,label,oracle,tm,tsec,maxseq)
        end
    end
    EQV_HISTORY_STATS[:seconds] += time() - t_start
    return out
end

# all the pages of a history, with windows that start small so that every page spans several of them
function eqv_history_pages(id,facet,tm,maxseq,eff,order,limit;enc::Bool=false)
    old = (CHESSDatabase._HISTORY_FIRST_WINDOW[],CHESSDatabase._HISTORY_GROWTH[])
    CHESSDatabase._HISTORY_FIRST_WINDOW[] = 3; CHESSDatabase._HISTORY_GROWTH[] = 2
    try
        pages = DataFrame[]; after = nothing
        while true
            pg = CHESSDatabase.reconstruct_history(id,facet;from=0,to=maxseq,time=tm,effective=eff,order=order,limit=limit,after=after,encumbrances=enc)
            nrow(pg) == 0 && break
            push!(pages,pg)
            after = pg.SequenceID[end]
            nrow(pg) < limit && break
            length(pages) > 10_000 && break
        end
        return isempty(pages) ? CHESSDatabase._history_frame() : reduce(vcat,pages)
    finally
        CHESSDatabase._HISTORY_FIRST_WINDOW[],CHESSDatabase._HISTORY_GROWTH[] = old
    end
end

# the facet and the `effective` flag a label stands for
function facet_of(label)
    startswith(label,"setting ") && return ((:setting,label[9:end]),nothing)
    endswith(label,"effective") && return (Symbol(split(label)[1]),true)
    endswith(label,"own") && return (Symbol(split(label)[1]),false)
    return (Symbol(label),nothing)
end

eqv_same_frame(a::DataFrame,b::DataFrame) = nrow(a) == nrow(b) && all(isequal(a[!,c],b[!,c]) for c in names(b))

function eqv_history_check!(out,rng,h,id,label,oracle,tm,tsec,maxseq;enc::Bool=false)
    EQV_HISTORY_STATS[:histories] += 1
    EQV_HISTORY_STATS[:rows] += nrow(h)
    # a history is ordered, and has at most one row for a slot
    (issorted(h.SequenceID) && allunique(h.SequenceID)) || push!(out,EqvHistoryMismatch(id,label,-1,tsec,"not strictly ordered",h.SequenceID))
    if rand(rng) < EQV_HISTORY_PAGED
        f,eff = facet_of(label)
        for order in (rand(rng,Bool) ? (:asc,) : (:desc,))
            pages = eqv_history_pages(id,f,tm,maxseq,eff,order,2;enc=enc)
            whole = order === :asc ? h : h[end:-1:1,:]
            # the first row of a window is the state in force at `from`; it is part of the whole history only when it was recorded
            eqv_same_frame(pages,whole) || push!(out,EqvHistoryMismatch(id,label * " paged $order",-1,tsec,pages,whole))
        end
        EQV_HISTORY_STATS[:paged] += 1
        if eff !== true
            raw = CHESSDatabase.reconstruct_history(id,f;from=0,to=maxseq,time=tm,effective=eff,collapse=false,encumbrances=enc)
            for s in eqv_history_slot_sample(rng,h,maxseq)
                a,b = CHESSDatabase.history_value_at(raw,s),CHESSDatabase.history_value_at(h,s)
                (ismissing(a) && ismissing(b)) || isequal(a,b) || push!(out,EqvHistoryMismatch(id,label * " collapse=false",s,tsec,a,b))
            end
        end
    end
    sample = eqv_history_slot_sample(rng,h,maxseq)
    # a stock costs a replay at every slot: fewer slots for it
    label == "contents" && length(sample) > EQV_HISTORY_CONTENTS_SLOTS && (sample = sort!(rand(rng,sample,EQV_HISTORY_CONTENTS_SLOTS)))
    for s in sample
        EQV_HISTORY_STATS[:slots] += 1
        want = oracle(id,s,tm)
        got = CHESSDatabase.history_value_at(h,s)
        label == "contents" && (got = eqv_stock_summary(ismissing(got) ? Empty() : got))
        k = searchsortedlast(h.SequenceID,s)
        unit = k == 0 ? missing : h.Unit[k]
        # nothing recorded: the facet has its default value
        if ismissing(got) && !ismissing(want) && k == 0 && label in ("locked","active")
            got = label == "active"
        end
        eqv_history_equal(got,unit,want) || push!(out,EqvHistoryMismatch(id,label,s,tsec,got,want))
    end
    return nothing
end

# ---------------------------------------------------------------------------------- the visibility rule

const EQV_OPERATION_TABLES = ["Transfers","Movements","EnvironmentAttributes","Reads","Locks","Activity","InstrumentSettings",
    "CachedContents","CachedAncestors","CachedDescendants","CachedEnvironments","CachedLockActivity",
    "ObservedParents","ObservedAttributes","ObservedLocks","ObservedActivity","ObservedComponents","ProtocolEnforcement","Discards","ObservedLots"]

"""
    eqv_check_visibility(rng, w, n; predicate) -> Int

Number of disagreements, over `n` random windows and times, between the rows `visible_join` keeps (with
`predicate` as the rule) and the rows whose ledger row is in the original `ledger_subset` CTE, for every
operation table; also `visible_ledger_id` and `is_visible` against the CTE.
"""
function eqv_check_visibility(rng,n;predicate=CHESSDatabase._visible_predicate)
    maxid = query_db("SELECT Max(ID) FROM Ledger")[1,1]
    maxseq = query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
    bad = 0
    for _ in 1:n
        from = rand(rng) < 0.5 ? 0 : rand(rng,0:maxseq); to = rand(rng) < 0.3 ? maxseq : rand(rng,from:maxseq+1)
        tsec = rand(rng) < 0.5 ? Float64(rand(rng,0:maxid+1)) : rand(rng)*(maxid+2)
        t = eqv_clock_time(tsec); lt = db_time(t)
        cte = "WITH ledger_subset (ID,SequenceID,Time) AS (SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $lt AND SequenceID BETWEEN $from AND $to GROUP BY SequenceID)"
        for tbl in EQV_OPERATION_TABLES
            expected = query_db("$cte SELECT o.ID FROM $tbl o INNER JOIN ledger_subset l ON o.LedgerID = l.ID ORDER BY o.ID").ID
            actual = query_db("SELECT o.ID FROM $tbl o " * CHESSDatabase.visible_join("o";from="$from",to="$to",t="$lt",predicate=predicate) * " ORDER BY o.ID").ID
            expected == actual || (bad += 1)
        end
        expected = query_db("$cte SELECT ID FROM ledger_subset ORDER BY ID").ID
        actual = query_db("SELECT o.ID FROM (SELECT ID AS LedgerID, ID FROM Ledger) o " * CHESSDatabase.visible_join("o";from="$from",to="$to",t="$lt",predicate=predicate) * " ORDER BY o.ID").ID
        expected == actual || (bad += 1)
    end
    return bad
end

# ------------------------------------------------------------------------------------------- reduction

function eqv_ledger_dump(io::IO)
    println(io,"Ledger (ID, SequenceID, Time-origin):")
    for r in eachrow(query_db("SELECT ID, SequenceID, Time FROM Ledger ORDER BY ID"))
        println(io,"  ",r.ID,"\t",r.SequenceID,"\t",r.Time - EQV_CLOCK_ORIGIN)
    end
    for tbl in ("Transfers","Movements","EnvironmentAttributes","Locks","Activity","Reads")
        println(io,"$tbl: ",query_db("SELECT COUNT(*) FROM $tbl")[1,1]," rows")
    end
end

"""
    eqv_reduce(seed, clock, recipe, mismatch, trials) -> (reduced_recipe, io_dump)

Shrink `recipe` while `mismatch.check` still disagrees at the same query point, then describe the result.
Operations never create locations, so location ids are the same for every sub-recipe of one seed.
"""
function eqv_reduce(seed,clock,recipe,mismatch::EqvMismatch;trials::Int=EQV_REDUCE_TRIALS)
    count = 0
    function still_fails(trial)
        count += 1
        with_scratch_db() do _
            eqv_generate(seed;recipe=trial,clock=clock)
            return !isempty(eqv_check_point(mismatch.point;end_to_end=true,only=mismatch.check))
        end
    end
    keep = collect(recipe)
    chunk = max(1,length(keep) ÷ 2)
    while chunk >= 1 && count < trials
        i = 1
        while i <= length(keep) && count < trials
            trial = vcat(keep[1:i-1],keep[min(length(keep)+1,i+chunk):end])
            if !isempty(trial) && still_fails(trial)
                keep = trial
            else
                i += chunk
            end
        end
        chunk ÷= 2
    end
    io = IOBuffer()
    println(io,"reduced recipe ($(length(keep)) of $(length(recipe)) operations, $count trials):")
    for op in keep
        println(io,"  ",op)
    end
    with_scratch_db() do _
        eqv_generate(seed;recipe=keep,clock=clock)
        eqv_ledger_dump(io)
    end
    return keep,String(take!(io))
end

# ------------------------------------------------------------------------------------------------ tests

@testset "equivalence: current reconstruction == frozen original" begin
    total_points = Ref(0); total_checks = Ref(0)
    for seed in EQV_SEED_START:EQV_SEED_START+EQV_SEEDS-1
        clock = seed % 3 == 0 ? :backward : :monotone
        @testset "seed $seed ($clock clock)" begin
            t_seed = time()
            with_scratch_db() do _
                recipe = eqv_recipe(seed,EQV_OPS)
                w = eqv_generate(seed;recipe=recipe,clock=clock)
                EQV_HUB[] = location_id(w.reservoirs[1])
                haskey(ENV,"CHESS_EQUIV_PROGRESS") && (println(stderr,"seed $seed generated ",round(time()-t_seed;digits=1)," s"); flush(stderr))
                rng = Xoshiro(10_000 + seed)
                # the generator must produce a ledger worth testing
                n_amended = query_db("SELECT COUNT(*) FROM (SELECT SequenceID FROM Ledger GROUP BY SequenceID HAVING COUNT(*) > 1)")[1,1]
                @test length(w.executed) > EQV_OPS ÷ 3
                EQV_OPS >= 100 && @test n_amended > 0

                points = eqv_points(rng,w,EQV_POINTS)
                mismatches = EqvMismatch[]
                for (i,p) in enumerate(points)
                    haskey(ENV,"CHESS_EQUIV_PROGRESS") && (println(stderr,"seed $seed point $i ",round(time()-t_seed;digits=1)," s"); flush(stderr))
                    append!(mismatches,eqv_check_point(p;end_to_end=i % 2 == 1,skip = i % EQV_KIND_EVERY == 0 ? String[] : EQV_COSTLY)) # the end-to-end functions on every other point
                end
                hist = eqv_check_history(Xoshiro(20_000 + seed),w)
                if !isempty(hist)
                    @error "history differs from the reconstruction" seed clock nops=EQV_OPS count=length(hist) first_mismatches=hist[1:min(5,end)]
                end
                @test isempty(hist)
                if EQV_HISTORY_ENC
                    hist_enc = eqv_check_history(Xoshiro(30_000 + seed),w;enc=true)
                    if !isempty(hist_enc)
                        @error "history with planned operations differs from the reconstruction" seed clock nops=EQV_OPS count=length(hist_enc) first_mismatches=hist_enc[1:min(5,end)]
                    end
                    @test isempty(hist_enc)
                end
                total_points[] += length(points)
                total_checks[] += length(points) * length(EQV_FUNCTION_CHECKS) + cld(length(points),2) * length(EQV_END_TO_END)
                vis = eqv_check_visibility(rng,EQV_POINTS)
                @test vis == 0
                if !isempty(mismatches)
                    first_mismatch = first(mismatches)
                    reduced = try
                        eqv_reduce(seed,clock,recipe,first_mismatch)[2]
                    catch err
                        "(reduction failed: $err)"
                    end
                    @error "reconstruction differs from the original" seed clock nops=EQV_OPS mismatching_checks=unique(m.check for m in mismatches) first_point=first_mismatch.point
                    println(stderr,reduced)
                end
                @test isempty(mismatches)
                haskey(ENV,"CHESS_EQUIV_PROGRESS") && @info "seed $seed: $(round(time()-t_seed;digits=1)) s, $(length(points)) points"
            end
        end
    end
    if total_points[] >= 100      # the comparisons must have reached the interesting corners of the closure
        for (k,v) in EQV_CLOSURE_STATS
            k === :chain && total_points[] < 200 && continue     # a chain of three sources is rare; the nightly run and test_transfer_closure.jl cover it
            @test v > 0
            v == 0 && @warn "closure comparisons never covered" k
        end
    end
    @info "equivalence closure coverage: $(EQV_CLOSURE_STATS)"
    @info "equivalence history: $(EQV_HISTORY_STATS)"
    @info "equivalence: $(total_points[]) query points, about $(total_checks[]) function comparisons; results with rows: $(EQV_STATS[:nonempty]), empty: $(EQV_STATS[:empty]), both threw: $(EQV_STATS[:both_err])"
end

@testset "equivalence: planted wrong visibility rules are caught" begin
    # Each mutation changes one thing in the rule. The check must report a disagreement with the original
    # `ledger_subset` on at least one of the generated ledgers, and must report none for the real rule.
    mutations = Dict(
        "superseded revision still visible (NOT EXISTS dropped)" => (l,f,t,u) -> "$l.SequenceID BETWEEN $f AND $t AND $l.Time <= $u",
        "r.ID >= instead of r.ID >" => (l,f,t,u) -> replace(CHESSDatabase._visible_predicate(l,f,t,u),"r.ID > $l.ID"=>"r.ID >= $l.ID"),
        "older revision wins (r.ID < instead of r.ID >)" => (l,f,t,u) -> replace(CHESSDatabase._visible_predicate(l,f,t,u),"r.ID > $l.ID"=>"r.ID < $l.ID"),
        "later revision must be strictly earlier (r.Time < t)" => (l,f,t,u) -> replace(CHESSDatabase._visible_predicate(l,f,t,u),"r.Time <= $u"=>"r.Time < $u"),
        "ledger row strictly before t (vl.Time < t)" => (l,f,t,u) -> replace(CHESSDatabase._visible_predicate(l,f,t,u),"$l.Time <= $u"=>"$l.Time < $u"),
        "window end exclusive" => (l,f,t,u) -> replace(CHESSDatabase._visible_predicate(l,f,t,u),"BETWEEN $f AND $t"=>">= $f AND $l.SequenceID < $t"),
    )
    caught = Dict(name=>0 for name in keys(mutations))
    real_rule_bad = 0
    for seed in 1:3
        with_scratch_db() do _
            eqv_generate(seed;nops=min(EQV_OPS,150),clock = seed == 3 ? :backward : :monotone)
            rng = Xoshiro(seed)
            real_rule_bad += eqv_check_visibility(rng,40)
            for (name,pred) in mutations
                caught[name] += eqv_check_visibility(Xoshiro(seed),40;predicate=pred)
            end
        end
    end
    @test real_rule_bad == 0
    for (name,n) in caught
        @test n > 0
        n == 0 && @warn "mutation not caught" name
    end
end


@testset "latest_visible_event agrees with a brute-force search under every walk/scan schedule" begin
    # (first window, growth, series factor): tiny windows that grow slowly; the walk only; the series scan after one failed walk
    schedules = [(1,2,1),(3,3,0),(10^6,8,4),(1,2,10^9),(128,8,4)]
    old = (CHESSDatabase._WALK_FIRST_WINDOW[],CHESSDatabase._WALK_GROWTH[],CHESSDatabase._SERIES_SCAN_FACTOR[])
    checked = 0
    try
        for seed in (1,2)
            with_scratch_db() do _
                eqv_generate(seed;nops=120,clock = seed == 2 ? :backward : :monotone)
                rng = Xoshiro(seed)
                maxid = query_db("SELECT Max(ID) FROM Ledger")[1,1]; maxseq = query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
                keys = Tuple[]
                for (tbl,cols) in (("Movements",["Child"]),("ObservedParents",["Child"]),("Locks",["LocationID"]),("Activity",["LocationID"]),
                        ("EnvironmentAttributes",["LocationID","Attribute"]),("InstrumentSettings",["InstrumentID","Setting"]),("Reads",["LocationID"]))
                    for r in eachrow(query_db("SELECT DISTINCT $(join(cols,",")) FROM $tbl"))
                        push!(keys,(tbl,cols,Tuple(r)))
                    end
                end
                for _ in 1:150
                    tbl,cols,vals = rand(rng,keys)
                    from = rand(rng) < 0.5 ? 0 : rand(rng,0:maxseq); to = rand(rng) < 0.3 ? maxseq + 5 : rand(rng,from:maxseq+1)
                    t = eqv_clock_time(rand(rng) < 0.5 ? Float64(rand(rng,0:maxid+1)) : rand(rng)*(maxid+2))
                    conds = join(["e.$c = ?" for c in cols]," AND ")
                    expected = query_db("""WITH ledger_subset (ID,SequenceID,Time) AS (SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= ? AND SequenceID BETWEEN ? AND ? GROUP BY SequenceID)
                        SELECT l.ID AS ledger_id, l.SequenceID AS slot FROM $tbl e INNER JOIN ledger_subset l ON e.LedgerID = l.ID WHERE $conds ORDER BY l.SequenceID DESC LIMIT 1""",
                        (db_time(t),from,to,vals...))
                    expected = nrow(expected) == 0 ? nothing : (ledger_id=expected.ledger_id[1],slot=expected.slot[1])
                    for (w,g,f) in schedules
                        CHESSDatabase._WALK_FIRST_WINDOW[],CHESSDatabase._WALK_GROWTH[],CHESSDatabase._SERIES_SCAN_FACTOR[] = w,g,f
                        got = CHESSDatabase.latest_visible_event(tbl,[c=>v for (c,v) in zip(cols,vals)],from,to,t)
                        @test got == expected
                        checked += 1
                    end
                end
            end
        end
    finally
        CHESSDatabase._WALK_FIRST_WINDOW[],CHESSDatabase._WALK_GROWTH[],CHESSDatabase._SERIES_SCAN_FACTOR[] = old
    end
    @test checked == 2 * 150 * length(schedules)
end

# The two reduced recipes of the first deep run with the depth checks (seeds 401 and 402). At these points the full
# reconstruction used to throw a MethodError in reconstruct_contents (see push_location!; fixed since), while the fields of
# depth 0 to 2 do not read contents and were returned. The depth checks compared them with the throwing full reconstruction
# and reported a difference that was not one; they now use the per-field reference of eqv_legacy_pieces.
@testset "equivalence: depth 0 to 2 do not depend on a full reconstruction that throws" begin
    recipes = [
        (401,:monotone,EqvPoint(30,172,0,2432,1160.0378254879452,1795,false),[
            (n = 316, kind = :transfer, i = 3821, j = 5407, k = 8027, x = 0.7120814260067496, y = 0.02221964433860557, flag = false),
            (n = 392, kind = :cache, i = 3234, j = 8891, k = 681, x = 0.9715930409513767, y = 0.7278129169399845, flag = false),
            (n = 564, kind = :transfer, i = 8163, j = 978, k = 6622, x = 0.7870249580900325, y = 0.38423396913829877, flag = false),
            (n = 723, kind = :transfer, i = 6665, j = 2143, k = 3233, x = 0.6008021060675547, y = 0.08145263447133844, flag = false)]),
        (402,:backward,EqvPoint(185,86,152,1779,871.1436693162698,1651,false),[
            (n = 862, kind = :transfer, i = 8319, j = 9990, k = 7442, x = 0.011703510067311407, y = 0.8518725811529935, flag = false),
            (n = 866, kind = :cache, i = 8614, j = 3267, k = 8868, x = 0.4370251404644022, y = 0.11942053268852837, flag = true),
            (n = 870, kind = :transfer, i = 5293, j = 4998, k = 1895, x = 0.489486926084301, y = 0.060590208988375194, flag = false),
            (n = 1087, kind = :transfer, i = 8343, j = 8428, k = 4535, x = 0.36989489866333736, y = 0.02395058718928278, flag = true)]),
    ]
    for (seed,clock,p,recipe) in recipes
        with_scratch_db() do _
            eqv_generate(seed;recipe=recipe,clock=clock)
            for d in 0:2
                @test CHESSDatabase.reconstruct_location(p.loc,p.seq,eqv_time(p),p.max_cache;depth=d) isa Location
                @test isempty(eqv_check_point(p;only="reconstruct_location(depth=$d)"))
            end
        end
    end
end

# The first recipe above, at its point: a cache of the target well exactly at the slot before a transfer, and a source
# whose newest cache is older. reconstruct_contents threw a MethodError there; the stock must be the one a replay from the
# earliest caches gives, whatever caches the call may use.
@testset "equivalence: reconstruct_contents with a cache at the slot before a transfer" begin
    recipe1 = [
        (n = 316, kind = :transfer, i = 3821, j = 5407, k = 8027, x = 0.7120814260067496, y = 0.02221964433860557, flag = false),
        (n = 392, kind = :cache, i = 3234, j = 8891, k = 681, x = 0.9715930409513767, y = 0.7278129169399845, flag = false),
        (n = 564, kind = :transfer, i = 8163, j = 978, k = 6622, x = 0.7870249580900325, y = 0.38423396913829877, flag = false),
        (n = 723, kind = :transfer, i = 6665, j = 2143, k = 3233, x = 0.6008021060675547, y = 0.08145263447133844, flag = false)]
    recipe2 = [
        (n = 862, kind = :transfer, i = 8319, j = 9990, k = 7442, x = 0.011703510067311407, y = 0.8518725811529935, flag = false),
        (n = 866, kind = :cache, i = 8614, j = 3267, k = 8868, x = 0.4370251404644022, y = 0.11942053268852837, flag = true),
        (n = 870, kind = :transfer, i = 5293, j = 4998, k = 1895, x = 0.489486926084301, y = 0.060590208988375194, flag = false),
        (n = 1087, kind = :transfer, i = 8343, j = 8428, k = 4535, x = 0.36989489866333736, y = 0.02395058718928278, flag = true)]
    for (seed,clock,recipe,p) in ((401,:monotone,recipe1,EqvPoint(30,172,0,2432,1160.0378254879452,1795,false)),
                                  (402,:backward,recipe2,EqvPoint(185,86,152,1779,871.1436693162698,1651,false)))
      with_scratch_db() do _
        eqv_generate(seed;recipe=recipe,clock=clock)
        t = eqv_time(p)
        stocks = [eqv_stock_summary(CHESSCore.stock(CHESSDatabase.reconstruct_contents(30,p.seq,t,mc))) for mc in (0,p.max_cache,p.seq)]
        @test stocks[1] == stocks[2] == stocks[3]
        seed == 401 && @test !isempty(stocks[1])
        @test eqv_try(()->eqv_snapshot(CHESSDatabase.reconstruct_location(p.loc,p.seq,t,p.max_cache))) ==
              eqv_try(()->eqv_snapshot(Legacy.reconstruct_location(p.loc,p.seq,t,p.max_cache)))
        @test isempty(eqv_check_point(p))
      end
    end
end
