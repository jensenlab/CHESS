# Seeded generator of small but busy CHESS ledgers, built with the real API (generate_location, upload,
# update(...; replace=, insert=), observe, cache, encumber), so every write also runs validation and cache
# repair. It is used by the equivalence tests (test_equivalence.jl) to compare the old reconstruction code
# with the current one on the same database.
#
# A ledger is described by a *recipe*: a list of operations drawn from the seed alone. Each operation names
# its targets by position in fixed pools (the n-th room, the n-th plate, ...) and carries its own random
# numbers, so removing one operation from the recipe changes nothing else. That is what lets a failing
# case be reduced (eqv_reduce): drop operations while the mismatch persists. An operation the database
# refuses (a locked plate that cannot move, an overfull well) is skipped and recorded as not executed.
#
# What it produces: a lab tree (rooms, incubators with shelves, plates, reservoir bottles, a plate reader),
# environment series, reads sharing a tick, transfers (chains and shared reservoirs, one hub), movements and
# removals, locks, activity, instrument settings, observations, caches, encumbrances, replace amendments
# (also of old slots) and mid-ledger inserts. Lots and discards are not part of this version of CHESS.
# Afterwards Ledger.Time (and the Time of cache rows) is rewritten to a synthetic clock, optionally with a
# step backward, so `time`-travel cut-offs can fall between any two revisions.

using Random

const EQV_CLOCK_ORIGIN = 1.7e9    # Ledger.Time of row ID 0 on the synthetic clock (seconds since 1970)

# kind => relative weight
const EQV_OP_WEIGHTS = [
    :setattr=>30, :envtick=>6, :move=>9, :remove=>3, :lock=>4, :activity=>4, :transfer=>20, :readtick=>9,
    :setting=>2, :observe=>5, :discard=>4, :lot=>2, :unparent=>2, :cache=>3, :replace=>8, :insert=>4, :encumber=>3,
]

"""
    eqv_recipe(seed, nops) -> Vector{NamedTuple}

The list of operations for `seed`. Every field is a plain number or symbol.
"""
function eqv_recipe(seed::Integer,nops::Integer)
    rng = Xoshiro(seed)
    kinds = first.(EQV_OP_WEIGHTS); weights = last.(EQV_OP_WEIGHTS)
    cum = cumsum(weights)
    pick() = kinds[searchsortedfirst(cum,rand(rng,1:cum[end]))]
    return [(; n=i, kind=pick(), i=rand(rng,1:10_000), j=rand(rng,1:10_000), k=rand(rng,1:10_000),
             x=rand(rng), y=rand(rng), flag=rand(rng) < 0.5) for i in 1:nops]
end

pick_from(pool,i) = pool[mod1(i,length(pool))]

mutable struct EqvWorld
    rooms::Vector{Location}; incubators::Vector{Location}; shelves::Vector{Location}; plates::Vector{Location}
    bottles::Vector{Location}; reader::Location
    reservoirs::Vector{Well}                    # wells of the bottles, the sources of transfers
    wells::Vector{Well}                         # plate wells
    balance::Dict{Int,Float64}                  # µL believed to be in a plate well
    sent::Dict{Int,Int}                         # transfers received per well
    protocol_id::Int
    log::Vector{Any}                            # (n, kind, ledger_id, detail) of every executed operation
    executed::Dict{Int,Int}                     # recipe number => ledger_id (first row)
    replaceable::Vector{Any}                    # single-operation entries that can be amended
    locations::Vector{Int}                      # every location id, in a fixed order, for picking query points
end

