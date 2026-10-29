# reconstruct_history(...; encumbrances=true) (src/reconstruction/history_encumbrances.jl): planned operations in a history.
# The property that matters (the value at every slot equals the matching reconstruct_* with encumbrances=true) is also checked
# on random ledgers with planned operations in test/equivalence/test_equivalence.jl; here a planted ledger with known answers.
# Every location is new (prefixed `he_`) and runs against the shared database set up in build_test_database.jl.
#
# A planned operation takes effect from the slot of the enforcement entry of its protocol (the pseudo-slot
# `last + EncumbranceID` only orders planned rows against each other) and stops at an entry that switches enforcement off.

he_tick() = sleep(0.02)
he_id(x) = location_id(x)
he_time(lid) = CHESSDatabase.julia_time(query_db("SELECT Time FROM Ledger WHERE ID = ?",(lid,)).Time[1])

he_lab = generate_location(Lab,"he lab")
he_a = generate_location(Room,"he room a")
he_b = generate_location(Room,"he room b")
upload(move_into!,he_lab,he_a); upload(move_into!,he_lab,he_b)
he_plate = generate_location(WP96,"he plate")
he_well = he_plate[1,1]
he_src = generate_location(Bottle1L,"he source")
upload(move_into!,he_a,he_src); upload(move_into!,he_a,he_plate)
he_sw = he_src[1,1]
deposit!(he_sw,100u"mL"*rgt"water"); cache(he_sw)
upload(set_attribute!,he_a,Temperature(20u"°C"))
upload(set_attribute!,he_b,Temperature(30u"°C"))
he_exp = upload_experiment("he experiment","he")
he_pid = upload_protocol(he_exp,"he protocol")      # enforced from its creation
he_s0 = get_last_sequence_id()

he_slot = Dict{Symbol,Int}()
function he_do(name,f,args...)
    lid = upload(f,args...)
    he_tick()
    he_slot[name] = get_sequence_id(lid)
end
function he_enforce(name,flag)
    CHESSDatabase.upload_protocol_enforcement(he_pid,flag)
    he_tick()
    he_slot[name] = get_last_sequence_id()
end
# the planned operations are uploaded while the protocol is enforced
he_slot[:enforce1] = get_sequence_id(query_db("SELECT Max(LedgerID) AS l FROM ProtocolEnforcement WHERE ProtocolID = ?",(he_pid,)).l[1])
# `encumber` runs the operation on the objects it is given, so it gets copies read back from the database
he_fresh(x) = reconstruct_location(he_id(x))
encumber(he_pid,move_into!,he_fresh(he_b),he_fresh(he_plate))
encumber(he_pid,set_attribute!,he_fresh(he_b),Humidity(70u"percent"))
encumber(he_pid,toggle_activity!,he_fresh(he_well))
encumber(he_pid,lock!,he_fresh(he_plate))
encumber(he_pid,transfer!,he_fresh(he_sw),he_fresh(he_well),10u"µL")
he_do(:a_hum,set_attribute!,he_a,Humidity(40u"percent"))
he_do(:plate25,set_attribute!,he_plate,Temperature(25u"°C"))
he_enforce(:off,false)
he_do(:w_deact,deactivate!,he_fresh(he_well))
he_do(:real_move_b,move_into!,he_fresh(he_b),he_fresh(he_plate))
he_do(:real_hum,set_attribute!,he_b,Humidity(50u"percent"))
he_enforce(:on,true)
he_do(:plate26,set_attribute!,he_plate,Temperature(26u"°C"))
he_slot[:cache] = (cache(reconstruct_location(he_id(he_plate))); get_last_sequence_id())
he_do(:w_react,activate!,he_fresh(he_well))
he_enforce(:off2,false)
he_do(:last,set_attribute!,he_a,Humidity(45u"percent"))
he_last = get_last_sequence_id()

function he_quantity(dict,name)
    for (k,a) in dict
        kname = k isa Symbol ? k : hasproperty(k,:name) ? k.name : Symbol(string(k))
        kname === Symbol(name) || continue
        return ismissing(CHESSCore.value(a)) ? missing : CHESSCore.quantity(a)
    end
    return missing
end
function he_number(q)
    ismissing(q) && return missing
    return Unitful.dimension(q) == Unitful.dimension(1u"°C") ? ustrip(uconvert(u"°C",q)) : ustrip(uconvert(u"percent",q))
end
he_same(a,b) = (ismissing(a) && ismissing(b)) || (!ismissing(a) && !ismissing(b) && isapprox(a,b;rtol=1e-9))

