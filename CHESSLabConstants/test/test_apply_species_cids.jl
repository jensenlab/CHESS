# The developer script that writes PubChem IDs into @species lines (tools/apply_species_cids.jl).
include(joinpath(@__DIR__,"..","tools","apply_species_cids.jl"))

@testset "apply_species_cids: rewriting @species lines" begin
    add = add_cid
    @test add("@species AmpicillinCation \"Ampicillin(cation)\" 1 \"C16H20N3O4S\"","AmpicillinCation",6249) ==
        "@species AmpicillinCation \"Ampicillin(cation)\" 1 \"C16H20N3O4S\" 6249"
    # a trailing comment stays after the ID
    @test add("@species AspartateCation \"Aspartate(cation)\" 1 \"C4H8NO4\" # L-aspartic acid + H+","AspartateCation",5960) ==
        "@species AspartateCation \"Aspartate(cation)\" 1 \"C4H8NO4\" 5960 # L-aspartic acid + H+"
    # unicode labels and charges
    @test add("@species HCitrate²⁻ \"HCitrate2-\" -2 \"C6H6O7\"","HCitrate²⁻",311) == "@species HCitrate²⁻ \"HCitrate2-\" -2 \"C6H6O7\" 311"
    # a line that already has an ID is reported, not changed
    @test add("@species H3PO4 \"H3PO4\" 0 \"H3PO4\" 1004","H3PO4",1) === :has_cid
    # another species, or text that is not a species definition
    @test isnothing(add("@species Other \"x\" 0 \"H2O\"","AmpicillinCation",1))
    @test isnothing(add("# @species AmpicillinCation","AmpicillinCation",1))
    @test isnothing(add("@reagent water \"water\" Liquid \"H2O\" 1.0u\"g/mL\" 962","water",1))
end

@testset "apply_species_cids: decisions files and files on disk" begin
    dir = mktempdir()
    csv = joinpath(dir,"decisions.csv")
    write(csv,"label,decision,cid,notes\nAmpicillinCation,cid,6249,\"parent, neutral\"\nFoo,skip,,\nBar,cid,594.0,\n")
    @test read_decisions(csv) == Dict("AmpicillinCation"=>6249,"Bar"=>594)
    write(csv,"label,decision,cid\nA,cid,notanumber\n")
    @test_throws ErrorException read_decisions(csv)
    write(csv,"label,decision,cid\nA,cid,1\nA,cid,2\n")
    @test_throws ErrorException read_decisions(csv)

    file = joinpath(dir,"species.jl")
    write(file,"@species A \"a\" 0 \"H2\"\n@species B \"b\" 1 \"H\" # comment\n@species C \"c\" 0 \"H2O\" 962\n")
    changed = redirect_stdout(devnull) do
        dry = apply_decisions(Dict("A"=>1,"B"=>2,"C"=>3,"D"=>4),[file];write=false)
        @test sort(dry) == ["A","B"] && read(file,String) == "@species A \"a\" 0 \"H2\"\n@species B \"b\" 1 \"H\" # comment\n@species C \"c\" 0 \"H2O\" 962\n"
        apply_decisions(Dict("A"=>1,"B"=>2,"C"=>3,"D"=>4),[file];write=true)
    end
    @test sort(changed) == ["A","B"]
    @test read(file,String) == "@species A \"a\" 0 \"H2\" 1\n@species B \"b\" 1 \"H\" 2 # comment\n@species C \"c\" 0 \"H2O\" 962\n"
end
