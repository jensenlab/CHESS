# fetch_pubchem_records and audit_pubchem, run without a network: the PubChem records are built here.
using CHESSCore, CHESSLabConstants, Test, Unitful, DataFrames

const PCR = CHESSLabConstants.PubChemRecord
const Throttled = CHESSLabConstants.PubChemThrottled

charge_suffix(z) = z == 0 ? "" : (z > 0 ? "+" : "-") * (abs(z) > 1 ? string(abs(z)) : "")
record(cid,formula,charge;title="record $cid",mw=missing,isotopes=0) = PCR(cid,title,formula,mw,charge,isotopes)
store(records...) = Dict{Int,Union{PCR,Nothing}}(r.cid => r for r in records)

@testset "fetch_pubchem_records" begin
    calls = Vector{Int}[]
    fake(cids) = (push!(calls,collect(cids)); [record(c,"H2O",0) for c in cids if c != 13])

    records = fetch_pubchem_records(1:60;batchsize=25,delay=0,fetch=fake)
    @test length(calls) == 3 && length.(calls) == [25,25,10]
    @test records[1].formula == "H2O"
    @test records[13] === nothing # PubChem has no compound 13

    # IDs already held are not fetched again
    empty!(calls)
    fetch_pubchem_records([1,2,3,70];records,delay=0,fetch=fake)
    @test calls == [[70]]
    fetch_pubchem_records(1:60;records,delay=0,fetch=fake)
    @test length(calls) == 1 # nothing new

    # the delay applies between requests, not before the first
    elapsed = @elapsed fetch_pubchem_records(100:104;batchsize=2,delay=0.2,fetch=fake)
    @test 0.35 < elapsed < 1.5 # three batches, two waits

    # a refused request stops the fetch, keeps what was fetched, and does not retry
    empty!(calls)
    refusing(cids) = length(calls) >= 1 ? throw(Throttled(429,0)) : (push!(calls,collect(cids)); [record(c,"H2O",0) for c in cids])
    partial = Dict{Int,Union{PCR,Nothing}}()
    err = try
        fetch_pubchem_records(1:60;records=partial,batchsize=25,delay=0,fetch=refusing)
        nothing
    catch e
        e
    end
    @test err isa Throttled && err.status == 429 && err.fetched == 25
    @test length(partial) == 25 && length(calls) == 1
    @test occursin("same `records`",sprint(showerror,err))
    # calling again with the same dictionary fetches only the rest
    empty!(calls)
    fetch_pubchem_records(1:60;records=partial,batchsize=25,delay=0,fetch=fake)
    @test calls == [collect(26:50),collect(51:60)]

    # other errors are not hidden
    @test_throws ErrorException fetch_pubchem_records([1];fetch=_ -> error("boom"),delay=0)
end

@testset "title check" begin
    plausible = CHESSLabConstants._title_plausible
    @test plausible("D-glucose","D-Glucose")
    @test plausible("L-aspartic acid","Aspartic acid")
    @test plausible("Alpha Ketoglutaric Acid (2-Oxoglutaric Acid)","2-Oxoglutaric Acid")
    @test plausible("Na+","Sodium Ion") # no word to judge
    @test !plausible("neomycin","Butyl Lactate")
    @test !plausible("Adonitol (Ribitol)","(2S,4R)-Pentane-1,2,3,4,5-Pentol")
end