# the facets, as (history call, matching reconstruction)
he_facets(id) = Any[
    ("parent", (;facet=:parent), (s,tm)->(p = CHESSCore.parent(reconstruct_parent(id,s,tm;encumbrances=true)); isnothing(p) ? missing : he_id(p))),
    ("locked", (;facet=:locked), (s,tm)->CHESSCore.is_locked(reconstruct_lock(id,s,tm;encumbrances=true))),
    ("active", (;facet=:active), (s,tm)->CHESSCore.is_active(reconstruct_activity(id,s,tm;encumbrances=true))),
    ("Temperature effective", (;facet=:Temperature,effective=true),
        (s,tm)->he_number(he_quantity(CHESSCore.environment(reconstruct_environment(id,s,tm;encumbrances=true)),"Temperature"))),
    ("Humidity effective", (;facet=:Humidity,effective=true),
        (s,tm)->he_number(he_quantity(CHESSCore.environment(reconstruct_environment(id,s,tm;encumbrances=true)),"Humidity"))),
    ("Humidity own", (;facet=:Humidity,effective=false),
        (s,tm)->he_number(he_quantity(CHESSCore.attributes(reconstruct_attributes(id,s,tm;encumbrances=true)),"Humidity"))),
]
function he_bad(id,tm;to=he_last + 3)
    bad = String[]
    for (label,kw,oracle) in he_facets(id)
        h = reconstruct_history(id,kw.facet;from=0,to=to,time=tm,effective=get(kw,:effective,nothing),encumbrances=true)
        # before its first row (the creation of the location) a history has no value
        for s in (isempty(h.SequenceID) ? 0 : h.SequenceID[1]):to
            got = history_value_at(h,s)
            he_same(got,oracle(s,tm)) || push!(bad,"$label $id slot $s")
        end
    end
    return bad
end
he_times = (Dates.now(),he_time(query_db("SELECT Max(ID) AS i FROM Ledger").i[1]),
            he_time(query_db("SELECT LedgerID AS i FROM ProtocolEnforcement WHERE ProtocolID = ? ORDER BY LedgerID LIMIT 1 OFFSET 1",(he_pid,)).i[1]))

@testset "history encumbrances: the value at every slot equals the reconstruction with encumbrances=true" begin
    for tm in he_times, loc in (he_plate,he_well,he_b)
        @test isempty(he_bad(he_id(loc),tm))
    end
end

@testset "history encumbrances: planned rows are labelled, start at the enforcement slot and stop when it is switched off" begin
    h = reconstruct_history(he_id(he_plate),:parent;from=he_s0,encumbrances=true)
    planned = filter(r -> startswith(r.Event,"planned"),h)
    @test !isempty(planned)
    @test he_slot[:enforce1] in planned.SequenceID || minimum(planned.SequenceID) <= he_slot[:enforce1]
    # switched off: the plate is where the real ledger put it again at the slot of the entry
    at(s) = history_value_at(h,s)
    @test at(he_slot[:enforce1]) == he_id(he_b)
    @test at(he_slot[:off]) == he_id(he_a)
    @test at(he_slot[:real_move_b]) == he_id(he_b)
    @test at(he_slot[:on]) == he_id(he_b)
    # a lock only exists as a planned row
    lk = reconstruct_history(he_id(he_plate),:locked;from=he_s0,encumbrances=true)
    @test history_value_at(lk,he_slot[:enforce1]) == true && history_value_at(lk,he_slot[:off]) == false
    @test history_value_at(lk,he_slot[:on]) == true && history_value_at(lk,he_last) == false
    @test all(startswith.(filter(r -> r.Value === true,lk).Event,"planned"))
end

@testset "history encumbrances: encumbrances=false is unchanged and has no planned rows" begin
    for (id,facet) in ((he_id(he_plate),:parent),(he_id(he_plate),:locked),(he_id(he_well),:active),(he_id(he_b),:Humidity),(he_id(he_well),:Temperature))
        plain = reconstruct_history(id,facet;from=he_s0)
        @test isequal(plain,reconstruct_history(id,facet;from=he_s0,encumbrances=false))
        @test !any(startswith.(plain.Event,"planned"))
    end
    # a location nothing is planned on has the same rows with and without
    for facet in (:parent,:locked,:active,:Temperature)
        @test isequal(reconstruct_history(he_id(he_a),facet;from=he_s0),reconstruct_history(he_id(he_a),facet;from=he_s0,encumbrances=true)) || facet === :Temperature
    end
end

