using CHESSCore, CHESSLabConstants, Test, Unitful

include("empirical_measurements.jl")

@testset "CHESSLabConstants loads and registers as a lab module" begin
    @test isdefined(CHESSLabConstants, :get_mw_density)
    @test :get_mw_density in names(CHESSLabConstants) # exported
    @test :get_json_from_url ∉ names(CHESSLabConstants) # internal, not exported
    @test CHESSLabConstants in CHESSCore.labmodules
end

@testset "Reagents resolve" begin
    @test CHESSLabConstants.water isa CHESSCore.Liquid
    @test CHESSLabConstants.glucose isa CHESSCore.Solid
    @test CHESSCore.molecular_weight(CHESSLabConstants.water) == 18.015u"g/mol"
    @test ismissing(CHESSCore.molecular_weight(CHESSLabConstants.yeast_extract))
end

@testset "Organisms resolve" begin
    @test CHESSLabConstants.SMU_UA159 isa CHESSCore.Organism
    @test CHESSCore.genus(CHESSLabConstants.SMU_UA159) == "Streptococcus"
end

@testset "Location kinds resolve, categories/occupancy translated" begin
    @test CHESSLabConstants.WP96 isa CHESSCore.LocationKind
    @test :WellPlate in CHESSLabConstants.WP96.categories
    @test CHESSCore.concretetype(CHESSLabConstants.WP96) == CHESSCore.Labware
    @test CHESSLabConstants.Nimbus.is_instrument
    @test CHESSCore.is_capable(CHESSLabConstants.Nimbus)
    @test CHESSCore.concretetype(CHESSLabConstants.Nimbus) == CHESSCore.Labware # is_instrument no longer overrides structure -- Nimbus has real shape data ((2,4)), previously silently discarded
    @test CHESSCore.occupancy_rules[(:CobraSlot,:WellPlate)] == 1//1
end

@testset "Attribute/Read kind registry resolves and reaches CHESSCore's central registries" begin
    @test CHESSLabConstants.Temperature isa CHESSCore.AttributeKind
    @test CHESSLabConstants.Humidity isa CHESSCore.AttributeKind
    @test CHESSLabConstants.CO2 isa CHESSCore.AttributeKind
    @test CHESSLabConstants.Pressure isa CHESSCore.AttributeKind
    @test CHESSLabConstants.LinearShaking isa CHESSCore.AttributeKind

    @test CHESSLabConstants.Absorbance isa CHESSCore.ReadKind
    @test CHESSLabConstants.Fluorescence isa CHESSCore.ReadKind
    @test CHESSCore.is_quantitative(CHESSLabConstants.Absorbance)
    @test CHESSCore.is_quantitative(CHESSLabConstants.Fluorescence)

    @test :Temperature in keys(CHESSCore.attribute_kinds)
    @test :CO2 in keys(CHESSCore.attribute_kinds)
    @test :Absorbance in keys(CHESSCore.read_kinds)
    @test :Fluorescence in keys(CHESSCore.read_kinds)

    @test CHESSLabConstants.Temperature(20u"°C") isa CHESSCore.Attribute
    @test CHESSLabConstants.Absorbance(0.5u"OD") isa CHESSCore.Read

    # @attribute/@read no longer export -- attr"..."/read"..." are the collision-safe lookup instead
    @test !(:Temperature in names(CHESSLabConstants))
    @test !(:Absorbance in names(CHESSLabConstants))
    @test attr"Temperature" === CHESSLabConstants.Temperature
    @test read"Absorbance" === CHESSLabConstants.Absorbance
end

@testset "Instrument performable_operations wired up correctly" begin
    @test CHESSLabConstants.Freezer.performable_operations == Set([CHESSCore.set_attribute!])
    @test :Incubator in CHESSLabConstants.Freezer.categories
    @test CHESSLabConstants.Freezer.actuatable_attributes == Set([:Temperature])

    @test CHESSLabConstants.Autoclave.actuatable_attributes == Set([:Temperature,:Pressure])

    @test CHESSLabConstants.BioSpa.performable_operations == Set([CHESSCore.move_into!,CHESSCore.set_attribute!])
    @test :Incubator in CHESSLabConstants.BioSpa.categories
    @test CHESSLabConstants.BioSpa.actuatable_attributes == Set([:Temperature,:Humidity,:CO2,:LinearShaking])

    @test CHESSLabConstants.Epoch2.performable_operations == Set([CHESSCore.record_read!])
    @test CHESSLabConstants.Epoch2.readable_types == Set([:Absorbance,:Fluorescence])
    @test CHESSLabConstants.Cobra.performable_operations == Set([CHESSCore.transfer!])
    @test isempty(CHESSLabConstants.Cobra.actuatable_attributes) # no attribute kinds defined for liquid handlers yet

    @test CHESSLabConstants.PlateCrane.performable_operations == Set([CHESSCore.move_into!])
    @test CHESSCore.transfer! ∉ CHESSLabConstants.PlateCrane.performable_operations

    @test !CHESSLabConstants.LC3.is_instrument
    @test CHESSCore.concretetype(CHESSLabConstants.LC3) == CHESSCore.Labware

    @test CHESSLabConstants.Panopticon.is_instrument
    @test :Incubator in CHESSLabConstants.Panopticon.categories
    @test CHESSLabConstants.Panopticon.performable_operations == Set([CHESSCore.set_attribute!])
