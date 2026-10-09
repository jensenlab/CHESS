using CHESSCore, Test, Unitful

const pf = CHESSCore.parse_formula
const fm = CHESSCore.formula_mass

@testset "parse_formula: element counts" begin
    @test pf("C6H12O6") == Dict(:C=>6,:H=>12,:O=>6)
    @test pf("H2O") == Dict(:H=>2,:O=>1)
    @test pf("NaCl") == Dict(:Na=>1,:Cl=>1)
    @test pf("Fe") == Dict(:Fe=>1)
    @test pf("C12H22O11") == Dict(:C=>12,:H=>22,:O=>11)
    @test pf("H12C6O6") == pf("C6H12O6") # order does not matter
    @test pf("CH3COOH") == Dict(:C=>2,:H=>4,:O=>2) # repeated elements are summed
    @test pf("CO") == Dict(:C=>1,:O=>1) # carbon monoxide
    @test pf("Co") == Dict(:Co=>1) # cobalt
end

@testset "parse_formula: groups" begin
    @test pf("Fe(OH)3") == Dict(:Fe=>1,:O=>3,:H=>3)
    @test pf("Ca3(PO4)2") == Dict(:Ca=>3,:P=>2,:O=>8)
    @test pf("(NH4)2SO4") == Dict(:N=>2,:H=>8,:S=>1,:O=>4)
    @test pf("K4[Fe(CN)6]") == Dict(:K=>4,:Fe=>1,:C=>6,:N=>6)
    @test pf("Mg(OH)2") == Dict(:Mg=>1,:O=>2,:H=>2)
    @test pf("((CH3)3C)2O") == Dict(:C=>8,:H=>18,:O=>1) # nested groups
end

@testset "parse_formula: hydrates" begin
    expected = Dict(:Fe=>1,:S=>1,:O=>11,:H=>14)
    @test pf("FeSO4·7H2O") == expected
    @test pf("FeSO4.7H2O") == expected # ASCII separator
    @test pf("2NaOH·H2O") == Dict(:Na=>2,:O=>3,:H=>4) # leading coefficient on the first part
    @test pf("CaSO4·2H2O") == Dict(:Ca=>1,:S=>1,:O=>6,:H=>4)
    @test pf("MgSO4.7H2O") == Dict(:Mg=>1,:S=>1,:O=>11,:H=>14)
    @test pf("CuSO4·5H2O·H2O") == Dict(:Cu=>1,:S=>1,:O=>10,:H=>12) # more than two parts
end

@testset "parse_formula: errors" begin
    @test_throws ArgumentError pf("")
    @test_throws ArgumentError pf("Xx")
    @test_throws ArgumentError pf("Uue") # element 119 placeholder is not accepted
    @test_throws ArgumentError pf("nacl") # lowercase start
    @test_throws ArgumentError pf("Fe(OH")
    @test_throws ArgumentError pf("FeOH)3")
    @test_throws ArgumentError pf("K4[Fe(CN)6)") # mismatched bracket kinds
    @test_throws ArgumentError pf("()")
    @test_throws ArgumentError pf("C0H4") # zero count
    @test_throws ArgumentError pf("C6H12O6 ") # whitespace
    @test_throws ArgumentError pf("FeSO4 · 7H2O")
    @test_throws ArgumentError pf("FeSO4·") # empty hydrate part
    @test_throws ArgumentError pf("Na+") # charge
    @test_throws ArgumentError pf("SO4^2-")
    @test_throws ArgumentError pf("SO4²⁻")
    @test_throws ArgumentError pf("CaSO4·0.5H2O") # fractional coefficient
    @test_throws ArgumentError pf("½H2O")
    # isotopes: reserved notation and D/T are rejected with an explanatory message
    @test_throws ArgumentError pf("[13C]6H12O6")
    @test_throws ArgumentError pf("[2H]2O")
    err = try pf("[13C]6H12O6") catch e e end
    @test occursin("isotope",err.msg)
    err = try pf("D2O") catch e e end
    @test occursin("isotope",err.msg)
    err = try pf("Na+") catch e e end
    @test occursin("charge",err.msg)
end

