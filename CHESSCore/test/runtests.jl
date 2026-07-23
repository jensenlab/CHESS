using CHESSCore, Test, Unitful, AbstractTrees, DataFrames, Dates

include("core_fixtures.jl")

# test new unit parsing
@testset "NewUnitParsing" begin
    @test uparse("OD",unit_context=[Unitful,JensenLabUnits])==u"OD"
    @test uparse("RFU",unit_context=[Unitful,JensenLabUnits])==u"RFU"
    @test uparse("X",unit_context=[Unitful,JensenLabUnits])==u"X"
end

x="water"
y="SMU_UA159"
@testset "ChemicalTypes" begin
    @test rgt"paba" isa Solid
    @test rgt"water" isa Liquid
    @test reagentparse(x,reagent_context=[CHESSCore,TestChemOrg]) == rgt"water"
    @test org"SMU_UA159" isa Organism
    @test orgparse(y,org_context=[CHESSCore,TestChemOrg]) == org"SMU_UA159"
    @test loc"TestWellKind" === TestChemOrg.TestWellKind # loc"..." mirrors rgt"..."'s lab-module search
    @test attr"TestHumidity" === TestChemOrg.TestHumidity # attr"..." mirrors loc"..."'s lab-module search
    @test read"TestpH" === TestChemOrg.TestpH # read"..." mirrors loc"..."'s lab-module search
    @test stock"test_stock_recipe" === TestChemOrg.test_stock_recipe # stock"..." mirrors loc"..."'s lab-module search
end

module StockRegistryTest
using CHESSCore, Unitful
using Main: TestChemOrg
const unregistered_intermediate = 1u"mL" * TestChemOrg.water # a bare const, never registered via @stock
@stock registered_recipe 2u"mL" * TestChemOrg.water
end
CHESSCore.register_lab(StockRegistryTest)

# @stock's `const` declaration is only valid at top-level scope, so the duplicate-registration
# attempt has to happen here (not inside a @testset body) -- the haskey check is against the
# already-merged central registry, so re-using the same name from anywhere throws.
stock_duplicate_error = try
    @eval @stock registered_recipe 1u"mL" * TestChemOrg.water
    nothing
catch e
    e
end

@testset "@stock registers a recipe; a bare const Stock does not" begin
    @test haskey(stock_recipes, :registered_recipe)
    @test stock_recipes[:registered_recipe] === StockRegistryTest.registered_recipe
    @test stock"registered_recipe" === StockRegistryTest.registered_recipe

    # a plain `const` Stock binding, never passed through @stock, is NOT reachable via stock"..."
    @test !haskey(stock_recipes, :unregistered_intermediate)
    @test_throws ArgumentError stock"unregistered_intermediate"

    # duplicate registration under the same name throws
    @test stock_duplicate_error isa ArgumentError
end

@testset "registry_summary assembles all categories from a lab module" begin
    summary = registry_summary([CHESSCore,TestChemOrg])

    @test any(r -> r.name === :water && r.module_ === TestChemOrg, summary.reagents)
    @test any(c -> c.name === Symbol("TestNa⁺") && c.module_ === TestChemOrg, summary.chemicals)
    @test any(s -> s.name === :test_stock_recipe && s.module_ === TestChemOrg, summary.stocks)
    @test any(o -> o.name === :SMU_UA159 && o.genus == "Streptococcus", summary.organisms)
    @test any(l -> l.name === :TestWellKind, summary.locations)
    @test any(a -> a.name === :TestHumidity && a.unit == u"percent", summary.attributes)
    @test any(r -> r.name === :TestpH, summary.reads)
end

@testset "@attribute/@read no longer export -- attr_str/read_str are the collision-safe lookup" begin
    @test !(:TestHumidity in names(TestChemOrg))
    @test !(:TestpH in names(TestChemOrg))
    @test isdefined(TestChemOrg,:TestHumidity) # still a real const binding, just not exported
    @test isdefined(TestChemOrg,:TestpH)
end




a=100u"mL"*rgt"water" #solution
b=10u"g"*rgt"paba" # mixture
c=5u"g"*rgt"iron_nitrate" #mixture
d=10u"mL"*rgt"glycerol" #solution
e=Empty()+org"SMU_UA159"

@testset "Stocks" begin
    @test a isa Solution
    @test b isa Mixture
    @test e isa Culture
    @test volume_estimate(b) == quantity(b)/density(rgt"paba") # volume estimate method
    @test 1u"mol"*rgt"paba" == convert(u"g",1u"mol",rgt"paba")*rgt"paba" # equivalence of the mass vs mol constructors
    @test 0.01u"kg"*rgt"paba" == b # equivalence of unit changes
end

@testset "reagent_display / show consolidation" begin
    out_solids,out_liquids,out_organisms = reagent_display(b)
    @test out_solids["4-aminobenzoic acid"]["Amount"] == (10.0,"g")
    @test out_solids["4-aminobenzoic acid"]["Concentration"] == (100.0,"percent")
    @test isempty(out_liquids)

    ac = a+c
    sol_ac,liq_ac,_ = reagent_display(ac)
    @test liq_ac["water"]["Concentration"] == (100.0,"percent") # same-dimension branch: percent
    @test sol_ac["Iron Nitrate"]["Amount"] == (5.0,"g")
    @test sol_ac["Iron Nitrate"]["Concentration"] == (0.05,"g/mL") # cross-dimension branch: mass/volume

    str = sprint(show, MIME"text/plain"(), b)
    @test occursin("reagent(s)",str)
    @test !occursin("chemical(s)",str)
    @test occursin("Name",str)
    @test occursin("Amount",str)
    @test occursin("4-aminobenzoic acid",str) # descriptive name shown alongside the symbol

    # _reagent_table's empty-dict path doesn't error
    arr,amt,conc = CHESSCore._reagent_table(CHESSCore.SolidDict(), 1u"mL")
    @test isempty(arr) && isempty(amt) && isempty(conc)
end


@testset "MixingArithmetic" begin
    @test c+b isa Mixture
    @test a+c isa Solution
    @test a+e isa Culture
    @test a==a+Empty() #identity
    @test a-a == Empty() #identity
    @test allequal([a+b+c , b+c+a , c+a+b]) #commutative property
    @test ((a+b)+c)==(a + (b+c)) #associative property
    @test a+b+c+d-(b+d) == a+c # subtraction
    @test_throws CHESSCore.MixingError a-b # removing paba from pure water results in a mixing error ->  violation of non-negativity constraints on masses and volumes
    @test 3*a == a+a+a # scalar multiplication
    @test a * 3 == 3 * a # scalar multiplication  commutative property
    @test a/3 == 1/3 * a # scalar division
    @test 3*(a+e) == a+a+a+e+e+e # there is no quantity to track for e in this case, but it does contribute to the organismal contents
    @test e+a-e !=a # identity property does not hold for cultures
    @test e-e != Empty() # ' '
    @test quantity(10u"mL"*a) == 10u"mL" # quantity multiplcation
    @test quantity(10u"mL"*((10/3)*a)) == 10u"mL" # floating point quantity multiplication
    @test 10u"mL" *a == a * 10u"mL" # commutative property