end

@testset "Standard stocks compile and compose" begin
    @test CHESSLabConstants.thy_350mL isa CHESSCore.Stock
    @test CHESSLabConstants.cdm_glucose_500mL isa CHESSCore.Stock
    @test CHESSLabConstants.lb_agar_1000mL isa CHESSCore.Stock

    # standard_stocks no longer exports recipes -- stock"..." is the collision-safe lookup instead
    @test !(:thy_350mL in names(CHESSLabConstants))
    @test !(:cdm_glucose_500mL in names(CHESSLabConstants))
    @test stock"thy_350mL" === CHESSLabConstants.thy_350mL
    @test stock"cdm_glucose_500mL" === CHESSLabConstants.cdm_glucose_500mL
end

@testset "registry_summary picks up CHESSLabConstants via labmodules" begin
    summary = CHESSCore.registry_summary()

    @test any(r -> r.name === :water && r.module_ === CHESSLabConstants, summary.reagents)
    @test any(c -> c.name === Symbol("Na⁺") && c.module_ === CHESSLabConstants, summary.chemicals)
    @test any(s -> s.name === :thy_350mL && s.module_ === CHESSLabConstants, summary.stocks)
    @test any(o -> o.name === :SMU_UA159 && o.genus == "Streptococcus", summary.organisms)
    @test any(l -> l.name === :WP96, summary.locations)
    @test any(a -> a.name === :Temperature && a.unit == u"°C", summary.attributes)
    @test any(r -> r.name === :Absorbance, summary.reads)
end

@testset "register_reagent!/register_organism! author-time tools (cache hits, no network)" begin
    CHESSLabConstants._cache_reagent!("boric_acid","Boric Acid",CHESSCore.Solid,61.84,1.435,7628)
    line = CHESSLabConstants.register_reagent!(CHESSCore.Solid,"boric_acid","Boric Acid",7628)
    @test line == "@reagent boric_acid \"Boric Acid\" Solid 61.84u\"g/mol\" 1.435u\"g/mL\" 7628"

    CHESSLabConstants._cache_organism!("SMU_UA159","Streptococcus","mutans","UA159",missing,"")
    orgline = CHESSLabConstants.register_organism!("SMU_UA159","Streptococcus","mutans","UA159")
    @test orgline == "@organism SMU_UA159 \"Streptococcus\" \"mutans\" \"UA159\""
end

@testset "register_chemical! author-time tool (cache hit, no network)" begin
    CHESSLabConstants._cache_chemical!("Na⁺","Na+",1,22.9897693,923)
    line = CHESSLabConstants.register_chemical!("Na⁺","Na+",1,923)
    @test line == "@chemical Na⁺ \"Na+\" 1 22.9897693u\"g/mol\""
end

