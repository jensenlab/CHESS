using CHESSCore, CHESSDatabase, Test, Unitful, UUIDs, SQLite, DataFrames, Dates

@testset "db_utils: not-connected error stubs" begin
    # the only point in this process where connect_SQLite hasn't run yet -- once it does (via
    # build_test_database.jl below), _current_db[] is set and these calls succeed instead.
    @test_throws ErrorException CHESSDatabase.execute_db("SELECT 1")
    @test_throws ErrorException CHESSDatabase.query_db("SELECT 1")
    @test_throws ErrorException CHESSDatabase.execute_db("SELECT 1",())
    @test_throws ErrorException CHESSDatabase.query_db("SELECT 1",())
    @test_throws ErrorException CHESSDatabase.sql_transaction(()->nothing)
    @test_throws ErrorException CHESSDatabase.sql_commit("x")
    @test_throws ErrorException CHESSDatabase.sql_rollback("x")
end

println("building sample database...")

include("build_test_database.jl")

println("sample database complete.")

println("testing cache repair tools...")

include("test_cache_repair.jl")
println("cache repair complete")

# Fixtures used by testsets below that originally relied on core_runtests.jl's script-level bindings
# (b = a Mixture stock; Cl⁻ = a test-local dissociation Chemical) -- now that CHESSCore and
# CHESSDatabase are separate packages with independent test processes, these need their own copy here.
b=10u"g"*rgt"paba" # mixture
const Cl⁻=CHESSCore.Chemical("Cl-",-1,35.45u"g/mol")

@testset "upload() rejects uncommitted locations without a phantom ledger row" begin
    # upload's `ledger_id` default (append_ledger()) used to be evaluated before the commit check,
    # so append_ledger()'s ledger write already happened by the time UncommittedLocationError fired --
    # confirm no ledger row is left behind now that the check runs first.
    before = get_last_sequence_id()
    @test_throws UncommittedLocationError upload(set_attribute!,build_location(Room,"eph upload test"),Temperature(1u"°C"))
    @test get_last_sequence_id() == before
    # cache()'s commit check runs before its DB-touching default argument is resolved, so this
    # throws UncommittedLocationError -- not a raw "use connect_SQLite" error.
    @test_throws UncommittedLocationError cache(build_location(WP96,"eph cache test"))
end

@testset "commit_location! / release_location" begin
    eph_root = build_location(Room,"merge test room")
    eph_plate = build_location(WP96,"merge test plate")
    move_into!(eph_root,eph_plate)
    set_attribute!(eph_root,Temperature(19u"°C"))
    lock!(eph_plate)
    deposit!(eph_plate[1,1],0.1u"g"*rgt"paba",5)

    committed = commit_location!(eph_root)
    @test CHESSCore.is_committed(committed)
    @test !CHESSCore.is_committed(eph_root) # the original uncommitted tree is left untouched
    @test environment(committed)[:Temperature] == Temperature(19u"°C")

    committed_plate = children(committed)[1]
    @test is_locked(committed_plate)
    @test stock(committed_plate[1,1]) == stock(eph_plate[1,1])

    # reconstruct_children! deliberately builds shallow child references (see its docstring), so
    # compare root-level identity/environment rather than a full recursive softequal against the
    # committed tree's deeply-populated children
    preview = reconstruct_location(location_id(committed))
    @test location_id(preview) == location_id(committed)
    @test CHESSCore.kind(preview) === CHESSCore.kind(committed)
    @test environment(preview)[:Temperature] == environment(committed)[:Temperature]
    @test location_id(children(preview)[1]) == location_id(committed_plate)

    # release_location is the inverse: strips real IDs back out, no database calls
    released = release_location(committed)
    @test !CHESSCore.is_committed(released)
    @test CHESSCore.softequal(released,eph_root)

    # merge scenario: two independently-built uncommitted pieces, combined under a fresh root, then
    # committed together into the (same, for this test) database with fresh non-colliding IDs
    piece1 = release_location(commit_location!(build_location(WP96,"merge piece 1")))
    piece2 = release_location(commit_location!(build_location(WP96,"merge piece 2")))
    merged_root = build_location(Room,"merged room")
    move_into!(merged_root,piece1)
    move_into!(merged_root,piece2)
    committed_merge = commit_location!(merged_root)
    committed_children_ids = location_id.(children(committed_merge))
    @test length(unique(committed_children_ids)) == 2
    @test all(!isnothing,committed_children_ids)
