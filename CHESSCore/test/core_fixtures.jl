# Location-kind/attribute/chemical registrations plus an uncommitted (in-memory only) location tree,
# shared by every DB-free testset in core_runtests.jl. Mirrors the registrations in
# build_test_database.jl, but builds locations with `build_location` and plain mutating calls
# (`move_into!`/`set_attribute!`) instead of `generate_location`/`upload(...)`, since none of the
# properties these fixtures are used to test (occupancy, containment, kind identity, environment
# inheritance) depend on the location being committed to a real database.
#
# This file is the single source of truth for these registrations -- `@location_kind` throws if a
# name is registered twice, so build_test_database.jl (included later, by database_runtests.jl) does
# NOT redeclare any of these; it assumes this file has already run in the same process.

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
@attribute TestHumidity u"percent"
@read TestpH nothing
@chemical TestNa⁺ "TestNa+" 1 22.99u"g/mol"
@chemical TestCa²⁺ "TestCa2+" 2 40.08u"g/mol"
@chemical TestH2PO4⁻ "TestH2PO4-" -1 96.99u"g/mol"
@chemical TestSO4²⁻ "TestSO4 2-" -2 96.06u"g/mol"
@stock test_stock_recipe 1u"mL" * water
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


# Uncommitted location tree — same shape as build_test_database.jl's committed, DB-backed tree, built with
# `build_location` (no database calls, `location_id === nothing`) and plain mutating calls instead of
# `generate_location`/`upload(...)`. Only the instances actually referenced by DB-free testsets
# (Locations, Environments, LocationKind sharing, Labware indexing, Location child lookup) are built
# here -- build_test_database.jl builds the full, real-ID-backed tree (including barcodes,
# experiments, runs, encumbrances) separately for the DB-dependent testsets.
jensen_lab=build_location(Lab,"Jensen Lab")
main_room=build_location(Room,"Main Room")
culture_room=build_location(Room,"Culture Room")
robot_room=build_location(Room,"Robot Room")
incubator1=build_location(Incubator,"Upper Incubator")
incubator2=build_location(Incubator,"Lower Incubator")
shelf1=build_location(IncubatorShelf,"Upper Shelf")
shelf2=build_location(IncubatorShelf,"Middle Shelf")
shelf3=build_location(IncubatorShelf,"Lower Shelf")
biospa1=build_location(BioSpa,"Biospa 1")
dr1=build_location(BioSpaDrawer,"Drawer 1")
dr2=build_location(BioSpaDrawer,"Drawer 2")
dr3=build_location(BioSpaDrawer,"Drawer 3")
dr4=build_location(BioSpaDrawer,"Drawer 4")
l1=build_location(BioSpaSlot,"Left")
l2=build_location(BioSpaSlot,"Left")
l3=build_location(BioSpaSlot,"Left")
l4=build_location(BioSpaSlot,"Left")
r1=build_location(BioSpaSlot,"Right")
r2=build_location(BioSpaSlot,"Right")
r3=build_location(BioSpaSlot,"Right")
r4=build_location(BioSpaSlot,"Right")

plate1=build_location(WP96)

set_attribute!(jensen_lab,Temperature(25u"°C"))
set_attribute!(jensen_lab,Pressure(1u"atm"))
set_attribute!(biospa1,Temperature(37u"°C"))
set_attribute!(incubator1,Temperature(37u"°C"))

move_into!(jensen_lab,main_room)
move_into!(jensen_lab,culture_room)
move_into!(jensen_lab,robot_room)
move_into!(culture_room,incubator1)
move_into!(culture_room,incubator2)
move_into!(incubator1,shelf1,true)
move_into!(incubator1,shelf2,true)
move_into!(incubator1,shelf3,true)
move_into!(robot_room,biospa1)
move_into!(biospa1,dr1,true)
move_into!(biospa1,dr2,true)
move_into!(biospa1,dr3,true)
move_into!(biospa1,dr4,true)
move_into!(dr1,l1,true)
move_into!(dr1,r1,true)
move_into!(dr2,l2,true)
move_into!(dr2,r2,true)
move_into!(dr3,l3,true)
move_into!(dr3,r3,true)
move_into!(dr4,l4,true)
move_into!(dr4,r4,true)
move_into!(main_room,plate1)

st2 = build_location(WP96, "test single namer" , plate_namer)