@testset "formula_mass" begin
    @test fm("H2O") ≈ 18.015u"g/mol" atol=0.001u"g/mol"
    @test fm("NaCl") ≈ 58.44u"g/mol" atol=0.01u"g/mol"
    @test fm("C6H12O6") ≈ 180.156u"g/mol" atol=0.01u"g/mol"
    @test fm("Fe") ≈ 55.845u"g/mol" atol=0.001u"g/mol"
    @test fm("FeSO4·7H2O") ≈ 278.01u"g/mol" atol=0.02u"g/mol"
    @test fm(Dict(:Na=>1,:Cl=>1)) == fm("NaCl")
    @test unit(fm("H2O")) == u"g/mol"
    @test_throws ArgumentError fm(Dict{Symbol,Int}())
    @test_throws ArgumentError fm(Dict(:Xx=>1))
end

@testset "Species with elemental formulas" begin
    glucose_sp = Species("D-glucose",0,"C6H12O6")
    @test molecular_weight(glucose_sp) ≈ 180.156u"g/mol" atol=0.01u"g/mol"
    @test CHESSCore.formula(glucose_sp) == Dict(:C=>6,:H=>12,:O=>6)
    @test charge(glucose_sp) == 0
    @test Species("D-glucose","C6H12O6") == glucose_sp # neutral shorthand

    # a species with a stored molecular weight has no formula
    legacy = Species("legacy",1,100.0u"g/mol")
    @test molecular_weight(legacy) == 100.0u"g/mol"
    @test ismissing(CHESSCore.formula(legacy))
    @test ismissing(molecular_weight(Species("unknown",1,missing)))

    # equality: name, charge, and formula (element order does not matter)
    @test Species("x",0,"C6H12O6") == Species("x",0,"H12C6O6")
    @test hash(Species("x",0,"C6H12O6")) == hash(Species("x",0,"H12C6O6"))
    @test Species("x",0,"C6H12O6") != Species("x",0,"C6H12O5") # same name, different formula
    @test Species("x",0,"C6H12O6") != Species("x",1,"C6H12O6")
    @test Species("x",0,"C6H12O6") != Species("y",0,"C6H12O6")
    @test Species("glucose",0,"C6H12O6") != Species("fructose",0,"C6H12O6") # isomers are separate species

    # a species takes a formula or a stored weight, not both, and a formula must be non-empty
    @test_throws ArgumentError Species("x",0,Dict(:C=>1),1.0u"g/mol")
    @test_throws ArgumentError Species("x",0,Dict{Symbol,Int}(),missing)
    @test_throws ArgumentError Species("x",0,"Xx")
    @test_throws ArgumentError Species("x",0,"Na+")

    # the canonical proton and hydroxide carry derived molecular weights
    @test molecular_weight(H⁺) ≈ 1.008u"g/mol" atol=0.001u"g/mol"
    @test molecular_weight(OH⁻) ≈ 17.007u"g/mol" atol=0.001u"g/mol"
end

@testset "@species" begin
    @species TestFormulaNa⁺ "Na+" 1 "Na"
    @species TestFormulaGlucose "D-glucose" 0 "C6H12O6"
    @species TestLegacyIon "legacy ion" 1 123.0u"g/mol"
    @test molecular_weight(TestFormulaNa⁺) ≈ 22.99u"g/mol" atol=0.01u"g/mol"
    @test TestFormulaGlucose == Species("D-glucose",0,"C6H12O6")
    @test molecular_weight(TestLegacyIon) == 123.0u"g/mol"
end

@testset "formula_string: canonical Hill order" begin
    fs = CHESSCore.formula_string
    @test fs(pf("C6H12O6")) == "C6H12O6"
    @test fs(pf("H12C6O6")) == "C6H12O6"
    @test fs(pf("NaCl")) == "ClNa" # no carbon: alphabetical
    @test fs(pf("H2O")) == "H2O"
    @test fs(pf("CH3COOH")) == "C2H4O2"
    @test fs(pf("FeSO4·7H2O")) == "FeH14O11S"
    @test fs(pf("C2H5Br")) == "C2H5Br"
    @test fs(Dict(:C=>1,:Br=>1)) == "CBr" # no hydrogen: carbon then alphabetical
    # round trip: parsing the string gives back the same counts
    for f in ("C6H12O6","K4[Fe(CN)6]","Ca3(PO4)2","FeSO4·7H2O","H2O")
        @test pf(fs(pf(f))) == pf(f)
    end
    @test_throws ArgumentError fs(Dict{Symbol,Int}())