function eqv_setup(rng_seed::Integer)
    w = EqvWorld(Location[],Location[],Location[],Location[],Location[],generate_location(PlateReaderModelX,"eqv reader"),
        Well[],Well[],Dict{Int,Float64}(),Dict{Int,Int}(),0,Any[],Dict{Int,Int}(),Any[],Int[])
    lab = generate_location(Lab,"eqv lab")
    w.rooms = Location[generate_location(Room,"eqv room $i") for i in 1:3]
    w.incubators = Location[generate_location(Incubator,"eqv incubator $i") for i in 1:2]
    w.shelves = Location[generate_location(IncubatorShelf,"eqv shelf $i") for i in 1:4]
    w.plates = Location[generate_location(WP96,"eqv plate $i") for i in 1:2]
    w.bottles = Location[generate_location(Bottle1L,"eqv bottle $i") for i in 1:2]
    push!(w.bottles,generate_location(PabaBottle,"eqv paba"))
    for r in w.rooms; upload(move_into!,lab,r); end
    upload(move_into!,w.rooms[1],w.incubators[1]); upload(move_into!,w.rooms[2],w.incubators[2])
    for (i,s) in enumerate(w.shelves); upload(move_into!,w.incubators[mod1(i,2)],s,true); end
    upload(move_into!,w.rooms[3],w.reader)
    for p in w.plates; upload(move_into!,w.rooms[3],p); end
    for b in w.bottles; upload(move_into!,w.rooms[1],b); end
    w.reservoirs = Well[b[1,1] for b in w.bottles]
    deposit!(w.reservoirs[1],500u"mL"*rgt"water"); deposit!(w.reservoirs[2],500u"mL"*rgt"water"+2u"g"*rgt"iron_nitrate")
    deposit!(w.reservoirs[3],50u"g"*rgt"paba")
    for r in w.reservoirs; cache(r); end
    w.wells = Well[x for p in w.plates for x in children(p)]
    upload(set_attribute!,lab,Temperature(25u"°C"))
    exp_id = upload_experiment("eqv experiment $rng_seed","eqv")
    w.protocol_id = upload_protocol(exp_id,"eqv protocol")
    w.locations = vcat(location_id.(w.rooms),location_id.(w.incubators),location_id.(w.shelves),location_id.(w.plates),
        location_id.(w.bottles),location_id(lab),location_id(w.reader),location_id.(w.reservoirs),location_id.(w.wells[1:min(end,30)]))
    return w
end

_eqv_temp(x) = (10 + round(30x;digits=1))*u"°C"
_eqv_loc_pool(w) = vcat(w.rooms,w.incubators,w.shelves,w.plates)