@testset "audit_pubchem findings" begin
    ok = CHESSCore.Species("sodium ion",1,"Na";pubchemid=923)
    glucose = CHESSCore.Species("glucose",0,"C6H12O6";pubchemid=5793)
    stored = CHESSCore.Species("stored mass",0,100.0u"g/mol";pubchemid=7)
    stored_close = CHESSCore.Species("stored close",0,100.0u"g/mol";pubchemid=8)
    opaque = CHESSCore.Species("opaque thing",0,CHESSCore.opaque;pubchemid=9)
    unset = CHESSCore.Species("no id",0,"H2O")
    missing_cid = CHESSCore.Species("absent compound",0,"CH4";pubchemid=10)
    neomycin = CHESSCore.Species("neomycin",0,"C23H46N6O13";pubchemid=11)
    odd = CHESSCore.Species("odd formula",0,"C2H4";pubchemid=12)
    labelled = CHESSCore.Species("heavy water",0,"H2O";pubchemid=13)

    records = store(
        record(923,"Na+",1;title="Sodium Ion"),
        record(5793,"C6H12O5",0;title="glucose"), # formula differs
        record(7,"CH4",0;mw=120.0,title="stored mass"), record(8,"CH4",0;mw=100.03,title="stored close"),
        record(9,"C",0;title="opaque thing"),
        record(11,"C23H46N6O13",0;title="Butyl Lactate"),
        record(12,"(C2H4)n",0;title="odd formula"),
        record(13,"H2O",0;title="heavy water",isotopes=2))
    records[10] = nothing

    species = ["ok"=>ok,"glucose"=>glucose,"stored"=>stored,"stored_close"=>stored_close,"opaque"=>opaque,
        "unset"=>unset,"missing_cid"=>missing_cid,"neomycin"=>neomycin,"odd"=>odd,"labelled"=>labelled]
    found = audit_pubchem(species;records,fetch=_->error("no network expected"))
    @test names(found) == ["label","name","charge","pubchemid","severity","check","detail","pubchem_title"]
    checks = Dict(l => Set(found.check[found.label .== l]) for l in unique(found.label))
    @test !haskey(checks,:ok) && !haskey(checks,:stored_close) && !haskey(checks,:opaque) && !haskey(checks,:unset)
    @test checks[:glucose] == Set([:formula_differs])
    @test checks[:stored] == Set([:mass_differs])
    @test checks[:missing_cid] == Set([:not_in_pubchem])
    @test checks[:neomycin] == Set([:title_differs])
    @test checks[:odd] == Set([:formula_unreadable])
    @test checks[:labelled] == Set([:isotopes])

    severity = Dict(r.label => r.severity for r in eachrow(found))
    @test severity[:glucose] == :error && severity[:neomycin] == :review && severity[:odd] == :review
    # errors come first
    @test issorted(found.severity;by=s->Dict(:error=>1,:review=>2,:info=>3)[s])
    @test found[findfirst(==(:neomycin),found.label),:pubchem_title] == "Butyl Lactate"

    # a species without an ID is only informational
    with_info = audit_pubchem(species;records,include_info=true,fetch=_->error("no network expected"))
    @test only(with_info[with_info.label .== :unset,:check]) == :no_pubchem_id
    @test only(with_info[with_info.label .== :unset,:severity]) == :info

    # a charge that differs from PubChem's
    wrong_charge = CHESSCore.Species("wrong charge",1,"K";pubchemid=14)
    f = audit_pubchem([wrong_charge];records=store(record(14,"K",0;title="wrong charge")),fetch=_->error("no network expected"))
    @test only(f.check) == :charge_differs

    # a clean species set gives an empty table with the same columns
    clean = audit_pubchem([ok];records,fetch=_->error("no network expected"))
    @test nrow(clean) == 0 && names(clean) == names(found)

    # species that share an ID: the same chemistry is informational, different chemistry is an error
    water1 = CHESSCore.Species("water",0,"H2O";pubchemid=962)
    water2 = CHESSCore.Species("H2O",0,"H2O";pubchemid=962)
    water_records = store(record(962,"H2O",0;title="Water"))
    other = CHESSCore.Species("not water",0,"CH4";pubchemid=962)
    shared = audit_pubchem([water1,water2];records=water_records,include_info=true,fetch=_->error("no network expected"))
    @test all(shared.check .== :shared_pubchem_id) && all(shared.severity .== :info)
    @test isempty(audit_pubchem([water1,water2];records=water_records,fetch=_->error("no network expected")))
    conflict = audit_pubchem([water1,other];records=water_records,fetch=_->error("no network expected"))
    @test :shared_pubchem_id in conflict.check && all(conflict.severity[conflict.check .== :shared_pubchem_id] .== :error)

    # species given without labels are labelled by name
    @test only(audit_pubchem([glucose];records).label) == :glucose
end

@testset "audit_pubchem on the registry" begin
    species = CHESSLabConstants._lab_species()
    @test length(species) > 300
    labels = Set(first.(species))
    @test :Na⁺ in labels && :urea in labels && :H⁺ in labels
    with_cid = [s for (_,s) in species if !ismissing(CHESSCore.pubchemid(s))]
    @test length(with_cid) > 250

    # a PubChem built from the registry itself agrees with every species that has a formula
    records = Dict{Int,Union{PCR,Nothing}}()
    names_of = Dict{Int,Vector{String}}() # a compound's title names every species that uses it
    for spc in with_cid
        push!(get!(names_of,Int(CHESSCore.pubchemid(spc)),String[]),CHESSCore.name(spc))
    end
    for spc in with_cid
        cid = Int(CHESSCore.pubchemid(spc))
        haskey(records,cid) && continue
        f = CHESSCore.formula(spc)
        formula = f isa Dict ? CHESSCore.formula_string(f)*charge_suffix(CHESSCore.charge(spc)) : missing
        mw = ismissing(CHESSCore.molecular_weight(spc)) ? missing : ustrip(u"g/mol",CHESSCore.molecular_weight(spc))
        records[cid] = PCR(cid,join(unique(names_of[cid])," "),formula,mw,CHESSCore.charge(spc),0)
    end
    agree = audit_pubchem(records=records,fetch=_->error("no network expected"))
    @test nrow(agree) == 0

    # one wrong record is found, and only it
    cid = Int(CHESSCore.pubchemid(CHESSLabConstants.Na⁺))
    records[cid] = PCR(cid,"Sodium Ion","K+",missing,1,0)
    found = audit_pubchem(records=records,fetch=_->error("no network expected"))
    @test nrow(found) >= 1 && all(found.pubchemid .== cid) && all(found.check .== :formula_differs)
end