end

@testset "Non-mutating variants removed; reconstruct_location previews correctly" begin
    # `toggle_lock`/`activate`/`deactivate`/`toggle_activity`/`sterilize`/`drain`/`transfer` don't
    # collide with any Base name, so a plain isdefined check is unambiguous for them.
    @test !isdefined(CHESSCore,:toggle_lock)
    @test !isdefined(CHESSCore,:activate) && !isdefined(CHESSCore,:deactivate) && !isdefined(CHESSCore,:toggle_activity)
    @test !isdefined(CHESSCore,:sterilize) && !isdefined(CHESSCore,:drain) && !isdefined(CHESSCore,:transfer)
    @test !isdefined(CHESSCore,:move_into)
    @test !isdefined(CHESSCore,:set_attribute)
    # `lock`/`unlock`/`empty` collide with real Base names (threading locks, collections), so check the
    # specific removed method instead of the bare name.
    @test !hasmethod(Base.lock,Tuple{CHESSCore.Location})
    @test !hasmethod(Base.unlock,Tuple{CHESSCore.Location})
    @test !hasmethod(Base.empty,Tuple{CHESSCore.Well})
    # the ! forms must still exist
    @test isdefined(CHESSCore,:lock!) && isdefined(CHESSCore,:sterilize!) && isdefined(CHESSCore,:drain!) && isdefined(CHESSCore,:transfer!)

    # documented preview pattern: reconstruct_location gives an independent copy; mutating it never
    # touches the real, live object
    real_well = children(plate1)[1,1]
    preview = reconstruct_location(location_id(real_well))
    original_stock = stock(real_well)
    drain!(preview)
    @test stock(real_well) == original_stock # untouched by mutating the reconstructed copy
end

