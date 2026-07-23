using CHESSCore, CHESSDatabase, Test, Unitful, UUIDs, SQLite, DataFrames,Dates

file="./test_db.db"
if isfile(file)
    rm(file)
end
create_db(file)
connect_SQLite(file)


#### set up a test lab
module TestChemOrg
using CHESSCore, Unitful
@reagent water "water" Liquid 18.015u"g/mol" 1.00u"g/mL" 962
@reagent glycerol "glycerol" Liquid missing missing missing
@reagent paba "4-aminobenzoic acid" Solid 137.14u"g/mol" 1.35u"g/mL" 978
@reagent iron_nitrate "Iron Nitrate" Solid 179.86u"g/mol" missing  9815404
@reagent lb "LB Broth" Solid missing missing missing

@organism SMU_UA159 "Streptococcus" "mutans" "UA159"
@organism SSA_SK36 "Streptococcus" "sanguinis" "SK36"
@location_kind TestWellKind Symbol[] nothing nothing 200u"µL" nothing nothing
end

CHESSCore.register_lab(TestChemOrg)

@attribute Temperature u"°C"
@attribute Pressure u"atm"
@attribute LinearShaking u"Hz"
@attribute Oxygen u"percent"
@attribute Humidity u"percent"


# Plain, policy-governed locations. Every kind of place/equipment is now a named LocationKind value
# (data), not a distinct Julia type — see the design discussion recorded in the plan file for why.
# The booleans from the old `@location name supertype constrained_as_parent constrained_as_child`
# macro become explicit default_parent_cost/default_child_cost (2//1 = blocked by default, 0//1 =
# unconstrained by default).
@location_kind Lab            Symbol[] nothing nothing nothing nothing nothing 0//1 2//1
@location_kind Room           Symbol[] nothing nothing nothing nothing nothing 0//1 0//1
@location_kind Bench          Symbol[] nothing nothing nothing nothing nothing 0//1 0//1
@location_kind Incubator      Symbol[] nothing nothing nothing nothing nothing 2//1 0//1
@location_kind IncubatorShelf Symbol[] nothing nothing nothing nothing nothing 0//1 2//1
@location_kind BioSpa         Symbol[] nothing nothing nothing nothing nothing 2//1 0//1
@location_kind BioSpaDrawer   Symbol[] nothing nothing nothing nothing nothing 2//1 2//1
@location_kind BioSpaSlot     Symbol[] nothing nothing nothing nothing nothing 2//1 2//1
@location_kind AltemisSlot    Symbol[] nothing nothing nothing nothing nothing 2//1 2//1