@testset "Dissociation chemistry: derived molecular weights, hydrates, recipe/total_concentration" begin
    # copper_sulfate is the pentahydrate (fixed 2026-08-14 -- see solids.jl/electrolytes.jl), so its
    # derived weight includes 5 waters of hydration, not the anhydrous salt's 159.61
    @test CHESSCore.molecular_weight(CHESSLabConstants.copper_sulfate) ≈ 249.69u"g/mol" atol=0.01u"g/mol"

    # hydrate: waters of hydration keep the derived weight at the hydrate value, not the anhydrous one
    @test CHESSCore.molecular_weight(CHESSLabConstants.calcium_chloride) ≈ 147.01u"g/mol" atol=0.01u"g/mol"

    # pre-existing data bug in the ported PubChem cache (NaCl stored as 214.25u"g/mol", matching the
    # wrong CID it was linked to -- since fixed in solids.jl) is masked by composition-derivation,
    # which takes precedence over the stored field regardless
    @test CHESSCore.molecular_weight(CHESSLabConstants.sodium_chloride) ≈ 58.44u"g/mol" atol=0.01u"g/mol"

    # recipe()/total_concentration() see the real ionic composition
    stock = 1u"mol" * CHESSLabConstants.calcium_chloride
    r = CHESSCore.recipe(stock)
    @test CHESSCore.molar_amount(r,CHESSLabConstants.Ca²⁺) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.molar_amount(r,CHESSLabConstants.Cl⁻) ≈ 2u"mol" atol=1e-6u"mol"

    # potassium chloride: simple 1:1 strong electrolyte, no acid/base equilibrium
    @test CHESSCore.molecular_weight(CHESSLabConstants.potassium_chloride) ≈ 74.555u"g/mol" atol=0.01u"g/mol"
    kcl_stock = 1u"mol" * CHESSLabConstants.potassium_chloride
    kcl_r = CHESSCore.recipe(kcl_stock)
    @test CHESSCore.molar_amount(kcl_r,CHESSLabConstants.K⁺) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.molar_amount(kcl_r,CHESSLabConstants.Cl⁻) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.acid_base_system(CHESSLabConstants.potassium_chloride) === nothing
end

@testset "Acid/base equilibrium: cysteine and lysine are HCl salts, not free zwitterions" begin
    # cysteine: L-Cysteine hydrochloride monohydrate (Thermo Fisher BP376, PubChem CID 23462)
    @test CHESSCore.molecular_weight(CHESSLabConstants.cysteine) ≈ 175.63u"g/mol" atol=0.01u"g/mol"
    cys_r = CHESSCore.recipe(1u"mol"*CHESSLabConstants.cysteine)
    @test CHESSCore.molar_amount(cys_r,CHESSLabConstants.Cl⁻) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.molar_amount(cys_r,CHESSLabConstants.H2O) ≈ 1u"mol" atol=1e-6u"mol"
    cys_sys = CHESSCore.acid_base_system(CHESSLabConstants.cysteine)
    @test cys_sys.pKa == [1.96,8.3,10.28] # unchanged acid/base chemistry

    # lysine: L-Lysine monohydrochloride (Sigma/Thermo L5626, PubChem CID 69568), anhydrous
    @test CHESSCore.molecular_weight(CHESSLabConstants.lysine) ≈ 182.65u"g/mol" atol=0.01u"g/mol"
    lys_r = CHESSCore.recipe(1u"mol"*CHESSLabConstants.lysine)
    @test CHESSCore.molar_amount(lys_r,CHESSLabConstants.Cl⁻) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.molar_amount(lys_r,CHESSLabConstants.H2O) == 0u"mol" # anhydrous, unlike cysteine's monohydrate
    lys_sys = CHESSCore.acid_base_system(CHESSLabConstants.lysine)
    @test lys_sys.pKa == [2.18,8.95,10.5]
end