@testset "DataFrame interop" begin
    # reagent_to_string / string_to_reagent round-trip a registered reagent by symbol, not name
    @test reagent_to_string(rgt"water";reagent_context=[CHESSCore,TestChemOrg]) == "water"
    @test string_to_reagent("water",u"percent";reagent_context=[CHESSCore,TestChemOrg]) == rgt"water"

    # concentration(::Stock,::Solid) is now relative to quantity(stock) (a mass for Mixture), via
    # _relative_amount -- same-dimension (mass/mass here) means percent, not a density-style ratio
    conc = concentration(b,rgt"paba") # b = 10u"g"*rgt"paba", a pure-paba Mixture
    @test conc ≈ 100u"percent"

    # labware_to_df / df_to_labware round-trip, "q" format
    bottle = generate_location(Bottle1L,"df interop test bottle")
    deposit!(bottle.children[1,1],10u"g"*rgt"paba",5)
    df_q,units_q = labware_to_df(bottle,"q";reagent_context=[CHESSCore,TestChemOrg])
    @test df_q.labware[1] == string(kind(bottle).name) # kind-based, not typeof(lw)
    lws_q = df_to_labware(df_q,units_q;reagent_context=[CHESSCore,TestChemOrg])
    @test kind(lws_q[1]) == kind(bottle)
    @test stock(lws_q[1][df_q.well[1]]) == stock(bottle.children[1,1])

    # "vc" format round-trip on a Solution-derived stock (fits vc's volume/concentration model)
    bottle2 = generate_location(Bottle1L,"df interop test bottle vc")
    deposit!(bottle2.children[1,1],100u"mL"*rgt"water",5)
    df_vc,units_vc = labware_to_df(bottle2,"vc";reagent_context=[CHESSCore,TestChemOrg])
    lws_vc = df_to_labware(df_vc,units_vc;reagent_context=[CHESSCore,TestChemOrg])
    @test stock(lws_vc[1][df_vc.well[1]]) == stock(bottle2.children[1,1])

    # "vc" format now also works on a Mixture-derived stock -- previously crashed (MethodError) since
    # the exported concentration unit was always g/µL regardless of the total's dimension
    bottle3 = generate_location(Bottle1L,"df interop test bottle vc mixture")
    deposit!(bottle3.children[1,1],10u"g"*rgt"paba",5)
    df_vc3,units_vc3 = labware_to_df(bottle3,"vc";reagent_context=[CHESSCore,TestChemOrg])
    @test units_vc3[1,"paba"] == "%"
    lws_vc3 = df_to_labware(df_vc3,units_vc3;reagent_context=[CHESSCore,TestChemOrg])
    @test stock(lws_vc3[1][df_vc3.well[1]]) == stock(bottle3.children[1,1])

    # volume_estimate(::Mixture): a solid with unknown density no longer poisons the whole estimate
    # to 0 -- it's excluded, and a warning is emitted, but known-density solids still contribute
    mix = 10u"g"*rgt"paba" + 5u"g"*rgt"iron_nitrate" # paba has known density, iron_nitrate doesn't
    @test_logs (:warn,r"density unknown") volume_estimate(mix)
    vol = volume_estimate(mix)
    @test vol > 0u"mL"
    @test vol ≈ uconvert(u"mL",10u"g"/density(rgt"paba"))

    # vc_to_stock gives a clear error (not a deep MethodError) for a dimensionally-mismatched
    # hand-authored concentration unit (a density-style unit against a mass-typed total)
    vc_bad = DataFrame(volume=[10.0],paba=[1.0])
    units_bad = DataFrame(volume=["g"],paba=["g/µL"])
    @test_throws ErrorException vc_to_stock(vc_bad,units_bad;reagent_context=[CHESSCore,TestChemOrg])
end

@testset "Separate Chemical/Reagent DB registries" begin
    # bug fix: Reagents is keyed by ComponentID now, not Name -- a Solid and a Liquid sharing a name
    # (distinct Reagent values per value-based equality) each get their own persisted row
    s1 = Solid("dbtest",137.14u"g/mol",1.35u"g/mL",978)
    l1 = Liquid("dbtest",200.0u"g/mol",0.9u"g/mL",111)
    id_s1 = CHESSDatabase.upload_component(s1)
    id_l1 = CHESSDatabase.upload_component(l1)
    rows = query_db("SELECT * FROM Reagents WHERE Name='dbtest' ORDER BY ComponentID")
    @test nrow(rows) == 2
    @test rows[1,:MolecularWeight] == 137.14 && rows[1,:Density] == 1.35
    @test rows[2,:MolecularWeight] == 200.0 && rows[2,:Density] == 0.9

    # composition round-trips through the new Chemicals/CompositionRules tables
    hcl_db = Solid("hcl_dbtest",36.46u"g/mol",1.0u"g/mL",missing)
    set_composition!(hcl_db,CompositionRule(Dict(H⁺=>1,Cl⁻=>1)))
    id_hcl = CHESSDatabase.upload_component(hcl_db)
    comp_rows = query_db("""
        SELECT c.Name, c.Charge, c.MolecularWeight, r.Coefficient
        FROM CompositionRules r INNER JOIN Chemicals c ON r.ChemicalID = c.ID
        WHERE r.ReagentComponentID = $id_hcl
    """)
    @test nrow(comp_rows) == 2
    fetched = Dict(CHESSCore.Chemical(row.Name,row.Charge,row.MolecularWeight*u"g/mol") => row.Coefficient for row in eachrow(comp_rows))
    @test fetched == composition_rules[hcl_db].products

    # get_component restores the dissociation rule -- reconstructed reagent behaves identically
    reconstructed = CHESSDatabase.get_component(id_hcl)
    @test molecular_weight(reconstructed) == molecular_weight(hcl_db)
    @test composition(reconstructed).products == composition(hcl_db).products