# Run one recipe operation. Returns the ledger id of the (first) entry written, or nothing when the
# database refused it.
function eqv_run_op!(w::EqvWorld,op)
    k = op.kind
    if k === :setattr
        loc = pick_from(_eqv_loc_pool(w),op.i)
        attr = op.flag ? Temperature(op.y < 0.12 ? missing : _eqv_temp(op.x)) : Humidity((20 + round(60op.x;digits=1))*u"percent")
        lid = upload(set_attribute!,loc,attr)
        push!(w.replaceable,(; op.n,kind=:setattr,lid,loc=location_id(loc),attrkind=op.flag ? :Temperature : :Humidity))
        return lid
    elseif k === :envtick       # several samples sharing one tick: distinct (location, attribute)
        lid = append_ledger()
        pool = vcat(w.rooms,w.incubators,w.shelves)
        n = 2 + op.i % 3
        for t in 0:n-1
            loc = pick_from(pool,op.j+t)
            upload(set_attribute!,loc,Temperature(_eqv_temp(mod(op.x+0.13t,1.0)));ledger_id=lid)
        end
        return lid
    elseif k === :move
        plate = pick_from(w.plates,op.i)
        target = pick_from(vcat(w.rooms,w.shelves,w.incubators[1:0]),op.j)
        return upload(move_into!,target,plate)
    elseif k === :remove        # a plate taken out of the lab: an observation of "no parent"
        plate = pick_from(w.plates,op.i)
        isnothing(CHESSCore.parent(plate)) && return nothing
        return observe(plate,nothing)
    elseif k === :lock
        plate = pick_from(w.plates,op.i)
        lid = upload(op.flag ? lock! : unlock!,plate)
        push!(w.replaceable,(; op.n,kind=:lock,lid,loc=location_id(plate)))
        return lid
    elseif k === :activity
        loc = pick_from(_eqv_loc_pool(w),op.i)
        lid = upload(op.flag ? activate! : deactivate!,loc)
        push!(w.replaceable,(; op.n,kind=:activity,lid,loc=location_id(loc)))
        return lid
    elseif k === :transfer
        dest = pick_from(w.wells,op.j)
        did = location_id(dest)
        get(w.sent,did,0) >= 25 && return nothing
        # shared reservoirs: reservoir 1 is the hub (most use), 2 and 3 are used less
        src = if op.y < 0.55 && get(w.balance,did,0.0) >= 0 && op.flag
            # a chain: take from a plate well that already holds something
            holders = [x for x in w.wells if get(w.balance,location_id(x),0.0) >= 8.0 && location_id(x) != did]
            isempty(holders) ? w.reservoirs[1] : pick_from(holders,op.k)
        else
            w.reservoirs[op.x < 0.6 ? 1 : (op.x < 0.9 ? 2 : 3)]
        end
        isa_res = src in w.reservoirs
        solid = isa_res && src === w.reservoirs[3]
        q = solid ? (0.01 + round(0.05op.x;digits=3))*u"g" : (isa_res ? (0.5 + round(2op.x;digits=2)) : 0.4)*u"µL"
        solid && return nothing         # paba is a solid: only the bottle itself could receive it; skip
        lid = upload(transfer!,src,dest,q)
        amt = Float64(ustrip(q))
        w.balance[did] = get(w.balance,did,0.0) + amt
        isa_res || (w.balance[location_id(src)] = get(w.balance,location_id(src),0.0) - amt)
        w.sent[did] = get(w.sent,did,0) + 1
        push!(w.replaceable,(; op.n,kind=:transfer,lid,src=location_id(src),dest=did,q=amt))
        return lid
    elseif k === :readtick      # several reads on one tick: the wells of a plate
        lid = append_ledger()
        plate = pick_from(w.plates,op.i)
        n = 3 + op.j % 6
        t0 = Dates.DateTime(2026,1,1) + Dates.Minute(op.k)
        for (c,x) in enumerate(children(plate)[1:n])
            rd = op.flag ? Absorbance((10+round(80mod(op.x+0.07c,1.0);digits=1))*u"percent",t0+Dates.Second(c)) :
                           ColorimetricResult(op.y < 0.5 ? "Positive" : "Negative")
            upload(record_read!,x,rd;ledger_id=lid,instrument=w.reader)
        end
        return lid
    elseif k === :setting
        return upload_instrument_setting(w.reader,op.flag ? "Gain" : "Filter",op.flag ? round(1+3op.x;digits=2) : "F$(op.i % 4)")
    elseif k === :observe
        form = op.i % 5
        if form == 0
            return observe(pick_from(w.bottles,op.j),Lot("EQV Supplier","EQV-1","LOT$(op.k % 4)"))
        elseif form == 1
            return observe(pick_from(vcat(w.rooms,w.shelves),op.j),Temperature(_eqv_temp(op.x)))
        elseif form == 2
            return observe(pick_from(w.plates,op.j),:locked,op.flag)
        elseif form == 3
            return observe(pick_from(w.plates,op.j);recursive=false)
        else
            return observe(pick_from(w.wells,op.j),rgt"water",round(5op.x;digits=2)*u"µL")
        end
    elseif k === :lot
        return observe(pick_from(vcat(w.bottles,w.plates),op.j),Lot("EQV Supplier","EQV-$(op.i % 2)","LOT$(op.k % 4)";received=Dates.Date(2026,1,1)+Dates.Day(op.i % 50)))
    elseif k === :discard
        holders = [x for x in w.wells if get(w.balance,location_id(x),0.0) >= 1.0]
        isempty(holders) && return nothing
        src = pick_from(holders,op.j)
        lid = upload(discard!,src,0.2u"µL")
        w.balance[location_id(src)] -= 0.2
        push!(w.replaceable,(; op.n,kind=:discard,lid,src=location_id(src)))
        return lid
    elseif k === :unparent
        plate = pick_from(w.plates,op.i)
        isnothing(CHESSCore.parent(plate)) && return nothing
        return upload(remove_from_parent!,plate)
    elseif k === :cache
        # cache what the database says now (not the in-memory object, which may lag after amendments)
        target = pick_from(vcat(w.wells,w.plates,w.rooms,w.shelves),op.i)
        cache(reconstruct_location(location_id(target)))
        return get_last_ledger_id()
    elseif k === :replace
        isempty(w.replaceable) && return nothing
        r = pick_from(w.replaceable,op.i)
        slot = get_sequence_id(r.lid)
        if r.kind === :setattr
            loc = reconstruct_location(r.loc)
            attr = r.attrkind === :Temperature ? Temperature(_eqv_temp(op.x)) : Humidity((20 + round(60op.x;digits=1))*u"percent")
            return update(set_attribute!,loc,attr;replace=slot)
        elseif r.kind === :lock
            return update(op.flag ? lock! : unlock!,reconstruct_location(r.loc);replace=slot)
        elseif r.kind === :activity
            return update(op.flag ? activate! : deactivate!,reconstruct_location(r.loc);replace=slot)
        elseif r.kind === :discard
            return update(discard!,reconstruct_location(r.src),0.2u"µL"*(0.9+0.2op.x);replace=slot)
        else
            src,dest = reconstruct_location(r.src),reconstruct_location(r.dest)
            return update(transfer!,src,dest,r.q*(0.9+0.2op.x)*u"µL";replace=slot)
        end
    elseif k === :insert
        last_seq = get_last_sequence_id()
        slot = 2 + op.i % max(1,last_seq-1)
        loc = reconstruct_location(location_id(pick_from(_eqv_loc_pool(w),op.j)))
        if op.flag
            return update(set_attribute!,loc,Temperature(_eqv_temp(op.x));insert=slot)
        else
            return update(op.y < 0.5 ? activate! : deactivate!,loc;insert=slot)
        end
    elseif k === :encumber
        form = op.i % 4
        pid = w.protocol_id
        if form == 0
            plate = reconstruct_location(location_id(pick_from(w.plates,op.j)))
            return encumber(pid,move_into!,reconstruct_location(location_id(pick_from(w.shelves,op.k))),plate)
        elseif form == 1
            dest = reconstruct_location(location_id(pick_from(w.wells,op.j)))
            return encumber(pid,transfer!,reconstruct_location(location_id(w.reservoirs[1])),dest,0.5u"µL")
        elseif form == 2
            return encumber(pid,set_attribute!,reconstruct_location(location_id(pick_from(w.rooms,op.j))),Humidity((30+round(30op.x;digits=1))*u"percent"))
        else
            return encumber(pid,toggle_activity!,reconstruct_location(location_id(pick_from(w.plates,op.j))))
        end
    end
    error("unknown recipe operation $k")