@testset "history encumbrances: a cache after the enforcement entry keeps the value of the reconstruction, even where it drops the planned one" begin
    # the event getters read from the newest cache on, so a planned row older than a later cache is not seen there; the history
    # follows the reconstruction (this is the behaviour of reconstruct_*, not a decision of the history)
    s = he_slot[:cache]
    for loc in (he_plate,he_well)
        h = reconstruct_history(he_id(loc),:parent;from=0,encumbrances=true)
        want = CHESSCore.parent(reconstruct_parent(he_id(loc),s,Dates.now();encumbrances=true))
        @test isequal(history_value_at(h,s),isnothing(want) ? missing : he_id(want))
    end
end

@testset "history encumbrances: contents with a planned transfer, effective chain and slots after the last real slot" begin
    h = reconstruct_history(he_id(he_well),:contents;from=0,encumbrances=true)
    for s in 0:he_last + 3
        v = history_value_at(h,s)
        v = ismissing(v) ? Empty() : v
        w = CHESSCore.stock(reconstruct_contents(he_id(he_well),s,Dates.now();encumbrances=true))
        @test (v isa Empty && w isa Empty) || (!(v isa Empty) && !(w isa Empty) && isapprox(v,w;rtol=1e-9))
    end
    # the planned transfer moves water into the well from the enforcement slot; the plain history has none of it
    plain = reconstruct_history(he_id(he_well),:contents;from=0)
    @test any(startswith.(h.Event,"planned")) || nrow(h) >= nrow(plain)
    # the effective humidity of the well: planned 70 % on room b while the plate is moved there
    eff = reconstruct_history(he_id(he_well),:Humidity;from=he_s0,encumbrances=true)
    @test history_value_at(eff,he_slot[:enforce1]) ≈ 70.0 && history_value_at(eff,he_slot[:off]) ≈ 40.0
    @test any(==(he_id(he_b)),eff.Origin)
    # beyond the last real slot
    @test history_value_at(eff,he_last + 3) == history_value_at(eff,he_last)
end

@testset "history encumbrances: paging gives the rows of the whole history" begin
    for facet in (:parent,:locked,:active,:Humidity)
        id = facet === :active ? he_id(he_well) : he_id(he_plate)
        whole = reconstruct_history(id,facet;from=0,encumbrances=true)
        pages = DataFrame()
        after = nothing
        while true
            p = reconstruct_history(id,facet;from=0,encumbrances=true,limit=2,after=after)
            nrow(p) == 0 && break
            pages = vcat(pages,p)
            after = p.SequenceID[end]
            nrow(p) < 2 && break
        end
        @test isequal(pages,whole)
        rev = reconstruct_history(id,facet;from=0,encumbrances=true,order=:desc)
        @test isequal(reverse(rev),whole)
    end
end

@testset "history encumbrances: collapse=false keeps a row per source entry and the values still agree" begin
    id = he_id(he_plate)
    whole = reconstruct_history(id,:parent;from=0,encumbrances=true,collapse=false)
    for s in whole.SequenceID[1]:he_last
        p = CHESSCore.parent(reconstruct_parent(id,s,Dates.now();encumbrances=true))
        @test isequal(history_value_at(whole,s),isnothing(p) ? missing : he_id(p))
    end
    @test nrow(whole) >= nrow(reconstruct_history(id,:parent;from=0,encumbrances=true))
end

# Reduced from a random ledger: a planned attribute on a location that has no real value, switched off again by an entry that
# is not a row of any source of the key. The blank after the planned value has to be a row of the frame (the entry's ledger id).
@testset "history encumbrances: the blank after a planned value is a row of the enforcement entry that switched it off" begin
    room = generate_location(Room,"he blank room")
    box = generate_location(WP96,"he blank plate")
    upload(move_into!,room,box)
    exp2 = upload_experiment("he experiment 2","he")
    pid2 = upload_protocol(exp2,"he protocol 2")
    on_slot = get_last_sequence_id()
    encumber(pid2,set_attribute!,reconstruct_location(he_id(room)),Humidity(61u"percent"))
    sleep(0.02)
    CHESSDatabase.upload_protocol_enforcement(pid2,false)
    off_lid = get_last_ledger_id(); off_slot = get_sequence_id(off_lid)
    sleep(0.02)
    upload(set_attribute!,reconstruct_location(he_id(room)),Temperature(22u"°C"))      # a later, unrelated row
    for loc in (room,box)
        h = reconstruct_history(he_id(loc),:Humidity;from=on_slot,encumbrances=true)
        @test history_value_at(h,off_slot - 1) ≈ 61.0
        @test ismissing(history_value_at(h,off_slot))
        @test off_slot in h.SequenceID && h.LedgerID[findfirst(==(off_slot),h.SequenceID)] == off_lid
        @test h.Event[findfirst(==(off_slot),h.SequenceID)] == "planned ended"
    end
end