@testset "Acid/base equilibrium: phosphate/carbonate pKa data" begin
    # equimolar mono/dibasic potassium phosphate -> pH ≈ pKa2 (textbook Henderson-Hasselbalch check),
    # using the real registered lab reagents (not synthetic test doubles)
    buffer = (0.1u"mol"*CHESSLabConstants.potassium_phosphate_mono) +
             (0.1u"mol"*CHESSLabConstants.potassium_phosphate_di) +
             (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(buffer;ionic_strength_correction=false) ≈ 7.198 atol=1e-3

    results = CHESSCore.speciation(buffer;ionic_strength_correction=false)
    @test length(results) == 1
    @test results[1].system.species == [CHESSLabConstants.H3PO4,CHESSLabConstants.H2PO4⁻,CHESSLabConstants.HPO4²⁻,CHESSLabConstants.PO4³⁻]

    # sodium phosphate salts share the *same* AcidBaseSystem as the potassium salts (deduplication
    # across reagents that differ only in counter-ion)
    na_buffer = (0.1u"mol"*CHESSLabConstants.sodium_phosphate_mono) +
                (0.1u"mol"*CHESSLabConstants.sodium_phosphate_di) +
                (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(na_buffer;ionic_strength_correction=false) ≈ 7.198 atol=1e-3
    @test CHESSCore.acid_base_system(CHESSLabConstants.potassium_phosphate_mono) == CHESSCore.acid_base_system(CHESSLabConstants.sodium_phosphate_mono)

    # sodium carbonate/bicarbonate share the carbonic acid system
    carb_buffer = (0.05u"mol"*CHESSLabConstants.sodium_bicarbonate) +
                  (0.05u"mol"*CHESSLabConstants.sodium_carbonate) +
                  (1.0u"L"*CHESSLabConstants.water)
    # atol is looser here than the phosphate/pKa2 check above -- at pH~10.3, [OH-] (~2e-4 M) is no
    # longer negligible next to this buffer's 0.05 M concentration, so the full charge-balance solver
    # (which accounts for water autoionization) correctly deviates slightly from naive HH
    @test CHESSCore.pH(carb_buffer;ionic_strength_correction=false) ≈ 10.329 atol=0.01

    # real standard media recipes: smoke test -- must produce a sane, finite, in-range pH now that
    # their phosphate/bicarbonate buffering ingredients have real equilibrium data, not NaN/error
    for medium in (CHESSLabConstants.cdm_glucose_500mL, CHESSLabConstants.thy_350mL, CHESSLabConstants.atcc_thy_1000mL)
        p = CHESSCore.pH(medium)
        @test isfinite(p)
        @test 4.0 < p < 10.0
    end
end

@testset "Acid/base equilibrium: acetic acid" begin
    sys = CHESSCore.acid_base_system(CHESSLabConstants.acetic_acid)
    @test sys isa AcidBaseSystem
    @test sys.pKa == [4.76]
    @test sys.species[2] == CHESSLabConstants.OAc⁻ # reuses the existing ion, not a new one

    # acetic_acid is a Liquid -- constructed by volume, like LiquidHCl in CHESSCore's own test suite
    vol = uconvert(u"mL",0.1u"mol"*CHESSCore.molecular_weight(CHESSLabConstants.acetic_acid)/CHESSCore.density(CHESSLabConstants.acetic_acid))
    stock = (vol*CHESSLabConstants.acetic_acid) + (1.0u"L"*CHESSLabConstants.water)
    Ka = 10.0^(-4.76)
    # total stock volume is 1L(water) + the acid's own ~5.7mL, not exactly 1L -- use the real
    # volume_estimate (what pH(::Stock) itself divides by) rather than assuming a round 0.1M
    C = ustrip(uconvert(u"mol/L",0.1u"mol"/CHESSCore.volume_estimate(stock)))
    x = (-Ka+sqrt(Ka^2+4*Ka*C))/2 # independent closed-form quadratic solution
    expected_pH = -log10(x)
    @test CHESSCore.pH(stock;ionic_strength_correction=false) ≈ expected_pH atol=1e-6

    # sodium acetate salts share the same AcidBaseSystem instance as acetic_acid (regression test
    # for a real bug: OAc⁻ contributed by these salts was previously treated as an inert strong ion
    # instead of the genuine weak base it is, found while diagnosing a reported pH discrepancy)
    @test CHESSCore.acid_base_system(CHESSLabConstants.sodium_acetate_anhydrous) == sys
    @test CHESSCore.acid_base_system(CHESSLabConstants.sodium_acetate_trihydrate) == sys

    acetate_stock = (0.1u"mol"*CHESSLabConstants.sodium_acetate_anhydrous) + (1.0u"L"*CHESSLabConstants.water)
    acetate_families,_ = CHESSCore._analytical_species(acetate_stock)
    @test length(acetate_families) == 1 # OAc⁻ now recognized as a family member, not a strong ion
    @test CHESSCore.pH(acetate_stock;ionic_strength_correction=false) > 7.0 # a weak base, genuinely basic
end

@testset "Acid/base equilibrium: lactic_acid is the 85% w/w solution (Sigma W261114), not pure acid" begin
    # molecular_weight is purity-adjusted (90.08/0.85) so mass/MW yields moles of *real* lactic acid
    # per gram of the 85% product actually weighed out -- regression test for a real reported pH
    # discrepancy (carbon_sources_20x stock, predicted 4.94 vs measured 10.38)
    @test CHESSCore.molecular_weight(CHESSLabConstants.lactic_acid) ≈ 105.976u"g/mol" atol=0.001u"g/mol"

    stock = (10u"g"*CHESSLabConstants.lactic_acid) + (1.0u"L"*CHESSLabConstants.water)
    families,_ = CHESSCore._analytical_species(stock)
    @test length(families) == 1
    expected_moles = 10u"g"/105.976u"g/mol" # not 10u"g"/90.08u"g/mol" (the pure-acid assumption)
    @test uconvert(u"mol",families[1].total_concentration*CHESSCore.volume_estimate(stock)) ≈ expected_moles atol=1e-6u"mol"
end

@testset "Acid/base equilibrium: iron/succinate/ammonium audit" begin
    # iron_chloride: Fe3+ hydrolysis, shared with iron_nitrate (same Fe3+ chemistry)
    fe_sys = CHESSCore.acid_base_system(CHESSLabConstants.iron_chloride)
    @test fe_sys isa AcidBaseSystem
    @test fe_sys.pKa == [2.2]
    @test fe_sys == CHESSCore.acid_base_system(CHESSLabConstants.iron_nitrate)
    fe_stock = (0.01u"mol"*CHESSLabConstants.iron_chloride) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(fe_stock;ionic_strength_correction=false) < 3.0 # markedly acidic, matches known FeCl3 behavior

    # iron_sulfate: Fe2+ hydrolysis, much weaker than Fe3+'s (lower charge density)
    fe2_sys = CHESSCore.acid_base_system(CHESSLabConstants.iron_sulfate)
    @test fe2_sys isa AcidBaseSystem
    @test fe2_sys.pKa == [9.5]
    fe2_stock = (0.01u"mol"*CHESSLabConstants.iron_sulfate) + (1.0u"L"*CHESSLabConstants.water)
    fe2_pH = CHESSCore.pH(fe2_stock;ionic_strength_correction=false)
    @test 4.0 < fe2_pH < 7.0 # mildly acidic, not markedly so
    @test fe2_pH > CHESSCore.pH(fe_stock;ionic_strength_correction=false) # less acidic than the Fe3+ salt at the same concentration

    # sodium_succinate_hexahydrate: identity is already the dianion, chain built upward from it
    succ_sys = CHESSCore.acid_base_system(CHESSLabConstants.sodium_succinate_hexahydrate)
    @test succ_sys isa AcidBaseSystem
    @test succ_sys.pKa == [4.21,5.64]
    @test succ_sys.species[3] == CHESSLabConstants.C4H4O4²⁻
    succ_stock = (0.01u"mol"*CHESSLabConstants.sodium_succinate_hexahydrate) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(succ_stock;ionic_strength_correction=false) > 7.0 # basic, the fully-deprotonated salt of a weak acid

    # ammonium: shared across all three ammonium salts
    nh4_sys = CHESSCore.acid_base_system(CHESSLabConstants.ammonium_sulfate)
    @test nh4_sys isa AcidBaseSystem
    @test nh4_sys.pKa == [9.25]
    @test nh4_sys == CHESSCore.acid_base_system(CHESSLabConstants.ammonium_chloride)
    @test nh4_sys == CHESSCore.acid_base_system(CHESSLabConstants.ammonium_nitrate)
    nh4_stock = (0.01u"mol"*CHESSLabConstants.ammonium_sulfate) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(nh4_stock;ionic_strength_correction=false) < 7.0 # mildly acidic, textbook ammonium-salt behavior
end

@testset "Acid/base equilibrium: default water_correction (open-system dissolved atmospheric CO2)" begin
    spec = CHESSCore.default_water_correction[]
    @test spec isa CHESSCore.OpenSystemSpecies
    @test spec.system.pKa == [6.352,10.329]
    @test spec.system == CHESSCore.acid_base_system(CHESSLabConstants.sodium_bicarbonate)
    @test uconvert(u"mol/L",spec.free_concentration) ≈ 1.7005985e-6u"mol/L" atol=1e-9u"mol/L"

    plain_water_stock = 1u"L"*CHESSLabConstants.water
    @test CHESSCore.pH(plain_water_stock) == 7.0 # unaffected by default (water_correction=false)
    @test CHESSCore.pH(plain_water_stock;water_correction=true) < 6.5 # measurably acidified

    # the exact empirical calibration point: NaCl has no acid/base chemistry of its own, so this
    # measurement isolates the water's own background acidity
    nacl_amt = 20u"g"/CHESSCore.molecular_weight(CHESSLabConstants.sodium_chloride)
    nacl_stock = plain_water_stock + nacl_amt*CHESSLabConstants.sodium_chloride
    @test CHESSCore.pH(nacl_stock;water_correction=true) ≈ 5.93 atol=1e-3
end

@testset "Truesdell-Jones ion parameters registered from wateq4f.dat" begin
    expected = Dict(
        CHESSLabConstants.Na⁺=>(4.0,0.075), CHESSLabConstants.K⁺=>(3.5,0.015),
        CHESSLabConstants.Ca²⁺=>(5.0,0.165), CHESSLabConstants.Mg²⁺=>(5.5,0.2),
        CHESSLabConstants.Fe²⁺=>(6.0,0.0), CHESSLabConstants.Fe³⁺=>(9.0,0.0),
        CHESSLabConstants.Cl⁻=>(3.5,0.015), CHESSLabConstants.NO3⁻=>(3.0,0.0),
        CHESSLabConstants.SO4²⁻=>(5.0,-0.04), CHESSLabConstants.CO3²⁻=>(5.4,0.0),
        CHESSLabConstants.HCO3⁻=>(5.4,0.0),
    )
    for (chem,params) in expected
        @test get(CHESSCore.ion_parameters,chem,nothing) == params
    end
    # NH4+ has no -gamma line in wateq4f.dat -- deliberately left unregistered (Davies fallback),
    # not guessed
    @test !haskey(CHESSCore.ion_parameters,CHESSLabConstants.NH4⁺)

    # the Davies-reliability warning no longer fires for bicarbonate_10x: CO3²⁻/HCO3⁻ now have real
    # Truesdell-Jones parameters, so they're exempt from the "no citable parameter" check
    bicarbonate_10x = 12.5u"g"*rgt"sodium_bicarbonate" + 1u"L"*rgt"water"
    @test_logs CHESSCore.pH(bicarbonate_10x;water_correction=true)

    # but it still fires where genuinely warranted: sodium_succinate_hexahydrate's custom organic
    # dianion has no registered ion_parameters, so it's still Davies-only
    succ = 2.06u"g"*rgt"sodium_succinate_hexahydrate" + 10u"mL"*rgt"water"
    @test_logs (:warn,r"Davies' reliable range") CHESSCore.pH(succ;water_correction=true)
end

@testset "Acid/base equilibrium: MOPS" begin
    sys = CHESSCore.acid_base_system(CHESSLabConstants.mops)
    @test sys isa AcidBaseSystem
    @test sys.pKa == [7.20]
    @test sys.species[1] == CHESSCore.Chemical(name(CHESSLabConstants.mops),0,CHESSCore.molecular_weight(CHESSLabConstants.mops))

    # MOPS is a Solid -- constructed by moles directly, like the other organic acid reagents
    stock = (0.1u"mol"*CHESSLabConstants.mops) + (1.0u"L"*CHESSLabConstants.water)
    Ka = 10.0^(-7.20)
    C = ustrip(uconvert(u"mol/L",0.1u"mol"/CHESSCore.volume_estimate(stock)))
    x = (-Ka+sqrt(Ka^2+4*Ka*C))/2 # independent closed-form quadratic solution
    expected_pH = -log10(x)
    @test CHESSCore.pH(stock;ionic_strength_correction=false) ≈ expected_pH atol=1e-6

    # the free acid (zwitterion) alone, with no counterion, is genuinely acidic -- matches the
    # quadratic weak-acid math above, and real lab practice: Good's buffers are titrated with NaOH to
    # reach their working pH, not just dissolved as-is
    @test CHESSCore.pH(stock;ionic_strength_correction=false) < 5.0

    # half-neutralized with NaOH (the realistic buffer preparation) -> pH ≈ pKa, the actual
    # "MOPS buffers near neutral pH" behavior
    buffered = (0.1u"mol"*CHESSLabConstants.mops) + (0.05u"mol"*CHESSLabConstants.NaOH) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(buffered;ionic_strength_correction=false) ≈ 7.20 atol=1e-3
end

@testset "Acid/base equilibrium: organic acid titration curve (citric acid)" begin
    sys = CHESSCore.acid_base_system(CHESSLabConstants.citric_acid)
    @test sys isa AcidBaseSystem
    @test sys.pKa == [3.13,4.76,6.40]

    # at each of its own pKa's, the flanking pair of states should be ~equal (textbook
    # Henderson-Hasselbalch check, independent of any particular stock/concentration)
    for (step,pk) in enumerate(sys.pKa)
        alphas = CHESSCore._alpha_fractions(sys.pKa,pk)
        @test alphas[step] ≈ alphas[step+1] atol=1e-6
    end

    # monotonic titration curve: as pH rises, each successive deprotonated state's fraction rises
    # while the fully-protonated state's fraction falls
    low = CHESSCore._alpha_fractions(sys.pKa,1.0)
    mid = CHESSCore._alpha_fractions(sys.pKa,5.0)
    high = CHESSCore._alpha_fractions(sys.pKa,9.0)
    @test low[1] > mid[1] > high[1]
    @test low[4] < mid[4] < high[4]
end

@testset "Acid/base equilibrium: zwitterion isoelectric point (aspartic_acid, glutamic_acid)" begin
    for (reagent,expected_pI) in ((CHESSLabConstants.aspartic_acid,(1.99+3.90)/2),
                                   (CHESSLabConstants.glutamic_acid,(2.19+4.25)/2))
        sys = CHESSCore.acid_base_system(reagent)
        @test sys isa AcidBaseSystem
        alphas = CHESSCore._alpha_fractions(sys.pKa,expected_pI)
        z0 = CHESSCore.charge(sys.species[1])
        net_charge = sum((z0-(j-1))*alphas[j] for j in eachindex(alphas))
        @test net_charge ≈ 0.0 atol=1e-6 # net charge vanishes at the isoelectric point, by construction
    end

    # folic_acid/fusidic_acid are deliberately unregistered (documented scope boundary)
    @test CHESSCore.acid_base_system(CHESSLabConstants.folic_acid) === nothing
    @test CHESSCore.acid_base_system(CHESSLabConstants.fusidic_acid) === nothing
end

@testset "Tier-1 audit pass: smoke test across all 52 newly-registered reagents" begin
    tier1_reagents = [
        :alanine,:valine,:leucine,:isoleucine,:glycine,:proline,:serine,:threonine,:methionine,
        :phenylalanine,:tryptophan,:asparagine,:glutamine,:citruline,:histidine,:cysteine,:tyrosine,
        :lysine,:arginine,:ornithine,:cystine,
        :edta,:ascorbate,:sodium_pyruvate,:sodium_butyrate,:tartrate,:biotin,:lipoic_acid,
        :sulfadiazine,:sulfamethazine,:sulfathiazole,:ciprofloxacin,:ofloxacin,
        :penicillin_g,:ampicillin,:amoxicillin,:carbenicillin,:oxacillin,
        :tetracycline,:doxycycline,:chlortetracycline,:minocycline,
        :cycloserine,:erythromycin,:lincomycin,
        :promethazine,:carnitine,:taurine,:agmatine,:amitrole,:benzamadine,:guanidine,
    ]
    @test length(tier1_reagents) == 52
    for r in tier1_reagents
        reagent = getfield(CHESSLabConstants,r)
        sys = CHESSCore.acid_base_system(reagent)
        @test sys isa AcidBaseSystem
        stock = (0.01u"mol"*reagent) + (1.0u"L"*CHESSLabConstants.water)
        p = pH(stock;ionic_strength_correction=false)
        @test isfinite(p)
        @test -2 < p < 16
    end
end

@testset "Tier-1 audit pass: representative exact-value checks" begin
    # simple amino acid: independent isoelectric-point check (net charge vanishes at pI)
    sys = CHESSCore.acid_base_system(CHESSLabConstants.glycine)
    pI = (sys.pKa[1]+sys.pKa[2])/2
    alphas = CHESSCore._alpha_fractions(sys.pKa,pI)
    z0 = CHESSCore.charge(sys.species[1])
    net_charge = sum((z0-(j-1))*alphas[j] for j in eachindex(alphas))
    @test net_charge ≈ 0.0 atol=1e-6

    # basic amino acid: pI uses the average of the two *higher* pKa's (textbook convention)
    lys_sys = CHESSCore.acid_base_system(CHESSLabConstants.lysine)
    lys_pI = (lys_sys.pKa[2]+lys_sys.pKa[3])/2
    lys_alphas = CHESSCore._alpha_fractions(lys_sys.pKa,lys_pI)
    lys_z0 = CHESSCore.charge(lys_sys.species[1])
    lys_net = sum((lys_z0-(j-1))*lys_alphas[j] for j in eachindex(lys_alphas))
    @test lys_net ≈ 0.0 atol=1e-6

    # histidine: same "extra basic side-chain" dication/cation/zwitterion/anion shape as lysine
    # (imidazole is basic, not acidic -- regression check for a real bug: histidine was originally
    # misclassified with the "extra acidic side-chain" shape, putting the zwitterion between the
    # wrong pair of pKa's and predicting pH ~4.05 for a 0.14g/50mL stock instead of the correct ~7.68,
    # against an empirically measured 7.86)
    his_sys = CHESSCore.acid_base_system(CHESSLabConstants.histidine)
    @test his_sys.pKa == [1.80,6.04,9.33]
    @test CHESSCore.charge(his_sys.species[1]) == 2 # dication, not a simple cation
    his_pI = (his_sys.pKa[2]+his_sys.pKa[3])/2
    his_alphas = CHESSCore._alpha_fractions(his_sys.pKa,his_pI)
    his_z0 = CHESSCore.charge(his_sys.species[1])
    his_net = sum((his_z0-(j-1))*his_alphas[j] for j in eachindex(his_alphas))
    @test his_net ≈ 0.0 atol=1e-6

    his_stock = (0.14u"g"*CHESSLabConstants.histidine) + (50u"mL"*CHESSLabConstants.water)
    @test CHESSCore.pH(his_stock;ionic_strength_correction=false) ≈ 7.68 atol=0.01

    # pyruvate is real sodium pyruvate (confirmed against Reagent_StockList.xlsx, Sigma P5280) --
    # its CompositionRule dissociates into Na+ and the correctly-charged anion, not a bare ion
    pyr_products = CHESSCore.composition(CHESSLabConstants.sodium_pyruvate).products
    @test pyr_products[CHESSLabConstants.PyruvateAnion] == 1
    @test pyr_products[CHESSLabConstants.Na⁺] == 1
    @test CHESSCore.molecular_weight(CHESSLabConstants.sodium_pyruvate) ≈ 110.04u"g/mol" atol=0.01u"g/mol"
    # dissolving the real salt (Na+ + pyruvate-) is a base-hydrolysis problem, not the free acid's
    # Henderson-Hasselbalch case -- the conjugate base of a moderately strong acid (pKa=2.5) hydrolyzes
    # only weakly, giving a mildly basic solution; checked against the base-hydrolysis closed form
    # (Kb=Kw/Ka) to a loose tolerance (the approximation itself isn't exact here) and a sanity range
    pyr_stock = (0.1u"mol"*CHESSLabConstants.sodium_pyruvate) + (1.0u"L"*CHESSLabConstants.water)
    Ka = 10.0^(-2.5)
    Kb = 1e-14/Ka
    C = ustrip(uconvert(u"mol/L",0.1u"mol"/CHESSCore.volume_estimate(pyr_stock)))
    x = (-Kb+sqrt(Kb^2+4*Kb*C))/2
    expected_pyr_pH = 14-(-log10(x))
    @test pH(pyr_stock;ionic_strength_correction=false) ≈ expected_pyr_pH atol=0.01
    @test 7.0 < pH(pyr_stock;ionic_strength_correction=false) < 8.0

    # butyrate is real sodium butyrate (confirmed: Sigma 303410)
    but_products = CHESSCore.composition(CHESSLabConstants.sodium_butyrate).products
    @test but_products[CHESSLabConstants.ButyrateAnion] == 1
    @test but_products[CHESSLabConstants.Na⁺] == 1
    @test CHESSCore.molecular_weight(CHESSLabConstants.sodium_butyrate) ≈ 110.09u"g/mol" atol=0.01u"g/mol"

    # tartrate is real sodium tartrate dihydrate (confirmed against Reagent_StockList.xlsx, catalog
    # AAA1618730) -- 2 Na+ and 2 waters of hydration, not a bare dianion
    tart_products = CHESSCore.composition(CHESSLabConstants.tartrate).products
    @test tart_products[CHESSLabConstants.TartrateDianion] == 1
    @test tart_products[CHESSLabConstants.Na⁺] == 2
    @test tart_products[CHESSLabConstants.H2O] == 2
    @test CHESSCore.molecular_weight(CHESSLabConstants.tartrate) ≈ 230.08u"g/mol" atol=0.01u"g/mol"

    # ascorbate is the plain free acid (both Reagent_StockList.xlsx catalog lines are "L-ASCORBIC
    # ACID") -- no CompositionRule needed, identity is neutral like citric_acid/lactic_acid
    @test !haskey(CHESSCore.composition_rules,CHESSLabConstants.ascorbate)
    @test CHESSCore.molecular_weight(CHESSLabConstants.ascorbate) ≈ 176.12u"g/mol" atol=0.01u"g/mol"

    # tetracycline (HCl-salt case): CompositionRule correctly dissociates into Cl- and the cation,
    # and molecular_weight is now derived (matching the stored HCl-salt mass), not the stale copy
    r = CHESSCore.recipe(0.01u"mol"*CHESSLabConstants.tetracycline)
    @test CHESSCore.molar_amount(r,CHESSLabConstants.Cl⁻) ≈ 0.01u"mol" atol=1e-6u"mol"
    @test CHESSCore.molecular_weight(CHESSLabConstants.tetracycline) ≈ 480.9u"g/mol" atol=0.02u"g/mol"

    # EDTA: simplified 4-pKa hexaprotic system produces a sane, acidic pH for a dilute solution
    edta_stock = (0.01u"mol"*CHESSLabConstants.edta) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(edta_stock;ionic_strength_correction=false) < 4.0

    # guanidine: a very strong base (pKa=13.6, near the solver's upper bracket) still solves cleanly
    guan_stock = (0.01u"mol"*CHESSLabConstants.guanidine) + (1.0u"L"*CHESSLabConstants.water)
    @test CHESSCore.pH(guan_stock;ionic_strength_correction=false) > 10.0
end