end

"""
    eqv_build(seed, recipe) -> EqvWorld

Create the world and run `recipe` (a vector from [`eqv_recipe`](@ref), or a subset of one) against the
connected database. Operations the database refuses are skipped.
"""
function eqv_build(seed::Integer,recipe)
    w = eqv_setup(seed)
    for op in recipe
        lid = try
            eqv_run_op!(w,op)
        catch err
            err isa InterruptException && rethrow()
            nothing
        end
        isnothing(lid) || (w.executed[op.n] = lid; push!(w.log,(op.n,op.kind,lid)))
    end
    return w
end

"""
    eqv_synthetic_clock!(; back_after=nothing, back_by=0)

Rewrite `Ledger.Time` to `EQV_CLOCK_ORIGIN + ID` seconds (so time order equals write order), and give every
cache row the time of its ledger row. With `back_after=k` and `back_by=d`, every row after ID `k` is
written `d` seconds earlier than that, a clock that stepped backward.
"""
function eqv_synthetic_clock!(;back_after::Union{Nothing,Integer}=nothing,back_by::Real=0)
    execute_db("UPDATE Ledger SET Time = ? + ID",(EQV_CLOCK_ORIGIN,))
    if !isnothing(back_after)
        execute_db("UPDATE Ledger SET Time = Time - ? WHERE ID > ?",(Float64(back_by),back_after))
    end
    for tbl in ("CachedContents","CachedAncestors","CachedDescendants","CachedEnvironments","CachedLockActivity")
        execute_db("UPDATE $tbl SET Time = (SELECT Time FROM Ledger WHERE Ledger.ID = $tbl.LedgerID)")
    end
    return nothing
end

eqv_clock_time(seconds_after_origin::Real) = Dates.unix2datetime(EQV_CLOCK_ORIGIN + seconds_after_origin)

"""
    eqv_generate(seed; nops=250, clock=:monotone) -> EqvWorld

Build the ledger for `seed` in the connected database and rewrite its clock. `clock` is `:monotone` or
`:backward` (a step back of a fifth of the ledger's length, a third of the way through).
"""
function eqv_generate(seed::Integer;nops::Integer=250,clock::Symbol=:monotone,recipe=eqv_recipe(seed,nops))
    w = eqv_build(seed,recipe)
    n = query_db("SELECT Max(ID) FROM Ledger")[1,1]
    if clock === :backward
        eqv_synthetic_clock!(back_after=n÷3,back_by=max(2,n÷5))
    else
        eqv_synthetic_clock!()
    end
    return w
end