end

@testset "DB round-trip equivalence, natural-key dedup, SQL escaping, hash precision" begin
    # round-trip equality: reconstructed objects are == and hash-equal to the originals
    for r in (Solid("rt_solid",137.14u"g/mol",1.35u"g/mL",978),
              Liquid("rt_liquid",18.015u"g/mol",1.0u"g/mL",missing),
              Gas("rt_gas",44.01u"g/mol",1.98u"g/L",124389),
              Solid("rt_unknown",missing,missing,missing))
        id = CHESSDatabase.get_component_id(r)
        r2 = CHESSDatabase.get_component(id)
        @test r == r2
        @test hash(r) == hash(r2)
    end
    org = Organism("Streptococcus","mutans","UA159_rt")
    id_org = CHESSDatabase.get_component_id(org)
    org2 = CHESSDatabase.get_component(id_org)
    @test org == org2
    @test hash(org) == hash(org2)

    hplus_rt = CHESSCore.Chemical("H+_rt",1,1.008u"g/mol")
    id_chem = CHESSDatabase.get_chemical_id(hplus_rt)
    chem2 = CHESSDatabase.get_chemical(id_chem)
    @test hplus_rt == chem2
    @test hash(hplus_rt) == hash(chem2)

    # natural-key dedup: re-uploading the identical reagent/chemical/organism reuses the same row
    s_dedup = Solid("dedup_test",137.14u"g/mol",1.35u"g/mL",978)
    id1 = CHESSDatabase.get_component_id(s_dedup)
    id2 = CHESSDatabase.get_component_id(s_dedup)
    @test id1 == id2
    @test nrow(query_db("SELECT * FROM Reagents WHERE Name='dedup_test'")) == 1

    # ...but a Solid and Liquid sharing a name are still distinct rows
    s_distinct = Solid("distinct_test",1.0u"g/mol",1.0u"g/mL",1)
    l_distinct = Liquid("distinct_test",1.0u"g/mol",1.0u"g/mL",1)
    @test CHESSDatabase.get_component_id(s_distinct) != CHESSDatabase.get_component_id(l_distinct)

    # SQL escaping: names/comments containing apostrophes no longer break upload
    apostrophe_solid = Solid("O'Brien's reagent",137.14u"g/mol",1.35u"g/mL",978)
    id_ap = CHESSDatabase.get_component_id(apostrophe_solid)
    @test CHESSDatabase.get_component(id_ap) == apostrophe_solid

    apostrophe_org = Organism("Strep's","test'genus","str'ain")
    id_ap_org = CHESSDatabase.get_component_id(apostrophe_org)
    @test CHESSDatabase.get_component(id_ap_org) == apostrophe_org

    @test_nowarn upload(record_read!,main_room,Observation("it's a test observation with an apostrophe"))

    # hash-precision: a Stock whose hash exceeds typemax(Int64) still dedupes exactly via the
    # BLOB hex-literal encoding (sql_hash_literal), not a lossy bare numeric literal
    big_stock = nothing
    for i in 1:2000
        cand = i*u"g"*Solid("stockhash$i",100.0u"g/mol",1.0u"g/mL",missing)
        if hash(cand) > typemax(Int64)
            big_stock = cand
            break
        end
    end
    @test !isnothing(big_stock)
    sid1 = cache(big_stock)
    sid2 = cache(big_stock)
    @test sid1 == sid2

    # parameterized queries: a name containing a SQL comment sequence and a semicolon-separated
    # statement attempt round-trips as inert data instead of being interpreted as SQL
    injection_solid = Solid("x'; DROP TABLE Reagents; --",100.0u"g/mol",1.0u"g/mL",missing)
    id_inj = CHESSDatabase.get_component_id(injection_solid)
    @test CHESSDatabase.get_component(id_inj) == injection_solid
    @test nrow(query_db("SELECT * FROM Reagents")) > 0 # table was not dropped

    injection_org = Organism("Robert'); DROP TABLE Organisms; --","genus","species")
    id_inj_org = CHESSDatabase.get_component_id(injection_org)
    @test CHESSDatabase.get_component(id_inj_org) == injection_org
    @test nrow(query_db("SELECT * FROM Organisms")) > 0 # table was not dropped

    @test_nowarn upload(record_read!,main_room,Observation("obs'; DROP TABLE Reads; --"))

    # missing -> NULL: bound `missing` parameters store real SQL NULLs, not the string "NULL"
    missing_solid = Solid("missing_fields_test",missing,missing,missing)
    id_missing = CHESSDatabase.get_component_id(missing_solid)
    row = query_db("SELECT * FROM Reagents WHERE ComponentID = ?",(id_missing,))
    @test nrow(row) == 1
    @test ismissing(row[1,"MolecularWeight"])
    @test ismissing(row[1,"Density"])
    @test ismissing(row[1,"CID"])
    @test CHESSDatabase.get_component(id_missing) == missing_solid
