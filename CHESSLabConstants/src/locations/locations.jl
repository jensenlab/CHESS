# Location kinds, translated from the old JLIMS-era abstract-type hierarchy (WellPlate <: Labware,
# DeepWell <: WellPlate, etc., defined via @location/@labware/@occupancy_cost against real Julia
# types) onto current CHESSCore's data-driven LocationKind: each old ancestor chain becomes a flat
# `categories` tag list, and each `@occupancy_cost ParentKind AncestorType cost` wildcard rule becomes
# `set_occupancy_cost!(:ParentKind,:CategoryTag,cost)` keyed on that same tag -- see
# CHESSCore/src/locations/Occupancy.jl. Instrument capability metadata
# (actuatable_attributes/performable_operations/readable_types) isn't modeled here; every
# `is_instrument=true` kind below has empty capability sets, to be filled in as separate follow-up work.

#general
@location_kind Lab Symbol[] nothing nothing nothing nothing nothing
@location_kind Room Symbol[] nothing nothing nothing nothing nothing
@location_kind Bench Symbol[] nothing nothing nothing nothing nothing
@location_kind Shelf Symbol[] nothing nothing nothing nothing nothing

# well-capacity socket kinds (the old system's inline `Well{capacity}` sockets become real,
# separately-registered LocationKinds so they can be referenced by name)
@location_kind Well200 Symbol[] nothing nothing 200u"µL" nothing nothing
@location_kind Well400 Symbol[] nothing nothing 400u"µL" nothing nothing
@location_kind Well100 Symbol[] nothing nothing 100u"µL" nothing nothing
@location_kind Well2000 Symbol[] nothing nothing 2000u"µL" nothing nothing
@location_kind Well150000 Symbol[] nothing nothing 150000u"µL" nothing nothing
@location_kind Well25000 Symbol[] nothing nothing 25000u"µL" nothing nothing
@location_kind Well100000 Symbol[] nothing nothing 100000u"µL" nothing nothing
@location_kind Well50000 Symbol[] nothing nothing 50000u"µL" nothing nothing
@location_kind Well15000 Symbol[] nothing nothing 15000u"µL" nothing nothing
@location_kind Well10000 Symbol[] nothing nothing 10000u"µL" nothing nothing
@location_kind Well1000000 Symbol[] nothing nothing 1000000u"µL" nothing nothing
@location_kind Well500000 Symbol[] nothing nothing 500000u"µL" nothing nothing
@location_kind Well250000 Symbol[] nothing nothing 250000u"µL" nothing nothing
@location_kind Well1400 Symbol[] nothing nothing 1400u"µL" nothing nothing
@location_kind Well1000 Symbol[] nothing nothing 1000u"µL" nothing nothing

# tip reservoir (manifolds)
@location_kind TipReservior Symbol[] (1,1) :Well200 nothing "USA Scientific" "200 ul tip"

#plates
@location_kind WP96 [:MicroPlate,:WellPlate] (8,12) :Well400 nothing "Thermo" "123456"
@location_kind WP384 [:MicroPlate,:WellPlate] (16,24) :Well100 nothing "Thermo" "123457"
@location_kind DeepWP96 [:DeepWell,:WellPlate] (8,12) :Well2000 nothing "VWR" "76329-998"
@location_kind DeepReservior [:DeepWell,:WellPlate] (1,1) :Well150000 nothing "Thermo" "N/A"

# reservoir
@location_kind Reservior25mL [:Reservior] (1,1) :Well25000 nothing "Thermo" "N/A"
@location_kind Reservoir100mL [:Reservior] (1,1) :Well100000 nothing "Thermo" "N/A"

# PCR
@location_kind PCRTube [:PCRLabware] (1,1) :Well200 nothing "Thermo" "N/A"
@location_kind PCR8Strip [:PCRLabware] (8,1) :Well200 nothing "Thermo" "N/A"
@location_kind BreakawayPCRWafer [:PCRLabware] (8,4) :Well200 nothing "Thermo" "N/A"
@location_kind BreakawayPCRPlate [:PCRLabware] (1,3) :BreakawayPCRWafer nothing "Thermo" "N/A"
@location_kind PCRRack [:Rack] nothing nothing nothing nothing nothing
@location_kind QPCRPlate96 [:PCRLabware] (8,12) :Well200 nothing "Thermo" "N/A"
@location_kind MagPlate [:PCRLocation] nothing nothing nothing nothing nothing

#tubes
@location_kind Conical50 [:Conical,:Tube] (1,1) :Well50000 nothing "Thermo" "339652"
@location_kind Conical15 [:Conical,:Tube] (1,1) :Well15000 nothing "Corning" "430791"
@location_kind CultureTube10mL [:CultureTube,:Tube] (1,1) :Well10000 nothing "Fisher" "149569C"

#bottles
@location_kind Bottle1L [:ScrewBottle,:Bottle] (1,1) :Well1000000 nothing "Fisher" "FB-800-1000"
@location_kind Bottle500mL [:ScrewBottle,:Bottle] (1,1) :Well500000 nothing "Fisher" "FB-800-500"
@location_kind Bottle250mL [:ScrewBottle,:Bottle] (1,1) :Well250000 nothing "Fisher" "FB-800-250"
@location_kind FilterBottle1L [:FilterBottle,:Bottle] (1,1) :Well1000000 nothing "Fisher" "FB12566506"

#Freezer labware
@location_kind CryoTubeSlot [:Slot] nothing nothing nothing nothing nothing
@location_kind AltemisTube [:CryoTube,:Tube] (1,1) :Well1400 nothing "Altemis" "AlteTube"
@location_kind AltemisBox [:Box] (8,12) :CryoTubeSlot nothing "Altemis" "AlteBox"
@location_kind MatrixTube [:CryoTube,:Tube] (1,1) :Well1000 nothing "Thermo" "MatrixTube"
@location_kind MatrixBox [:Box] (8,12) :CryoTubeSlot nothing "Thermo" "Matrix"
