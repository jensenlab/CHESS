using CHESSCore, CHESSLabConstants, Test, Unitful

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
    # anhydrous salt: derived weight matches the stored value
    @test CHESSCore.molecular_weight(CHESSLabConstants.copper_sulfate) ≈ 159.61u"g/mol" atol=0.01u"g/mol"

    # hydrate: waters of hydration keep the derived weight at the hydrate value, not the anhydrous one
    @test CHESSCore.molecular_weight(CHESSLabConstants.calcium_chloride) ≈ 147.01u"g/mol" atol=0.01u"g/mol"

    # pre-existing data bug in the ported PubChem cache (NaCl stored as 214.25u"g/mol") is corrected
    # by composition-derivation, which takes precedence over the stored field
    @test CHESSCore.molecular_weight(CHESSLabConstants.sodium_chloride) ≈ 58.44u"g/mol" atol=0.01u"g/mol"

    # recipe()/total_concentration() see the real ionic composition
    stock = 1u"mol" * CHESSLabConstants.calcium_chloride
    r = CHESSCore.recipe(stock)
    @test CHESSCore.molar_amount(r,CHESSLabConstants.Ca²⁺) ≈ 1u"mol" atol=1e-6u"mol"
    @test CHESSCore.molar_amount(r,CHESSLabConstants.Cl⁻) ≈ 2u"mol" atol=1e-6u"mol"
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
