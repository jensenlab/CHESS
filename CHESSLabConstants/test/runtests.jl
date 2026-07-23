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
    @test CHESSCore.concretetype(CHESSLabConstants.Nimbus) == CHESSCore.Instrument
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