CHESSCore.set_occupancy_cost!(:BioSpa,:BioSpaDrawer,1//4)
CHESSCore.set_occupancy_cost!(:BioSpaDrawer,:BioSpaSlot,1//2)
CHESSCore.set_occupancy_cost!(:BioSpaSlot,:Plate,1//1) # :Plate is a category, matches any plate-tagged Labware kind
CHESSCore.set_occupancy_cost!(:Incubator,:IncubatorShelf,1//3)


# Well kinds — capacity is data on the kind (`kind.capacity`), not a Well{N} type parameter.
@location_kind Well200     Symbol[] nothing nothing 200u"µL"     nothing nothing
@location_kind Well80      Symbol[] nothing nothing 80u"µL"      nothing nothing
@location_kind Well1000000 Symbol[] nothing nothing 1000000u"µL" nothing nothing
@location_kind Well50000   Symbol[] nothing nothing 50000u"µL"   nothing nothing
@location_kind Well1000    Symbol[] nothing nothing 1000u"µL"    nothing nothing

@location_kind WP96 [:Plate] (8,12) :Well200 nothing "Thermo" "123456"
@location_kind WP384 [:Plate] (16,24) :Well80 nothing "Thermo" "123457"
@location_kind Bottle1L Symbol[] (1,1) :Well1000000 nothing "Corning" "1"
@location_kind IronNitrateBottle Symbol[] (1,1) :Well1000000 nothing "Sigma" "111"
@location_kind LBBottle Symbol[] (1,1) :Well1000000 nothing "Sigma" "123"
@location_kind PabaBottle Symbol[] (1,1) :Well50000 nothing "Sigma" "234"

@location_kind AltemisTube Symbol[] (1,1) :Well1000 nothing "Altemis" "1234"

CHESSCore.set_occupancy_cost!(:AltemisSlot,:AltemisTube,1//1)

@location_kind AltemisBox [:Plate] (8,12) :AltemisSlot nothing "Altemis" "4321"


@location_kind ExamplePlateStack Symbol[] (10,1) :WP96 nothing "Testing" "testing"

plate_stack_namer(row,col) = "plate $row"




jensen_lab=generate_location(Lab,"Jensen Lab")
main_room=generate_location(Room,"Main Room")
culture_room=generate_location(Room,"Culture Room")
robot_room=generate_location(Room,"Robot Room")
incubator1=generate_location(Incubator,"Upper Incubator")
incubator2=generate_location(Incubator,"Lower Incubator")
shelf1=generate_location(IncubatorShelf,"Upper Shelf")
shelf2=generate_location(IncubatorShelf,"Middle Shelf")
shelf3=generate_location(IncubatorShelf,"Lower Shelf")
shelf4=generate_location(IncubatorShelf,"Middle Shelf")
biospa1=generate_location(BioSpa,"Biospa 1")
dr1=generate_location(BioSpaDrawer,"Drawer 1")
dr2=generate_location(BioSpaDrawer,"Drawer 2")
dr3=generate_location(BioSpaDrawer,"Drawer 3")
dr4=generate_location(BioSpaDrawer,"Drawer 4")
l1=generate_location(BioSpaSlot,"Left")
l2=generate_location(BioSpaSlot,"Left")
l3=generate_location(BioSpaSlot,"Left")
l4=generate_location(BioSpaSlot,"Left")
r1=generate_location(BioSpaSlot,"Right")
r2=generate_location(BioSpaSlot,"Right")
r3=generate_location(BioSpaSlot,"Right")
r4=generate_location(BioSpaSlot,"Right")




b1=generate_location(Bottle1L)
b2=generate_location(PabaBottle,"Paba")
plate1=generate_location(WP96)
box1=generate_location(AltemisBox,"Freezer Box 1")


upload(set_attribute!,jensen_lab,Temperature(25u"°C"))
upload(set_attribute!,jensen_lab,Pressure(1u"atm"))
upload(set_attribute!,biospa1,Temperature(37u"°C"))
upload(set_attribute!,incubator1,Temperature(37u"°C"))

cache(jensen_lab)
upload(set_attribute!,jensen_lab,Temperature(missing))

upload(lock!,main_room)
upload(unlock!,main_room)
upload(toggle_lock!,jensen_lab)
upload(toggle_lock!,jensen_lab)

upload(activate!,main_room)
upload(deactivate!,main_room)
upload(toggle_activity!,main_room)


upload(move_into!,jensen_lab,main_room)
upload(move_into!,jensen_lab,culture_room)
upload(move_into!,jensen_lab,robot_room)
upload(move_into!,culture_room,incubator1)
upload(move_into!,culture_room,incubator2)
upload(move_into!,incubator1,shelf1,true)
upload(move_into!,incubator1,shelf2,true)
upload(move_into!,incubator1,shelf3,true)
upload(move_into!,robot_room,biospa1)
upload(move_into!,biospa1,dr1,true)
upload(move_into!,biospa1,dr2,true)
upload(move_into!,biospa1,dr3,true)
upload(move_into!,biospa1,dr4,true)
upload(move_into!,dr1,l1,true)
upload(move_into!,dr1,r1,true)
upload(move_into!,dr2,l2,true)
upload(move_into!,dr2,r2,true)
upload(move_into!,dr3,l3,true)
upload(move_into!,dr3,r3,true)
upload(move_into!,dr4,l4,true)
upload(move_into!,dr4,r4,true)
upload(move_into!,main_room,b1)
upload(move_into!,main_room,b2)
upload(move_into!,main_room,plate1)


upload(set_attribute!,jensen_lab,Temperature(25u"°C"))


w1=b1[1,1]

w2=b2[1,1]

deposit!(w2,50u"g"*rgt"paba", 20)
deposit!(w1,500u"mL"*rgt"water" + 2u"g" *rgt"iron_nitrate",3)
deposit!(w1,Empty()+org"SMU_UA159",0)
cache(w1)
cache(w2)

upload(transfer!,w2,w1,5u"g")
upload(transfer!,w1,plate1[1,1],100u"µL")


@read Observation

upload(record_read!,main_room,Observation("test_comment")) # replaces the old Tags system -- a location-scoped, qualitative, free-text observation (no instrument -- a human note)

bc=Barcode(string(UUIDs.uuid4()),"lazy_blue_poodle")
upload_barcode(bc)

bc2=Barcode(string(UUIDs.uuid4()),"nasty_green_baboon")
upload_barcode(bc2)

upload(assign_barcode!,bc2,plate1)


exp_id =upload_experiment("test_experiment","Ben")

testrun = Run(1,exp_id,[2,3,4],[5,6,7])
run_id = upload_run(testrun)

p_id=upload_protocol(exp_id,"test_protocol")
protocol1_id = p_id
protocol1_exp_id = exp_id
enc_move1 = encumber( p_id , move_into!,shelf1,plate1)

enc_move2 = encumber( p_id , move_into!,l1,plate1)
enc_move3 = encumber( p_id , move_into!,main_room,plate1)
enc_transfer1 = encumber( p_id , transfer!,w2,w1,20u"g")
enc_env1 = encumber( p_id , set_attribute!,jensen_lab,Humidity(43u"percent"))
enc_lock1 = encumber( p_id , CHESSCore.lock!,plate1)
enc_lock2 = encumber( p_id , CHESSCore.unlock!,plate1)
enc_activity1 = encumber( p_id , toggle_activity!,plate1)
enc_activity2 = encumber( p_id , toggle_activity!,plate1)
enc_env2 = encumber( p_id , set_attribute!,jensen_lab,Humidity(40u"percent"))
enc_move4 = encumber( p_id , move_into!,jensen_lab,b1)
enc_move5 = encumber( p_id , move_into!,l1,plate1,true) # exercises encumber_movement's lock branch
CHESSCore.unlock!(plate1) # undo the in-memory lock so later fixture moves of plate1 aren't blocked
encumber_cache(get_last_encumbrance_id(p_id),plate1)

exp_id = upload_experiment("bufanda","Ben")

p_id=upload_protocol(exp_id,"bufandisimo")
protocol2_id = p_id
protocol2_exp_id = exp_id

enc_transfer2 = encumber( p_id , transfer!,w1,plate1[4,8],100u"µL")
enc_move6 = encumber( p_id , move_into!,culture_room,plate1)
CHESSDatabase.upload_encumbrance_completion(1,get_last_ledger_id())

@read Absorbance u"percent" # NOTE: u"OD" would be the natural unit here, but Unitful.uparse (used by
# reconstruct_reads!, mirroring reconstruct_attributes!'s existing pattern) can't resolve custom
# lab-registered units like OD without an explicit unit_context -- a pre-existing gap shared with
# reconstruct_attributes.jl/reconstruct_contents.jl, not something introduced by this feature. Using a
# standard unit here sidesteps it rather than fixing that pre-existing, unrelated bug in this pass.
@read Fluorescence u"percent"
@read ColorimetricResult nothing Set(["Positive","Negative"]) # qualitative, constrained

@location_kind PlateReaderModelX Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set([move_into!,transfer!,set_attribute!,record_read!]) Set([:Absorbance]) true

reader1 = generate_location(PlateReaderModelX,"Plate Reader 1")

upload(transfer!,w2,w1,1u"g";instrument=reader1)
upload(set_attribute!,jensen_lab,Temperature(30u"°C");instrument=reader1)
upload(move_into!,main_room,box1;instrument=reader1)

upload(record_read!,w2,Absorbance(90u"percent",Dates.now());instrument=reader1)
upload(record_read!,w2,Absorbance(95u"percent",Dates.now()+Dates.Second(5));instrument=reader1) # second read of the same kind/well -- reads never collapse
upload(record_read!,w1,Absorbance(CHESSCore.Unknown);instrument=reader1) # instrument attempted this and got an indeterminate result
upload(record_read!,w1,Absorbance(missing);instrument=reader1) # in scope for the batch, no result
upload(record_read!,w2,ColorimetricResult("Positive");instrument=reader1) # qualitative read, same instrument (readable_types is descriptive-only now -- no gate on the specific ReadKind)

gain1_ledger_id = upload_instrument_setting(reader1,"Gain",1.5) # LedgerID is immutable even if a later insert_ledger/replace_ledger shifts SequenceIDs -- see get_instrument_settings's testset
upload_instrument_setting(reader1,"Gain",2.0) # second revision of the same setting
upload_instrument_setting(reader1,"Filter","GFP") # non-numeric setting value


st1 = generate_location(ExamplePlateStack,"test stack",plate_stack_namer, plate_namer)

st2 = generate_location(WP96, "test single namer" , plate_namer)

well_check = get_all_within(st1, Well)

println("n_wells = $(length(well_check))")



#reconstruct_location(collect(25:30))
#=
@time reconstruct_location(collect(25:30))

@time reconstruct_location(collect(25:30);cache_results=true)

@time reconstruct_location(collect(25:30))
=#