end


@testset "Locations" begin
    @test CHESSCore.kind(jensen_lab) === Lab
    @test occupancy(jensen_lab) == 0//1
    @test occupancy(biospa1)==1//1
    @test_throws CHESSCore.OccupancyError can_move_into(biospa1,jensen_lab)
    @test_throws CHESSCore.LockedLocationError can_move_into(main_room,dr1)
    @test_throws CHESSCore.AlreadyLocatedInError can_move_into(jensen_lab,main_room)
    @test in(main_room, jensen_lab) == true
    @test in(plate1, jensen_lab) == true
    @test CHESSCore.softequal(jensen_lab,deepcopy(jensen_lab)) ==true
    @test CHESSCore.softequal(l1,deepcopy(l1)) == true
end


@location_kind Well10000 Symbol[] nothing nothing 10000u"µL" nothing nothing

w1=Well(1,"testwell1",Well1000000;stock=a)
w2=Well(2,"testwell2",Well10000;stock=b)

# Fresh, purpose-built, standalone (parent=nothing) fixtures per assertion -- each is mutated
# directly with the `!` form. Standalone wells aren't part of any tree, so mutating them in place
# doesn't risk affecting anything else; this replaces the old drain/sterilize/empty/transfer
# non-mutating variants, which were removed (see reconstruct_location/build_location docstrings for
# the actual preview pattern).
w3_sterilized=Well(3,"w3-sterilize",Well1000000;stock=(a/10)+e)
sterilize!(w3_sterilized)

w3_drained=Well(3,"w3-drain",Well1000000;stock=(a/10)+e)
drain!(w3_drained)

w3_emptied=Well(3,"w3-empty",Well1000000;stock=(a/10)+e)
empty!(w3_emptied)

w3_both=Well(3,"w3-both",Well1000000;stock=(a/10)+e)
drain!(w3_both)
sterilize!(w3_both)

transfer_donor=Well(4,"transfer-donor",Well10000;stock=b)
transfer_recipient=Well(5,"transfer-recipient",Well1000000;stock=(a/10)+e)
transfer!(transfer_donor,transfer_recipient,5u"g")

@testset "Wells" begin
   @test stock(w1)==a
   @test CHESSCore.wellcapacity(w1)==1u"L"
   @test stock(w3_sterilized) == a/10 # removes the organisms only
   @test stock(w3_drained) == e
   @test stock(w3_emptied)==Empty()
   @test stock(w3_emptied) == stock(w3_both) # empty == dump |> sterilize
   @test stock(transfer_recipient) == ((a/10)+e) + b/2
   @test_throws MixingError transfer!(Well(6,"w2b",Well10000;stock=b),Well(7,"w1b",Well1000000;stock=a),20u"g") # try to transfer 20 g from a 10 g stock of paba
   @test_throws WellCapacityError Well(8,"testwell4",Well10000;stock=a) # try to put a 100mL stock in a 10 mL well
end


@testset "Environments" begin
    @test Temperature(10u"°C") == Temperature(10u"°C")
    @test Temperature(10u"°C") != Temperature(1u"°C")
    @test environment(jensen_lab)==environment(main_room)
    @test environment(biospa1)==environment(dr1)
end


@testset "LocationKind sharing" begin
    # every WP96 instance shares the SAME LocationKind object -- the whole point of the redesign
    @test CHESSCore.kind(plate1) === WP96
    @test CHESSCore.kind(st2) === WP96
    @test CHESSCore.kind(plate1) === CHESSCore.kind(st2)
    @test CHESSCore.location_kinds[:WP96] === WP96 # loc"WP96" itself is exercised in the ChemicalTypes-style
                                                # lab-module search context; WP96 here is a plain
                                                # top-level binding (like the test script's chemicals),
                                                # not inside a registered lab module, so loc"..." (which
                                                # mirrors chem"..."'s lab-module search) wouldn't find it.
    @test CHESSCore.concretetype(WP96) === Labware
    @test CHESSCore.concretetype(Well200) === Well
    @test CHESSCore.concretetype(Room) === CHESSCore.GenericLocation
end

