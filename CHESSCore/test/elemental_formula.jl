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