end

@testset "barcode_queries" begin
    # bc2 (assigned to plate1) / bc (unassigned) are already built in build_test_database.jl
    fetched = get_barcode(barcode(bc2))
    @test name(fetched) == name(bc2)
    @test location_id(fetched) == location_id(plate1)

    all_bcs = CHESSDatabase.get_all_barcodes(location_id(plate1))
    @test any(b -> barcode(b) == barcode(bc2), all_bcs)

    @test length(CHESSDatabase.get_all_barcodes(location_id(plate1);return_limit=1)) == 1

    @test_throws ErrorException get_barcode("not-a-real-barcode")
end

@testset "Barcode assign variants" begin
    fresh = Barcode(string(UUIDs.uuid4()),"variant-test")
    assign_barcode!(fresh,plate1)
    @test location_id(fresh) == location_id(plate1)
    @test_throws ErrorException assign_barcode!(fresh,main_room) # already assigned elsewhere

    # non-mutating variant returns a copy, leaves the original argument untouched
    fresh2 = Barcode(string(UUIDs.uuid4()),"variant-test-2")
    copied = assign_barcode(fresh2,plate1)
    @test location_id(copied) == location_id(plate1)
    @test ismissing(location_id(fresh2))
end

@testset "Run(::Location,...) constructor" begin
    r = Run(plate1,exp_id,[1,2],[3,4])
    @test location_id(r) == location_id(plate1)
    @test CHESSDatabase.experiment_id(r) == exp_id
    @test CHESSDatabase.controls(r) == [1,2]
    @test CHESSDatabase.blanks(r) == [3,4]
end

@testset "experiment_run_queries" begin
    @test CHESSDatabase.parse_int_string("") == Int64[]
    @test CHESSDatabase.parse_int_string("1,2,3") == [1,2,3]

    fetched = get_run(run_id)
    @test location_id(fetched) == location_id(testrun)
    @test CHESSDatabase.experiment_id(fetched) == CHESSDatabase.experiment_id(testrun)
    @test CHESSDatabase.controls(fetched) == CHESSDatabase.controls(testrun)
    @test CHESSDatabase.blanks(fetched) == CHESSDatabase.blanks(testrun)

    all_runs = get_all_runs(CHESSDatabase.experiment_id(testrun))
    @test any(r -> location_id(r)==location_id(testrun) && CHESSDatabase.controls(r)==CHESSDatabase.controls(testrun), all_runs)

    @test CHESSDatabase.get_last_experiment_id() >= CHESSDatabase.experiment_id(testrun)
    @test CHESSDatabase.get_last_run_id() >= run_id
end