@location_kind CatA [:Shared] nothing nothing nothing nothing nothing
@location_kind CatB [:Shared] nothing nothing nothing nothing nothing
@location_kind CatC Symbol[] nothing nothing nothing nothing nothing
CHESSCore.set_occupancy_cost!(:CatA,:CatC,1//2)
CHESSCore.set_occupancy_cost!(:Shared,:CatC,1//3)

@testset "Structural vs policy movement errors" begin
    @test_throws FixedMembershipError CHESSCore.add_to!(plate1,CHESSCore.GenericLocation(nothing,"x",Room))
    @test_throws FixedMembershipError CHESSCore.add_to!(w1,CHESSCore.GenericLocation(nothing,"x",Room))

    # remove! mirrors add_to! -- Labware's own docstring already claimed this, but only add_to! had
    # the override; without it, remove!(plate1,...) would throw a bare MethodError (filter! has no
    # method for a Matrix) and remove!(w1,...) a field-access error (Well has no `children` field),
    # instead of the documented, structural FixedMembershipError
    @test_throws FixedMembershipError CHESSCore.remove!(plate1,children(plate1)[1,1])
    @test_throws FixedMembershipError CHESSCore.remove!(w1,CHESSCore.GenericLocation(nothing,"x",Room))

    p=CHESSCore.GenericLocation(nothing,"p",CatA)
    ch=CHESSCore.GenericLocation(nothing,"ch",CatC)
    @test CHESSCore.occupancy_cost(p,ch) == 1//2 # exact kind rule wins over category rule

    p2=CHESSCore.GenericLocation(nothing,"p2",CatB)
    @test CHESSCore.occupancy_cost(p2,ch) == 1//3 # single category-rule match resolves without ambiguity

    # a Well can never be independently relocated -- unconditional, even into a plain Room with no
    # occupancy rules configured at all (regression: this used to be enforced only as a side effect
    # of a parent_cost/child_cost hack that also corrupted occupancy() reporting for every Labware)
    real_well = children(plate1)[1,1]
    @test_throws FixedMembershipError can_move_into(main_room,real_well)
    @test_throws FixedMembershipError move_into!(main_room,real_well)

    # a populated Labware is always considered 100% occupied -- its wells are fixed at construction
    # and can never be gained or lost, so there's no "how full" question the way there is for a
    # GenericLocation/Instrument (mirrors occupancy(::Well), also always 1//1)
    @test occupancy(plate1) == 1//1

    # occupancy doesn't fluctuate with well contents -- use a disposable plate, not the shared
    # plate1 fixture (later testsets deposit into plate1's own wells and rely on them starting Empty)
    occ_check_plate = build_location(WP96,"occupancy check plate")
    @test occupancy(occ_check_plate) == 1//1
    deposit!(occ_check_plate[1,1],1u"µL"*rgt"water",0)
    @test occupancy(occ_check_plate) == 1//1
end

@location_kind AmbA [:Tag1,:Tag2] nothing nothing nothing nothing nothing
@location_kind AmbChild Symbol[] nothing nothing nothing nothing nothing
CHESSCore.set_occupancy_cost!(:Tag1,:AmbChild,1//2)
CHESSCore.set_occupancy_cost!(:Tag2,:AmbChild,1//3)

@testset "Ambiguous occupancy rules" begin
    p=CHESSCore.GenericLocation(nothing,"p",AmbA)
    ch=CHESSCore.GenericLocation(nothing,"ch",AmbChild)
    @test_throws AmbiguousOccupancyRuleError CHESSCore.occupancy_cost(p,ch)
end

@testset "Uncommitted locations" begin
    eph=build_location(WP96,"test plate")
    @test !CHESSCore.is_committed(eph)
    @test isnothing(CHESSCore.location_id(eph))
    @test_throws UncommittedLocationError CHESSCore.assert_all_committed(eph)
    # cache()/upload()'s uncommitted-rejection behavior (they now check assert_all_committed
    # before resolving any DB-touching default argument) is exercised in CHESSDatabase's own test
    # suite, since `cache`/`upload` are CHESSDatabase functions, not CHESSCore ones.

    # the check also now walks the subtree, not just the root: a committed-looking root with an
    # uncommitted child is rejected too, instead of silently writing a `nothing` child id
    eph_child=build_location(WP96,"test child")
    @test_throws UncommittedLocationError CHESSCore.assert_all_committed(eph, eph_child)
end

@testset "Environment caching and Unknown" begin
    room=CHESSCore.GenericLocation(nothing,"room",Room)
    shelf=CHESSCore.GenericLocation(nothing,"shelf",Bench)
    CHESSCore.set_occupancy_cost!(:Room,:Bench,1//1)
    move_into!(room,shelf)
    set_attribute!(room,Temperature(20u"°C"))
    @test environment(shelf)[:Temperature] == Temperature(20u"°C")

    set_attribute!(shelf,Temperature(missing)) # explicit clear defers to inherited value
    @test environment(shelf)[:Temperature] == Temperature(20u"°C")

    set_attribute!(shelf,Temperature(CHESSCore.Unknown)) # Unknown propagates/overrides like a real value
    @test CHESSCore.isunknown(CHESSCore.value(environment(shelf)[:Temperature]))

    set_attribute!(room,Temperature(30u"°C")) # invalidation: shelf's Unknown override still wins
    @test CHESSCore.isunknown(CHESSCore.value(environment(shelf)[:Temperature]))
end

@testset "Labware indexing" begin
    @test plate1[1,1] === children(plate1)[1,1]
    @test plate1[5] === children(plate1)[5]
    @test size(plate1) == (8,12)
    @test length(plate1) == 96
    @test length(collect(plate1)) == 96
end

@testset "Location child lookup" begin
    @test dr1["Left"] === l1
    @test dr1["Right"] === r1
    @test_throws ChildNotFoundError dr1["Nope"]

    dup_parent=CHESSCore.GenericLocation(nothing,"dup",BioSpaDrawer)
    dup1=CHESSCore.GenericLocation(nothing,"Left",BioSpaSlot)
    dup2=CHESSCore.GenericLocation(nothing,"Left",BioSpaSlot)
    move_into!(dup_parent,dup1)
    move_into!(dup_parent,dup2)
    @test_throws AmbiguousChildNameError dup_parent["Left"]
    @test length(children_named(dup_parent,"Left")) == 2
end

@location_kind IncubatorModelX Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set([:Temperature]) Set{Function}() Set{Symbol}() true

@testset "Instrument: set_attribute! via any Location; capability gate" begin
    inc=CHESSCore.Instrument(nothing,"Inc X",IncubatorModelX)
    set_attribute!(inc,Temperature(37u"°C")) # any Location can have attributes set -- no instrument-specific mechanism needed
    @test environment(inc)[:Temperature] == Temperature(37u"°C")
    set_attribute!(inc,Humidity(40u"percent")) # not in actuatable_attributes, but that's descriptive-only now -- still succeeds
    @test environment(inc)[:Humidity] == Humidity(40u"percent")
end

@read TestAbsorbance u"percent"
@read TestFluorescence u"percent"

@location_kind CapableInstrumentKind Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set([move_into!,transfer!,set_attribute!,record_read!]) Set{Symbol}() true
@location_kind IncapableInstrumentKind Symbol[] nothing nothing nothing nothing nothing 0//1 0//1 Set{Symbol}() Set{Function}() Set{Symbol}() true

@testset "Capability gate: move_into!/transfer!/set_attribute!/record_read!" begin
    capable=CHESSCore.Instrument(nothing,"Capable",CapableInstrumentKind)
    incapable=CHESSCore.Instrument(nothing,"Incapable",IncapableInstrumentKind)

    parent=GenericLocation(nothing,"gate parent",Room)
    child=GenericLocation(nothing,"gate child",Room)
    @test_nowarn move_into!(parent,child;instrument=capable)
    @test_throws ArgumentError move_into!(parent,GenericLocation(nothing,"gate child 2",Room);instrument=incapable)
    @test_nowarn move_into!(parent,GenericLocation(nothing,"gate child 3",Room)) # instrument=nothing never gates

    @test_nowarn set_attribute!(child,Temperature(20u"°C");instrument=capable)
    @test_throws ArgumentError set_attribute!(child,Temperature(21u"°C");instrument=incapable)

    r=TestAbsorbance(50u"percent")
    @test_nowarn record_read!(child,r;instrument=capable)
    @test_throws ArgumentError record_read!(child,r;instrument=incapable)

    w1=plate1[1,1]
    w2=plate1[1,2]
    deposit!(w1,0.05u"g"*rgt"paba",0)
    @test_nowarn transfer!(w1,w2,0.01u"g";instrument=capable)
    @test_throws ArgumentError transfer!(w1,w2,0.01u"g";instrument=incapable)

    non_instrument=GenericLocation(nothing,"not an instrument",Room)
    @test_throws TypeError set_attribute!(child,Temperature(22u"°C");instrument=non_instrument)
end

@testset "Read/ReadKind: value contract, reads(), record_read!, per-kind filter" begin
    r1 = TestAbsorbance(90u"percent",DateTime(2026,1,1))
    r2 = TestAbsorbance(95u"percent",DateTime(2026,1,2))
    r3 = TestFluorescence(10u"percent")
    r_unknown = TestAbsorbance(CHESSCore.Unknown)
    r_missing = TestAbsorbance(missing)

    @test CHESSCore.value(r1) == 90.0
    @test CHESSCore.quantity(r1) == 90u"percent"
    @test read_kind(r1) === TestAbsorbance
    @test read_unit(r1) == u"percent"
    @test read_time(r1) == DateTime(2026,1,1)
    @test isunknown(CHESSCore.value(r_unknown))
    @test ismissing(CHESSCore.value(r_missing))
    @test isnothing(read_time(r3))

    loc = GenericLocation(nothing,"reads test loc",Room)
    @test isempty(reads(loc))
    record_read!(loc,r2)
    record_read!(loc,r1) # recorded out of chronological order -- reads(loc,kind) must still sort by read_time
    record_read!(loc,r3)
    @test length(reads(loc)) == 3
    absorbance = reads(loc,TestAbsorbance)
    @test absorbance == [r1,r2]
    @test reads(loc,:TestAbsorbance) == absorbance
    @test reads(loc,:TestFluorescence) == [r3]
end

@read TestColorimetric nothing Set(["Positive","Negative"])
@read TestObservation

@testset "Read/ReadKind: qualitative values (constrained and free-text)" begin
    @test is_qualitative(TestColorimetric)
    @test !is_quantitative(TestColorimetric)
    @test isnothing(TestColorimetric.unit)

    pos = TestColorimetric("Positive")
    @test CHESSCore.value(pos) == "Positive"
    @test CHESSCore.quantity(pos) == "Positive" # no unit to attach -- raw value returned
    @test_throws ArgumentError TestColorimetric("Maybe")

    obs = TestObservation("looked a bit cloudy; possible contamination")
    @test CHESSCore.value(obs) == "looked a bit cloudy; possible contamination"

    @test_throws ArgumentError TestColorimetric(50u"percent") # quantitative value into a qualitative kind
    @test_throws ArgumentError TestAbsorbance("Positive") # qualitative value into a quantitative kind

    unk = TestColorimetric(CHESSCore.Unknown)
    @test isunknown(CHESSCore.value(unk))
    ms = TestColorimetric(missing)
    @test ismissing(CHESSCore.value(ms))
end

@reagent HydrochloricAcid "hydrochloric acid" Solid 36.46u"g/mol" 1.0u"g/mL" missing
@reagent SodiumHydroxide "sodium hydroxide" Solid 40.0u"g/mol" 1.0u"g/mL" missing
@reagent PotassiumChloride "potassium chloride" Solid 74.55u"g/mol" 1.0u"g/mL" missing

const Cl⁻=CHESSCore.Chemical("Cl-",-1,35.45u"g/mol")
const Na⁺=CHESSCore.Chemical("Na+",1,22.99u"g/mol")
const K⁺=CHESSCore.Chemical("K+",1,39.10u"g/mol")

set_composition!(HydrochloricAcid,CompositionRule(Dict(H⁺=>1,Cl⁻=>1)))
set_composition!(SodiumHydroxide,CompositionRule(Dict(Na⁺=>1,OH⁻=>1)))
set_composition!(PotassiumChloride,CompositionRule(Dict(K⁺=>1,Cl⁻=>1)))

@testset "Ionic dissociation and pH" begin
    neutral=(0.001u"mol"*HydrochloricAcid)+(0.001u"mol"*SodiumHydroxide)
    @test pH(neutral) ≈ 7.0 atol=1e-6

    acidic=(0.002u"mol"*HydrochloricAcid)+(0.001u"mol"*SodiumHydroxide)
    @test pH(acidic) < 7.0

    basic=(0.001u"mol"*HydrochloricAcid)+(0.002u"mol"*SodiumHydroxide)
    @test pH(basic) > 7.0

    naoh_only=0.001u"mol"*SodiumHydroxide
    @test pH(naoh_only) > 7.0

    kcl=0.01u"mol"*PotassiumChloride
    @test total_concentration(kcl,K⁺) > 0u"mol/L"

    # molecular_weight(x::Reagent) now derives from the registered composition rather than the
    # originally-given stored field, once a composition is registered -- confirms the fix actually
    # changed which number wins (36.458, not the originally-given 36.46), not just that nothing broke
    @test molecular_weight(HydrochloricAcid) ≈ (1.008+35.45)u"g/mol"
    @test !(molecular_weight(HydrochloricAcid) ≈ 36.46u"g/mol")

    @test_throws ArgumentError CompositionRule(Dict(H⁺=>-1))
end

@reagent LiquidHCl "liquid hydrochloric acid" Liquid 36.46u"g/mol" 1.20u"g/mL" missing
set_composition!(LiquidHCl,CompositionRule(Dict(H⁺=>1,Cl⁻=>1)))

@testset "recipe(::Stock) includes liquids; composition reserved for Reagent" begin
    # composition(::Stock) was eliminated -- Recipe now covers this (see below); composition(x) only
    # has a Reagent-level method (-> CompositionRule), confirmed here
    @test !hasmethod(composition,Tuple{Stock})
    @test composition(PotassiumChloride).products == Dict(K⁺=>1,Cl⁻=>1) # reagent-level, unaffected

    # user-reported bug (now via recipe/molar_amount instead of the removed composition(::Stock)):
    # a pure-water Solution used to yield an empty Dict even though water has a (default,
    # non-dissociating) identity Chemical
    water_stock = 100u"mL"*rgt"water"
    r = recipe(water_stock)
    water_chem = CHESSCore.Chemical(name(rgt"water"),0,molecular_weight(rgt"water"))
    expected_moles = uconvert(u"mol", 100u"mL"*density(rgt"water")/molecular_weight(rgt"water"))
    @test molar_amount(r,water_chem) ≈ expected_moles

    # a liquid with a registered dissociation rule contributes correctly to pH/total_concentration
    acid_stock = 10u"mL"*LiquidHCl # Liquid only has a Volume-based `*` constructor, unlike Solid
    @test pH(acid_stock) < 7.0
    @test total_concentration(acid_stock,Cl⁻) > 0u"mol/L"

    # Mixture's recipe is unchanged -- the liquids loop is a no-op for it
    paba_chem = CHESSCore.Chemical(name(rgt"paba"),0,molecular_weight(rgt"paba"))
    expected_paba_moles = uconvert(u"mol",quantity(b)/molecular_weight(rgt"paba"))
    @test molar_amount(recipe(b),paba_chem) ≈ expected_paba_moles

    # Recipe is moles-native: a Chemical with unknown molecular_weight still has a well-defined molar
    # amount (mw-independent), even though mass() for it is missing (genuinely uncomputable) rather
    # than 0. Built directly via Recipe's own construction algebra -- going through a registered
    # Reagent composition isn't possible here, since molecular_weight(x::Reagent) now derives from
    # the sum of *all* its registered products (an earlier plan's fix): a reagent with an unknown-mw
    # product would itself get an unknown derived mw, which would block it from ever being converted
    # to moles in the first place, never reaching Recipe's accumulation at all.
    unknown_mw_chem = CHESSCore.Chemical("mystery ion",1,missing)
    r = 0.001u"mol" * unknown_mw_chem
    @test molar_amount(r,unknown_mw_chem) == 0.001u"mol"
    @test ismissing(mass(r,unknown_mw_chem))
    @test mass(r,H⁺) == 0u"g" # genuinely absent, not unknown -- stays 0, not missing
end

@testset "Formula algebra" begin
    @test (1*Na⁺).composition == Dict(Na⁺=>1)
    @test (Na⁺+Cl⁻).composition == Dict(Na⁺=>1,Cl⁻=>1)
    @test (Na⁺+2*Cl⁻).composition == Dict(Na⁺=>1,Cl⁻=>2)
end

const Mg²⁺=CHESSCore.Chemical("Mg2+",2,24.305u"g/mol")

@reagent_formula MgCl2 "magnesium chloride" Solid (Mg²⁺+2*Cl⁻) missing missing

@testset "reagent_formula derivation" begin
    @test molecular_weight(MgCl2) ≈ (24.305+2*35.45)u"g/mol"
    @test CHESSCore.composition(MgCl2).products == Dict(Mg²⁺=>1,Cl⁻=>2)
end

@testset "Recipe" begin
    stock = 0.01u"mol"*PotassiumChloride
    r = recipe(stock)
    @test mass(r,K⁺) ≈ 0.01u"mol"*molecular_weight(K⁺)
    @test molar_amount(r,K⁺) ≈ 0.01u"mol"
    @test mass(r,Cl⁻) ≈ 0.01u"mol"*molecular_weight(Cl⁻)

    r2 = 5u"g"*Na⁺ + 3u"g"*Cl⁻
    @test mass(r2,Na⁺) == 5u"g"
    r3 = r2 + r2
    @test mass(r3,Na⁺) == 10u"g"
    r4 = 2*r2
    @test mass(r4,Cl⁻) == 6u"g"
end

@testset "reagents(x) rename" begin
    @test reagents(solids(b)) == [rgt"paba"]
    @test rgt"water" in reagents(liquids(a))
end

module AsciiIonLab
using CHESSCore, Unitful
@chemical var"Na+" "Na+" 1 22.99u"g/mol"
@chemical var"Cl-" "Cl-" -1 35.45u"g/mol"
end
CHESSCore.register_lab(AsciiIonLab)

@testset "ASCII-parsable chem_str" begin
    @test chem"Na+" === AsciiIonLab.var"Na+"
    @test chem"Cl-" === AsciiIonLab.var"Cl-"
    f = chem"Na+" + chem"Cl-"
    @test f.composition == Dict(chem"Na+"=>1, chem"Cl-"=>1)
    # the non-macro function form still supports compound expressions (unchanged, still Meta.parse-based)
    @test orgparse("(SMU_UA159)",org_context=[CHESSCore,TestChemOrg]) == org"SMU_UA159"
end

@testset "chem_str ASCII charge-symbol normalization" begin
    # single charge, magnitude 1 -- sign-only candidate resolves immediately
    @test chem"TestNa+" === TestChemOrg.TestNa⁺
    # real charge magnitude (2) must be superscripted -- sign-only candidate ("TestCa⁺") doesn't
    # exist, so the second candidate ("TestCa²⁺") is the one that resolves
    @test chem"TestCa2+" === TestChemOrg.TestCa²⁺
    # a formula digit ("4") immediately preceding the sign, charge magnitude 1 -- must NOT be
    # mistaken for a charge-magnitude digit (i.e. must resolve to TestH2PO4⁻, not TestH2PO⁴⁻)
    @test chem"TestH2PO4-" === TestChemOrg.TestH2PO4⁻
    # a display-name-style spelling with an embedded space before the magnitude -- space is
    # stripped before candidates are generated
    @test chem"TestSO4 2-" === TestChemOrg.TestSO4²⁻
    # no matching candidate (and no direct match) still throws with the existing hint message
    # (chem"..." expands at macro/parse time, so use the runtime chemparse form to catch this)
    @test_throws ArgumentError chemparse("TestNotRegistered")
end

@testset "Reagent value-based equality" begin
    s1 = Solid("paba",137.14u"g/mol",1.35u"g/mL",978)
    s2 = Solid("paba",137.14u"g/mol",1.35u"g/mL",978)
    @test s1 == s2
    @test hash(s1) == hash(s2)
    l1 = Liquid("paba",137.14u"g/mol",1.35u"g/mL",978)
    @test s1 != l1 # same fields, different concrete type -- must stay distinct
    d = Dict(s1=>5u"g")
    @test d[s2] == 5u"g" # Dict lookup succeeds with a separately-constructed-but-equal key
end

@testset "symbol(x) reverse lookup" begin
    # H⁺ is bound under :H⁺, not derivable from name(H⁺)=="H+" -- exactly the gap symbol() fixes
    @test symbol(H⁺) == :H⁺
    @test symbol(H⁺) != Symbol(name(H⁺))
    @test symbol(rgt"water") == :water
    @test symbol(chem"Na+") == Symbol("Na+")
    @test symbol(org"SMU_UA159") == :SMU_UA159

    # show now prints the recoverable symbol, not the display name
    @test sprint(show,H⁺) == "H⁺"
    @test sprint(show,H⁺) != name(H⁺)

    # ephemeral, never-bound values fall back to name(x) instead of erroring
    transient = CHESSCore.Chemical("transient",0,missing)
    @test_throws ArgumentError symbol(transient)
    @test sprint(show,transient) == name(transient)
end

@testset "Interop: DataFrame <-> Stock/Labware round-trips" begin
    # reagent_to_string / string_to_reagent round-trip a registered reagent by symbol, not name
    @test reagent_to_string(rgt"water";reagent_context=[CHESSCore,TestChemOrg]) == "water"
    @test string_to_reagent("water",u"percent";reagent_context=[CHESSCore,TestChemOrg]) == rgt"water"
    # unregistered name falls back to a bare Solid/Liquid with missing properties, with a warning.
    # u"percent" is dimensionless -> the Liquid branch (a %v/v concentration in vc format)
    unreg = @test_logs (:warn,r"not registered") match_mode=:any string_to_reagent("mystery goo",u"percent";reagent_context=[CHESSCore,TestChemOrg])
    @test unreg isa Liquid && ismissing(molecular_weight(unreg))

    # concentration(::Stock,::Solid/::Liquid) relative to quantity(stock)
    conc = concentration(b,rgt"paba") # b = 10u"g"*rgt"paba", a pure-paba Mixture
    @test conc ≈ 100u"percent"
    @test concentration(a,rgt"water") ≈ 100u"percent" # a = 100u"mL"*rgt"water", a pure-water Solution
    @test concentration(b,rgt"iron_nitrate") == 0u"percent" # not present in the stock

    # quantity(::Stock,::Solid/::Liquid), including the "not in stock" zero branches
    @test quantity(b,rgt"paba") ≈ 10u"g"
    @test quantity(b,rgt"iron_nitrate") == 0u"g"
    @test quantity(a,rgt"water") ≈ uconvert(u"µL",100u"mL")
    @test quantity(a,rgt"glycerol") == 0u"µL"

    # all_reagents / reagent_df across a vector of stocks
    @test Set(all_reagents(b)) == Set([rgt"paba"])
    @test Set(all_reagents([a,b])) == Set([rgt"water",rgt"paba"])
    rdf = reagent_df([a,b];reagent_context=[CHESSCore,TestChemOrg])
    @test nrow(rdf) == 2
    @test Set(names(rdf)) == Set(["water","paba"])

    # labware_to_df / df_to_labware round-trip, "q" format -- build_location, not generate_location:
    # this exercises exactly the fix df_to_labware itself relies on (no database needed)
    bottle = build_location(Bottle1L,"df interop test bottle")
    deposit!(bottle.children[1,1],10u"g"*rgt"paba",5)
    df_q,units_q = labware_to_df(bottle,"q";reagent_context=[CHESSCore,TestChemOrg])
    @test df_q.labware[1] == string(kind(bottle).name) # kind-based, not typeof(lw)
    lws_q = df_to_labware(df_q,units_q;reagent_context=[CHESSCore,TestChemOrg])
    @test kind(lws_q[1]) == kind(bottle)
    @test stock(lws_q[1][df_q.well[1]]) == stock(bottle.children[1,1])
    @test !CHESSCore.is_committed(lws_q[1]) # df_to_labware never commits to a database by design

    # "vc" format round-trip on a Solution-derived stock (fits vc's volume/concentration model)
    bottle2 = build_location(Bottle1L,"df interop test bottle vc")
    deposit!(bottle2.children[1,1],100u"mL"*rgt"water",5)
    df_vc,units_vc = labware_to_df(bottle2,"vc";reagent_context=[CHESSCore,TestChemOrg])
    lws_vc = df_to_labware(df_vc,units_vc;reagent_context=[CHESSCore,TestChemOrg])
    @test stock(lws_vc[1][df_vc.well[1]]) == stock(bottle2.children[1,1])
    @test !CHESSCore.is_committed(lws_vc[1])

    # "vc" format also works on a Mixture-derived stock (cross-dimension branch: mass/volume)
    bottle3 = build_location(Bottle1L,"df interop test bottle vc mixture")
    deposit!(bottle3.children[1,1],10u"g"*rgt"paba",5)
    df_vc3,units_vc3 = labware_to_df(bottle3,"vc";reagent_context=[CHESSCore,TestChemOrg])
    @test units_vc3[1,"paba"] == "%"
    lws_vc3 = df_to_labware(df_vc3,units_vc3;reagent_context=[CHESSCore,TestChemOrg])
    @test stock(lws_vc3[1][df_vc3.well[1]]) == stock(bottle3.children[1,1])

    # df_to_stock / stock_to_df auto-detect format via the "volume" column (stock columns only --
    # df_to_labware strips the labware/name/well columns before calling df_to_stock internally)
    vc_only = select(df_vc,Not([:labware,:name,:well]))
    @test df_to_stock(vc_only,units_vc;reagent_context=[CHESSCore,TestChemOrg]) isa Vector{<:Stock}
    q_only = select(df_q,Not([:labware,:name,:well]))
    @test df_to_stock(q_only,units_q;reagent_context=[CHESSCore,TestChemOrg]) isa Vector{<:Stock}

    # empty-input branches: no rows in, no rows/columns out
    @test df_to_stock(DataFrame(),DataFrame()) == Stock[]
    @test stock_to_df(Stock[]) == (DataFrame(),DataFrame())
    @test df_to_labware(DataFrame(),DataFrame()) == Labware[]

    # stock_to_df rejects an unknown format name
    @test_throws ErrorException stock_to_df([b],"bogus_format")

    # vc_to_stock/q_to_stock give a clear error (not a deep MethodError) for dimensionally-mismatched
    # hand-authored units
    vc_bad = DataFrame(volume=[10.0],paba=[1.0])
    units_bad = DataFrame(volume=["g"],paba=["g/µL"])
    @test_throws ErrorException vc_to_stock(vc_bad,units_bad;reagent_context=[CHESSCore,TestChemOrg])

    q_bad = DataFrame(paba=[1.0])
    units_q_bad = DataFrame(paba=["g/µL"]) # a concentration-style unit in a quantity-format table
    @test_throws ErrorException q_to_stock(q_bad,units_q_bad;reagent_context=[CHESSCore,TestChemOrg])
end

@testset "Exception display" begin
    @test occursin("Well Capacity Error",sprint(showerror,WellCapacityError(10u"mL",5u"mL")))
    @test occursin("Mixing Error",sprint(showerror,MixingError(rgt"paba","too little")))
    @test occursin("Already-Located-In Error",sprint(showerror,AlreadyLocatedInError()))
    @test occursin("Occupancy Error",sprint(showerror,OccupancyError(3//2,"over capacity")))
    @test occursin("Locked Location Error",sprint(showerror,LockedLocationError(jensen_lab)))
    @test occursin("Fixed Membership Error",sprint(showerror,FixedMembershipError(plate1,"fixed slots")))
    @test occursin("Ambiguous Occupancy Rule Error",sprint(showerror,AmbiguousOccupancyRuleError(:A,:B,[:r1,:r2])))
    @test occursin("Child Not Found Error",sprint(showerror,ChildNotFoundError(jensen_lab,"nope")))
    @test occursin("Ambiguous Child Name Error",sprint(showerror,AmbiguousChildNameError(jensen_lab,"dup",[l1,l2])))
    @test occursin("Uncommitted Location Error",sprint(showerror,UncommittedLocationError(build_location(WP96,"x"))))
end

@testset "Labware misc accessors" begin
    @test CHESSCore.childtype(plate1) === Well # WP96's :Well200 socket
    @test CHESSCore.wells(plate1) == children(plate1)
    @test CHESSCore.parent_cost(plate1) == kind(plate1).default_parent_cost # no Labware-specific override -- purely kind-data-driven
    @test collect(eachindex(plate1)) == collect(eachindex(children(plate1)))
end

@testset "stock() is Well-only, no misleading Location fallback" begin
    @test_throws MethodError stock(plate1) # Labware can't hold a Stock at all
    generic = GenericLocation(nothing,"generic loc",Room)
    @test_throws MethodError stock(generic)
end

@testset "Stock equality, hashing, membership, and display" begin
    # ==/hash contract: hash must agree with the existing a==a+Empty() identity test
    @test a == a+Empty()
    @test hash(a) == hash(a+Empty())
    @test hash(a) == hash(a) # trivially reflexive, sanity check

    # isapprox: same reagents/organisms -> true; differing keys -> false
    @test isapprox(a,a)
    @test !isapprox(a,b) # different reagent sets entirely
    close_a = 99.9999999999u"mL"*rgt"water"
    @test isapprox(a,close_a;atol=1e-6u"mL")
    @test !isapprox(a,close_a;atol=0u"mL",rtol=0)

    # membership
    @test rgt"paba" in b
    @test !(rgt"iron_nitrate" in b)
    @test rgt"water" in a
    @test !(rgt"glycerol" in a)
    @test org"SMU_UA159" in e
    @test !(org"SSA_SK36" in e)

    # reagent_display(::Culture) -- currently-untested three-tuple path with organisms populated
    out_solids,out_liquids,out_organisms = reagent_display(e)
    @test isempty(out_solids) && isempty(out_liquids)
    @test out_organisms == [org"SMU_UA159"]

    # show variants not covered by the Mixture-only check in "reagent_display / show consolidation"
    for x in (a, e, Empty())
        str = sprint(show, MIME"text/plain"(), x)
        @test !isempty(str)
    end
    @test !isempty(sprint(show,a)) # plain, non-MIME Base.show(io::IO,s::Stock)
end

@testset "Chemical/Reagent parsing edge cases" begin
    # single bare Module (not a Vector) -- lookup_named_value(unitmod::Module, ex::Symbol, check).
    # Note: chemparse uses plain Meta.parse, unlike the @chem_str macro's special ASCII-name handling
    # (see its docstring) -- so "Na+"/"Cl-" (valid chem_str names, invalid Julia syntax) can't be used
    # here; H⁺/OH⁻ (unicode identifiers, valid plain Julia syntax) are the right fixtures instead.
    @test chemparse("H⁺";chem_context=CHESSCore) === H⁺

    # a string-encoded compound expression -- exercises both the :call-head recursive branch and
    # the bare-Number-literal overload (the `2` itself routes through lookup_named_value too)
    @test chemparse("2*H⁺";chem_context=CHESSCore).composition == (2*H⁺).composition

    # hint branch 1: symbol found in a globally-registered lab module, but not in the given context
    err1 = try
        reagentparse("water";reagent_context=[CHESSCore])
        nothing
    catch e
        e
    end
    @test err1 isa ArgumentError
    @test occursin("globally registered",sprint(showerror,err1))

    # hint branch 2: not found anywhere, but close enough to something for a Levenshtein suggestion
    err2 = try
        reagentparse("wter";reagent_context=[CHESSCore,TestChemOrg])
        nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
    @test occursin("Did you mean",sprint(showerror,err2))

    # no-suggestion sub-branch: nothing close enough to match
    @test_throws ArgumentError reagentparse("zzzznotreal";reagent_context=[CHESSCore,TestChemOrg])

    # Chemical's 2-arg convenience constructor (charge defaults to 0)
    @test Chemical("standalone name",12.0u"g/mol") == Chemical("standalone name",0,12.0u"g/mol")

    @test charge(Cl⁻) == -1

    # composition(::Reagent)'s default-identity fallback -- rgt"water" has no registered composition
    @test composition(rgt"water").products == Dict(CHESSCore.Chemical(name(rgt"water"),0,molecular_weight(rgt"water"))=>1)

    # commutative Chemical/Formula operator overloads -- Formula has no custom == (falls back to
    # identity), so compare .composition Dicts directly, matching the existing "Formula algebra"
    # testset's style
    @test (Cl⁻*2).composition == (2*Cl⁻).composition
    @test (Cl⁻ + (Na⁺+Cl⁻)).composition == ((Na⁺+Cl⁻) + Cl⁻).composition

    # convert(::DensityUnits,::Molarity,...) / convert(::MolarityUnits,::Density,...) -- were dead
    # code (the signature took a full Quantity for `y` but the body called uconvert(y,...), which
    # requires bare Units), fixed to take Units like the MassUnits/AmountUnits pair does
    @test convert(u"g/mL",1u"mol/L",rgt"paba") ≈ uconvert(u"g/mL",1u"mol/L"*molecular_weight(rgt"paba"))
    @test convert(u"mol/L",1u"g/mL",rgt"paba") ≈ uconvert(u"mol/L",1u"g/mL"/molecular_weight(rgt"paba"))
end

@testset "Location primitives: lock/activity/re-parenting" begin
    # lock!/unlock!/toggle_lock! directly, on a standalone (non-shared) fixture
    standalone = build_location(Room,"lock test room")
    @test !is_locked(standalone)
    lock!(standalone)
    @test is_locked(standalone)
    unlock!(standalone)
    @test !is_locked(standalone)
    toggle_lock!(standalone)
    @test is_locked(standalone)
    toggle_lock!(standalone)
    @test !is_locked(standalone)

    # activate!/deactivate!/toggle_activity! directly
    @test is_active(standalone)
    deactivate!(standalone)
    @test !is_active(standalone)
    activate!(standalone)
    @test is_active(standalone)
    toggle_activity!(standalone)
    @test !is_active(standalone)
    toggle_activity!(standalone)
    @test is_active(standalone)

    # re-parenting: move_into! removes the child from its OLD parent, not just adds it to the new one
    parentA = build_location(Room,"parent A")
    parentB = build_location(Room,"parent B")
    child = build_location(Room,"reparented child")
    move_into!(parentA,child)
    @test child in children(parentA)
    @test CHESSCore.parent(child) === parentA
    move_into!(parentB,child)
    @test child ∉ children(parentA)
    @test child in children(parentB)
    @test CHESSCore.parent(child) === parentB

    # add_to!(::Nothing,...) directly -- makes a location rootless
    CHESSCore.add_to!(nothing,child)
    @test CHESSCore.parent(child) === nothing

    # softequal's type-mismatch branch (existing tests only compare same-typed locations)
    @test !CHESSCore.softequal(build_location(Room,"x"),build_location(WP96,"y"))
    @test CHESSCore.softequal(nothing,nothing)

    # ancestors(...;rev=true) -- read-only against the shared core_fixtures.jl tree
    real_well = children(plate1)[1,1]
    @test ancestors(real_well;rev=true) == reverse(ancestors(real_well))

    # get_all_within -- plate1 (96 wells) is already moved into main_room, itself in jensen_lab
    @test length(get_all_within(jensen_lab,Well)) == 96

    # Nothing-argument defensive overloads (root locations have no parent)
    @test location_id(nothing) === nothing
    @test is_active(nothing) == false
    @test is_locked(nothing) == false
end

@testset "Organism accessors and display" begin
    @test genus(org"SMU_UA159") == "Streptococcus"
    @test species(org"SMU_UA159") == "mutans"
    @test strain(org"SMU_UA159") == "UA159"
    @test name(org"SMU_UA159") == "Streptococcus mutans UA159"

    # ad hoc, unregistered Organism -- show falls back to name() via the ArgumentError-catch branch,
    # mirroring the existing Reagent/Chemical show-fallback tests in "symbol(x) reverse lookup"
    transient_org = Organism("Genus","species","strain")
    @test_throws ArgumentError symbol(transient_org)
    @test sprint(show,transient_org) == name(transient_org)
end

@testset "Detailed MIME\"text/plain\" Location reports" begin
    # compact show is untouched -- still just the name
    @test sprint(show,jensen_lab) == "Jensen Lab"

    # GenericLocation: jensen_lab has children and inherited+own attributes
    generic_report = sprint(show,MIME("text/plain"),jensen_lab)
    @test occursin("Jensen Lab",generic_report)
    @test occursin("Lab",generic_report)
    @test occursin("Children:",generic_report)
    @test occursin("Attributes:",generic_report)
    @test occursin("Temperature",generic_report)
    @test occursin("Room: 3",generic_report) # 3 direct Room children (main/culture/robot)

    # Labware: plate1 has 96 wells -- must summarize, never enumerate every well's own name
    labware_report = sprint(show,MIME("text/plain"),plate1)
    @test occursin("Labware:",labware_report)
    @test occursin("Children:",labware_report)
    @test occursin("96 total",labware_report)
    @test !occursin(name(children(plate1)[1,1]),labware_report)

    # Well: delegates to Stock's own detailed display
    well = children(plate1)[1,1]
    deposit!(well,1u"µL"*rgt"water",0)
    well_report = sprint(show,MIME("text/plain"),well)
    @test occursin("Well:",well_report)
    @test occursin("capacity",well_report)
    @test occursin("water",well_report) # delegated Stock report shows its reagent table

    # Instrument: capability data from kind(x), plus a read grouped-by-kind/most-recent-few summary
    inst = CHESSCore.Instrument(nothing,"Test Incubator",IncubatorModelX)
    record_read!(inst,read"TestpH"("5.0",DateTime(2024,1,1)))
    record_read!(inst,read"TestpH"("6.0",DateTime(2024,1,2)))
    record_read!(inst,read"TestpH"("7.0",DateTime(2024,1,3)))
    record_read!(inst,read"TestpH"("8.0",DateTime(2024,1,4)))
    inst_report = sprint(show,MIME("text/plain"),inst)
    @test occursin("Instrument capabilities:",inst_report)
    @test occursin("Temperature",inst_report) # actuatable_attributes
    @test occursin("Reads:",inst_report)
    @test occursin("TestpH",inst_report)
    @test occursin("+1 more",inst_report) # 4 reads, nshow=3 -> "+1 more"
end

function _is_json_safe(x)
    x isa Union{Nothing,AbstractString,Real,Bool} && return true
    x isa AbstractDict && return all(k -> k isa AbstractString, keys(x)) && all(_is_json_safe, values(x))
    x isa AbstractVector && return all(_is_json_safe, x)
    return false
end

@testset "Location <-> Dict interchange" begin
    # Stock <-> Dict: Mixture, Solution, Culture (organisms + solids + liquids)
    culture = (a/10) + e # Solution/10 + Culture -> Culture with both a liquid and an organism
    for s in (a, b, culture)
        d = stock_to_dict(s; reagent_context=[CHESSCore,TestChemOrg])
        @test _is_json_safe(d)
        @test dict_to_stock(d; reagent_context=[CHESSCore,TestChemOrg]) == s
    end

    # Attribute <-> Dict, including missing/Unknown sentinel states
    attr = Temperature(20u"°C")
    @test dict_to_attribute(attribute_to_dict(attr)) == attr
    attr_missing = Temperature(missing)
    d_missing = attribute_to_dict(attr_missing)
    @test d_missing["state"] == "missing" && ismissing(CHESSCore.value(dict_to_attribute(d_missing)))
    attr_unknown = Temperature(Unknown)
    d_unknown = attribute_to_dict(attr_unknown)
    @test d_unknown["state"] == "unknown" && isunknown(CHESSCore.value(dict_to_attribute(d_unknown)))

    # Read <-> Dict: quantitative, qualitative, and missing/Unknown states
    r_quant = TestAbsorbance(50u"percent",DateTime(2024,1,1))
    @test dict_to_read(read_to_dict(r_quant)) == r_quant
    r_qual = read"TestpH"("7.0",DateTime(2024,1,2))
    @test dict_to_read(read_to_dict(r_qual)) == r_qual
    r_missing = TestAbsorbance(missing)
    d_r_missing = read_to_dict(r_missing)
    @test d_r_missing["state"] == "missing" && ismissing(CHESSCore.value(dict_to_read(d_r_missing)))
    r_unknown = TestAbsorbance(Unknown)
    d_r_unknown = read_to_dict(r_unknown)
    @test d_r_unknown["state"] == "unknown" && isunknown(CHESSCore.value(dict_to_read(d_r_unknown)))

    # Location <-> Dict: GenericLocation tree with nested children + attributes + reads
    root = CHESSCore.GenericLocation(nothing,"interchange root",Room)
    child = CHESSCore.GenericLocation(nothing,"interchange child",Bench)
    move_into!(root,child)
    set_attribute!(root,Temperature(22u"°C"))
    set_attribute!(child,Humidity(30u"percent")) # a `missing`-valued Attribute makes Attribute's own
    # == return `missing` (not `false`) -- a pre-existing quirk unrelated to this interchange -- which
    # would make softequal itself throw below; the missing/Unknown states are already covered directly
    # via attribute_to_dict/dict_to_attribute above, so use a concrete value here.
    record_read!(root,r_quant)
    d_root = location_to_dict(root)
    @test _is_json_safe(d_root)
    root2 = dict_to_location(d_root)
    @test CHESSCore.softequal(root,root2)

    # Instrument, with a locked child to exercise the deferred is_locked application
    inst2 = CHESSCore.Instrument(nothing,"interchange instrument",IncubatorModelX)
    locked_child = CHESSCore.GenericLocation(nothing,"locked child",Room)
    move_into!(inst2,locked_child,true) # lock=true
    record_read!(inst2,r_qual)
    d_inst = location_to_dict(inst2)
    @test d_inst["actuatable_attributes"] == ["Temperature"]
    inst2b = dict_to_location(d_inst)
    @test CHESSCore.softequal(inst2,inst2b)
    @test is_locked(children(inst2b)[1]) # the deferred-lock reconstruction actually took effect

    # standalone Well (not attached to any Labware)
    standalone_well = CHESSCore.Well(nothing,"standalone",Well1000000;stock=b,cost=3)
    d_well = location_to_dict(standalone_well; reagent_context=[CHESSCore,TestChemOrg])
    @test _is_json_safe(d_well)
    well2 = dict_to_location(d_well; reagent_context=[CHESSCore,TestChemOrg])
    @test CHESSCore.softequal(standalone_well,well2)

    # Labware: an entire plate + its wells round-trips as one unit (the explicit non-flat exception)
    deposit!(plate1[1,1],1u"µL"*rgt"water",0)
    d_plate = location_to_dict(plate1; reagent_context=[CHESSCore,TestChemOrg])
    @test _is_json_safe(d_plate)
    @test length(d_plate["wells"]) == shape(plate1)[1] && length(d_plate["wells"][1]) == shape(plate1)[2]
    plate2 = dict_to_location(d_plate; reagent_context=[CHESSCore,TestChemOrg])
    @test kind(plate2) === kind(plate1)
    @test name(plate2) == name(plate1)
    for row in 1:shape(plate1)[1], col in 1:shape(plate1)[2]
        @test stock(plate2[row,col]) == stock(plate1[row,col])
        @test cost(plate2[row,col]) == cost(plate1[row,col])
    end
end
