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
# Size: CHESS_EQUIV_SEEDS (default 12) seeds, starting at CHESS_EQUIV_SEED_START (default 1), of
# CHESS_EQUIV_OPS (default 250) operations and CHESS_EQUIV_POINTS (default 40) query points each. The
# nightly workflow (.github/workflows/equivalence-nightly.yml) runs 500 seeds of 3000 operations in shards.
# On a mismatch the failing seed, query point and a reduced recipe are printed.

using Random, Test

include("legacy_reconstruction.jl")
include("generate_ledger.jl")

const EQV_SEEDS = parse(Int,get(ENV,"CHESS_EQUIV_SEEDS","12"))
const EQV_SEED_START = parse(Int,get(ENV,"CHESS_EQUIV_SEED_START","1"))   # the nightly job splits the seeds over shards
const EQV_OPS = parse(Int,get(ENV,"CHESS_EQUIV_OPS","250"))
const EQV_POINTS = parse(Int,get(ENV,"CHESS_EQUIV_POINTS","40"))
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

function eqv_points(rng,w::EqvWorld,n)
    maxid = query_db("SELECT Max(ID) FROM Ledger")[1,1]
    maxseq = query_db("SELECT Max(SequenceID) FROM Ledger")[1,1]
    hot = eqv_hotspots()
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
        seq = clamp(seq,1,maxseq+2)
        push!(pts,EqvPoint(loc,loc2,rand(rng) < 0.5 ? 0 : rand(rng,0:seq),seq,tsec,rand(rng,0:seq),rand(rng) < 0.25))
    end
    return pts
end

# --------------------------------------------------------------------------------------- the comparisons

# (name, canon, call) where call(M, p) runs the function from module M (CHESSDatabase or Legacy) at point p
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
    ("get_transfer_ancestors",eqv_canon,(M,p)->M.get_transfer_ancestors([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("get_transfer_descendents",eqv_canon,(M,p)->M.get_transfer_descendents([p.loc,p.loc2],p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("transfers_touch",eqv_canon,(M,p)->M.transfers_touch(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
    ("transfers_touched_by",eqv_canon,(M,p)->M.transfers_touched_by(p.loc,p.start,p.seq,eqv_time(p);encumbrances=p.enc)),
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
function eqv_check_point(p::EqvPoint;end_to_end::Bool=true,only::Union{Nothing,String}=nothing)
    out = EqvMismatch[]
    for (name,canon,call) in EQV_FUNCTION_CHECKS
        isnothing(only) || name == only || continue
        new = eqv_try(()->call(CHESSDatabase,p)); old = eqv_try(()->call(Legacy,p))
        eqv_same(new,old;canon=canon) || push!(out,EqvMismatch(name,p))
    end
    if end_to_end
        for (name,call) in EQV_END_TO_END
            isnothing(only) || name == only || continue
            new = eqv_try(()->call(CHESSDatabase,p)); old = eqv_try(()->call(Legacy,p))
            eqv_same(new,old;canon=identity) || push!(out,EqvMismatch(name,p))
        end
    end
    return out
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
                    append!(mismatches,eqv_check_point(p;end_to_end=i % 2 == 1)) # the end-to-end functions on every other point
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