@testset "db_utils misc" begin
    @test CHESSDatabase.query_join_vector(["a","b"]) == ("(?,?)", ("a","b"))

    now_value = Dates.now()
    @test abs(julia_time(db_time(now_value)) - now_value) < Dates.Millisecond(2)

    attrs = get_all_attributes()
    @test nrow(attrs) > 0
    @test "Temperature" in attrs.Attribute

    # 1-arg, no-params forms -- confirmed dead in production call sites (everything else uses the
    # parameterized 2-arg form) but still part of the public connection interface
    @test execute_db("SELECT 1") isa Any # just confirm it doesn't throw
    @test nrow(query_db("SELECT 1 AS x")) == 1
end

@testset "encumbrances: get_all_encumbrances / get_encumbrance_completion" begin
    @test CHESSDatabase.get_all_encumbrances(protocol1_id) == collect(enc_move1:enc_move5)
    @test CHESSDatabase.get_all_encumbrances(protocol2_id) == [enc_transfer2,enc_move6]

    completion = CHESSDatabase.get_encumbrance_completion([enc_move1,enc_transfer2])
    @test completion[completion.EncumbranceID.==enc_move1,:IsComplete][1] == true
    @test completion[completion.EncumbranceID.==enc_transfer2,:IsComplete][1] == false
end

@testset "encumbrances: get_all_protocols / get_protocol_status" begin
    protocols = CHESSDatabase.get_all_protocols()
    @test protocol1_id in protocols.ProtocolID
    @test protocol2_id in protocols.ProtocolID
    @test protocols[protocols.ProtocolID.==protocol1_id,:Name][1] == "test_protocol"
    @test protocols[protocols.ProtocolID.==protocol1_id,:ExperimentID][1] == protocol1_exp_id
    @test protocols[protocols.ProtocolID.==protocol2_id,:Name][1] == "bufandisimo"

    status = CHESSDatabase.get_protocol_status([protocol1_id,protocol2_id])
    row1 = status[status.ProtocolID.==protocol1_id,:]
    @test row1.Total[1] == 12
    @test row1.Complete[1] == 1
    row2 = status[status.ProtocolID.==protocol2_id,:]
    @test row2.Total[1] == 2
    @test row2.Complete[1] == 0
end

@testset "encumbrances: get_encumbered_* getters" begin
    transfer = CHESSDatabase.get_encumbered_transfer(enc_transfer1)
    @test transfer.Source[1] == location_id(w2)
    @test transfer.Destination[1] == location_id(w1)
    @test transfer.Quantity[1] == ustrip(20u"g")
    @test transfer.Unit[1] == string(unit(20u"g"))

    movement = CHESSDatabase.get_encumbered_movement(enc_move1)
    @test movement.Parent[1] == location_id(shelf1)
    @test movement.Child[1] == location_id(plate1)

    humidity = quantity(Humidity(43u"percent"))
    env = CHESSDatabase.get_encumbered_environment_attribute(enc_env1)
    @test env.LocationID[1] == location_id(jensen_lab)
    @test env.Attribute[1] == "Humidity"
    @test env.Value[1] == ustrip(humidity)
    @test env.Unit[1] == string(unit(humidity))

    lock_on = CHESSDatabase.get_encumbered_lock(enc_lock1)
    @test lock_on.LocationID[1] == location_id(plate1)
    @test lock_on.Lock[1] == 1
    lock_off = CHESSDatabase.get_encumbered_lock(enc_lock2)
    @test lock_off.Lock[1] == 0

    act1 = CHESSDatabase.get_encumbered_activity(enc_activity1).Activate[1]
    act2 = CHESSDatabase.get_encumbered_activity(enc_activity2).Activate[1]
    @test act1 != act2
end