end

@testset "@reagent chemistry argument" begin
    # a formula string: identity species with that formula, molecular weight derived
    @reagent TestGlucose "D-glucose" Solid "C6H12O6" 1.2u"g/mL" 5793
    @test molecular_weight(TestGlucose) ≈ 180.156u"g/mol" atol=0.01u"g/mol"
    d = CHESSCore.dissolution(TestGlucose)
    @test d == Dissolution(Dict(Species("D-glucose",0,"C6H12O6")=>1))
    @test CHESSCore.dissolutions[TestGlucose] == d
    @test TestGlucose.molecular_weight ≈ molecular_weight(TestGlucose) # stored weight is the derived one
    @test pubchemid(TestGlucose) == 5793

    # a dissolution expression
    @species TestFe³⁺ "Fe3+" 3 "Fe"
    @species TestCl⁻ "Cl-" -1 "Cl"
    @reagent TestIronChloride "iron chloride" Solid (TestFe³⁺ + 3*TestCl⁻) 2.8u"g/mL" 24380
    @test molecular_weight(TestIronChloride) ≈ 162.2u"g/mol" atol=0.1u"g/mol"
    @test CHESSCore.dissolution(TestIronChloride).products == Dict(TestFe³⁺=>1,TestCl⁻=>3)

    # the legacy forms: a stored molecular weight, and missing
    @reagent TestLegacyReagent "legacy reagent" Solid 100.0u"g/mol" 1.0u"g/mL" missing
    @test molecular_weight(TestLegacyReagent) == 100.0u"g/mol"
    @test ismissing(CHESSCore.formula(only(keys(CHESSCore.dissolution(TestLegacyReagent).products))))
    @reagent TestUnknownReagent "unknown reagent" Solid missing missing missing
    @test ismissing(molecular_weight(TestUnknownReagent))
    @test ismissing(CHESSCore.formula(only(keys(CHESSCore.dissolution(TestUnknownReagent).products))))

    # opaque: no molecular weight, a species flagged as intentionally undescribed
    @reagent TestYeastExtract "yeast extract" Solid opaque 1.0u"g/mL" missing
    @test ismissing(molecular_weight(TestYeastExtract))
    spc_opaque = only(keys(CHESSCore.dissolution(TestYeastExtract).products))
    @test CHESSCore.is_opaque(spc_opaque)
    @test !CHESSCore.is_opaque(only(keys(CHESSCore.dissolution(TestUnknownReagent).products)))
    @test ismissing(molecular_weight(spc_opaque))
    # an opaque reagent contributes no moles to a composition
    @test isempty(composition(5u"g"*TestYeastExtract).amounts)

    # an invalid formula string is rejected when the reagent is defined
    @test_throws ArgumentError @eval @reagent TestBadFormula "bad" Solid "Xx2" missing missing
end

@testset "opaque species" begin
    o = Species("undefined mixture",0,CHESSCore.opaque)
    @test CHESSCore.is_opaque(o)
    @test CHESSCore.formula(o) === CHESSCore.opaque
    @test ismissing(molecular_weight(o))
    @test o == Species("undefined mixture",0,CHESSCore.opaque)
    @test o != Species("undefined mixture",0,missing)
    @test hash(o) == hash(Species("undefined mixture",0,CHESSCore.opaque))
    @test_throws ArgumentError Species("x",0,CHESSCore.opaque,1.0u"g/mol")
    @species TestOpaqueSpecies "opaque species" 0 opaque
    @test CHESSCore.is_opaque(TestOpaqueSpecies)
end

@testset "set_dissolution! requires a neutral reagent" begin
    na = Species("Na+",1,"Na")
    cl = Species("Cl-",-1,"Cl")
    so4 = Species("SO4 2-",-2,"SO4")
    salt = Solid("charge_check_salt",missing,missing,missing)
    @test_throws ArgumentError set_dissolution!(salt,Dissolution(Dict(na=>1)))
    @test_throws ArgumentError set_dissolution!(salt,Dissolution(Dict(na=>1,cl=>2)))
    @test !haskey(dissolutions,salt)
    @test set_dissolution!(salt,Dissolution(Dict(na=>1,cl=>1))) === nothing
    @test haskey(dissolutions,salt)
    @test set_dissolution!(salt,Dissolution(Dict(na=>2,so4=>1))) === nothing
end