@testset "encumbrances: get_encumbrance_operation / isa_encumbered_*" begin
    @test CHESSDatabase.get_encumbrance_operation(enc_transfer1) == CHESSDatabase.get_encumbered_transfer
    @test CHESSDatabase.get_encumbrance_operation(enc_move1) == CHESSDatabase.get_encumbered_movement
    @test CHESSDatabase.get_encumbrance_operation(enc_env1) == CHESSDatabase.get_encumbered_environment_attribute
    @test CHESSDatabase.get_encumbrance_operation(enc_lock1) == CHESSDatabase.get_encumbered_lock
    @test CHESSDatabase.get_encumbrance_operation(enc_activity1) == CHESSDatabase.get_encumbered_activity
    @test_throws ErrorException CHESSDatabase.get_encumbrance_operation(-1)

    @test CHESSDatabase.isa_encumbered_transfer(enc_transfer1) == true
    @test CHESSDatabase.isa_encumbered_transfer(enc_move1) == false
    @test CHESSDatabase.isa_encumbered_movement(enc_move1) == true
    @test CHESSDatabase.isa_encumbered_movement(enc_transfer1) == false
    @test CHESSDatabase.isa_encumbered_environment_attribute(enc_env1) == true
    @test CHESSDatabase.isa_encumbered_environment_attribute(enc_move1) == false
    @test CHESSDatabase.isa_encumbered_lock(enc_lock1) == true
    @test CHESSDatabase.isa_encumbered_lock(enc_move1) == false
    @test CHESSDatabase.isa_encumbered_activity(enc_activity1) == true
    @test CHESSDatabase.isa_encumbered_activity(enc_move1) == false
end

@testset "encumbrances: get_encumbrance_status" begin
    status = CHESSDatabase.get_encumbrance_status(protocol1_id)
    @test nrow(status) == 12
    @test status[status.EncumbranceID.==enc_transfer1,:Operation][1] == "Transfer"
    @test status[status.EncumbranceID.==enc_move1,:Operation][1] == "Movement"
    @test status[status.EncumbranceID.==enc_env1,:Operation][1] == "Environment Attribute"
    @test status[status.EncumbranceID.==enc_lock1,:Operation][1] == "Lock"
    @test status[status.EncumbranceID.==enc_activity1,:Operation][1] == "Activity"
    @test status[status.EncumbranceID.==enc_move1,:IsComplete][1] == true
    @test status[status.EncumbranceID.==enc_move2,:IsComplete][1] == false
end

@location_kind IncapableReaderKind Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}() Set{Symbol}() true

@testset "Instrument: capability gate lives in CHESSCore, attribution in CHESSDatabase" begin
    @test location_id(reader1) isa Integer
    @test move_into! in performable_operations(reader1)
    @test record_read! in performable_operations(reader1)
    @test :Absorbance in readable_types(reader1) # descriptive only -- not enforced (Fluorescence/qualitative reads succeed too, see below)

    incapable=generate_location(IncapableReaderKind,"Incapable Reader")

    # the gate fires inside the CHESSCore operation function itself (via upload()'s fun(args...;instrument=instrument)),
    # not inside upload_read/upload_environment_attribute/etc.
    @test_throws ArgumentError upload(record_read!,w2,Fluorescence(50u"percent");instrument=incapable)
    @test_throws ArgumentError upload(set_attribute!,jensen_lab,Temperature(1u"°C");instrument=incapable)
    @test_throws ArgumentError upload(transfer!,w2,w1,0.001u"g";instrument=incapable)

    # readable_types is descriptive-only now -- a Fluorescence read via reader1 (whose readable_types
    # only lists :Absorbance) succeeds anyway, since only performable_operations gates
    @test_nowarn upload(record_read!,w2,Fluorescence(50u"percent");instrument=reader1)

    # capable operation/read succeed without error (already exercised in build_test_database.jl;
    # confirm here that they actually persisted with the right InstrumentID/InstrumentTime)
    transfer_row = CHESSDatabase.query_db("SELECT InstrumentID FROM Transfers WHERE InstrumentID = ? LIMIT 1",(location_id(reader1),))
    @test nrow(transfer_row) == 1
    env_row = CHESSDatabase.query_db("SELECT InstrumentID FROM EnvironmentAttributes WHERE InstrumentID = ? LIMIT 1",(location_id(reader1),))
    @test nrow(env_row) == 1
    move_row = CHESSDatabase.query_db("SELECT InstrumentID FROM Movements WHERE InstrumentID = ? LIMIT 1",(location_id(reader1),))
    @test nrow(move_row) == 1
    read_row = CHESSDatabase.query_db("SELECT InstrumentID FROM Reads WHERE InstrumentID = ? LIMIT 1",(location_id(reader1),))
    @test nrow(read_row) == 1
end

@testset "Instrument: reads -- multiplicity, Unknown/missing, reconstruction" begin
    # w2 accumulates: 2 Absorbance + 1 ColorimetricResult (build_test_database.jl) + 1 Fluorescence
    # (the previous testset's capability-gate check) -- none collapse.
    @test length(reads(w2)) == 4
    absorbance_reads = reads(w2,:Absorbance)
    @test length(absorbance_reads) == 2
    @test issorted(read_time.(absorbance_reads))
    @test CHESSCore.value.(absorbance_reads) == [90.0,95.0]

    w1_reads = reads(w1)
    @test any(r -> isunknown(CHESSCore.value(r)),w1_reads)
    @test any(r -> ismissing(CHESSCore.value(r)),w1_reads)

    fresh = reconstruct_location(location_id(w2))
    @test length(reads(fresh)) == 4
    @test issorted(read_time.(reads(fresh,:Absorbance)))
    @test CHESSCore.value.(reads(fresh,Absorbance)) == [90.0,95.0]
end

@testset "Instrument: qualitative reads round-trip (constrained + free-text)" begin
    colorimetric = only(reads(w2,:ColorimetricResult))
    @test CHESSCore.value(colorimetric) == "Positive"
    @test CHESSCore.quantity(colorimetric) == "Positive"

    fresh = reconstruct_location(location_id(w2))
    colorimetric_fresh = only(reads(fresh,:ColorimetricResult))
    @test CHESSCore.value(colorimetric_fresh) == "Positive"

    observation_values = CHESSCore.value.(reads(main_room,:Observation))
    @test "test_comment" in observation_values
    @test "it's a test observation with an apostrophe" in observation_values
    fresh_room = reconstruct_location(location_id(main_room))
    @test "test_comment" in CHESSCore.value.(reads(fresh_room,:Observation))
end

@testset "get_instrument_settings" begin
    settings = get_instrument_settings(location_id(reader1))
    @test settings[settings.Setting.=="Gain",:Value][1] == "2.0"
    @test settings[settings.Setting.=="Filter",:Value][1] == "GFP"

    # resolve as of the sequence position right after the first Gain revision, before the second --
    # confirms multi-revision resolution actually picks the revision in effect at the requested point,
    # not just always the latest. Resolved via get_sequence_id(gain1_ledger_id) rather than a cached
    # SequenceID, since test_cache_repair.jl's insert_ledger calls (which run between the fixture build
    # and this testset) shift SequenceIDs for earlier entries -- LedgerID is immutable, SequenceID isn't.
    old_settings = get_instrument_settings(location_id(reader1),get_sequence_id(gain1_ledger_id))
    @test old_settings[old_settings.Setting.=="Gain",:Value][1] == "1.5"
    @test nrow(old_settings[old_settings.Setting.=="Filter",:]) == 0 # Filter didn't exist yet at this point
end

@testset "Instrument reconstructs as Instrument (concretetype gap fix)" begin
    n,t = get_location_info(location_id(reader1))
    @test t(location_id(reader1),n) isa Instrument

    reconstructed = reconstruct_location(location_id(reader1))
    @test reconstructed isa Instrument
    @test name(reconstructed) == "Plate Reader 1"
end

rm(file)
