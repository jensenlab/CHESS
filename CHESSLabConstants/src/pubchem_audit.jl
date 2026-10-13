#### Checking registered species against PubChem ############################

struct PubChemRecord
    cid::Int
    title::Union{String,Missing}
    formula::Union{String,Missing}
    molecular_weight::Union{Float64,Missing}
    charge::Int
    isotope_atoms::Int
end

"""
    PubChemThrottled(status, fetched)

Thrown by [`fetch_pubchem_records`](@ref) when PubChem answers with HTTP 429 or 503 (too many requests, or
the server is busy). `fetched` is the number of records already collected. The function does not retry,
because repeated requests extend the block.
"""
struct PubChemThrottled <: Exception
    status::Int
    fetched::Int
end

function Base.showerror(io::IO,e::PubChemThrottled)
    print(io,"PubChem refused the request (HTTP $(e.status)) after $(e.fetched) records were fetched. ",
        "Wait a few minutes, then call again with the same `records` to continue where it stopped.")
end

# One request for a batch of CIDs. PubChem leaves out the CIDs it does not have, and answers 404 when it
# has none of them.
function _pubchem_properties(cids::AbstractVector{<:Integer})
    url = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/$(join(cids,","))/property/Title,MolecularFormula,MolecularWeight,Charge,IsotopeAtomCount/JSON"
    response = HTTP.get(url;status_exception=false,readtimeout=60)
    response.status == 404 && return PubChemRecord[]
    response.status in (429,503) && throw(PubChemThrottled(response.status,0))
    response.status == 200 || error("PubChem answered HTTP $(response.status) for compounds $(first(cids)) to $(last(cids))")
    properties = JSON.parse(String(response.body))["PropertyTable"]["Properties"]
    return [PubChemRecord(
        Int(p["CID"]),
        haskey(p,"Title") ? String(p["Title"]) : missing,
        haskey(p,"MolecularFormula") ? String(p["MolecularFormula"]) : missing,
        haskey(p,"MolecularWeight") ? parse(Float64,string(p["MolecularWeight"])) : missing,
        Int(get(p,"Charge",0)),
        Int(get(p,"IsotopeAtomCount",0))) for p in properties]
end

"""
    fetch_pubchem_records(cids; records=Dict(), batchsize=25, delay=1.0)

Author-time tool: fetch the title, formula, molecular weight, charge, and isotope count that
[PubChem](https://pubchem.ncbi.nlm.nih.gov) holds for each PubChem ID in `cids`, in batches of `batchsize`
with `delay` seconds between requests. Returns the `records` dictionary, keyed by ID, with `nothing` for an
ID that PubChem does not have.

IDs already in `records` are not fetched again, so passing the same dictionary to a later call resumes a
fetch. If PubChem answers that there are too many requests, the function stops without retrying and throws
a `PubChemThrottled` error; the dictionary keeps everything fetched so far.

```julia-repl
julia> records = fetch_pubchem_records([923, 962]);

julia> records[923].formula
"Na+"
```
"""
function fetch_pubchem_records(cids;records::AbstractDict=Dict{Int,Union{PubChemRecord,Nothing}}(),
        batchsize::Integer=25,delay::Real=1.0,fetch=_pubchem_properties)
    need = [Int(c) for c in unique(cids) if !haskey(records,Int(c))]
    for (i,batch) in enumerate(Iterators.partition(need,batchsize))
        i > 1 && sleep(delay)
        found = try
            fetch(collect(batch))
        catch err
            err isa PubChemThrottled && throw(PubChemThrottled(err.status,length(records)))
            rethrow()
        end
        for record in found
            records[record.cid] = record
        end
        for cid in batch
            haskey(records,cid) || (records[cid] = nothing)
        end
    end
    return records
end

# The species of this package that can be audited: every `Species` constant, the species that each reagent
# breaks into (so a reagent's own species is covered), and the two ions CHESSCore defines. Each is paired
# with the name it is registered under.
function _lab_species()
    named = Pair{Symbol,CHESSCore.Species}[:H⁺=>CHESSCore.H⁺,:OH⁻=>CHESSCore.OH⁻]
    from_reagents = Pair{Symbol,CHESSCore.Species}[]
    for n in sort!(collect(names(CHESSLabConstants;all=true)))
        startswith(string(n),"#") && continue
        isdefined(CHESSLabConstants,n) || continue
        v = getfield(CHESSLabConstants,n)
        if v isa CHESSCore.Species
            push!(named,n=>v)
        elseif v isa CHESSCore.Reagent
            for spc in keys(CHESSCore.dissolution(v).products)
                push!(from_reagents,n=>spc)
            end
        end
    end
    # a species keeps the first name it is found under, so the species constants come before the species
    # that reagents break into
    seen = Set{Tuple{CHESSCore.Species,Any}}()
    found = Pair{Symbol,CHESSCore.Species}[]
    for p in Iterators.flatten((named,from_reagents))
        key = (p.second,CHESSCore.pubchemid(p.second))
        key in seen && continue
        push!(seen,key)
        push!(found,p)
    end
    return found
end

_alnum(s::AbstractString) = lowercase(replace(s,r"[^A-Za-z0-9]"=>""))

# Words that describe a species' charge state, not the compound.
const _CHARGE_WORDS = ("anion","cation","dication","trication","dianion","trianion","tetraanion","monoanion","zwitterion")

# True when the species' name and the PubChem title plausibly name the same compound: the first five letters
# of some word of five or more letters in one appear in the other, so "alanine" matches "alaninate". Words
# that contain a digit (as in "H3PO4") or only describe a charge state are not compared, and a name with no
# word left to compare is not judged.
function _title_plausible(name::AbstractString,title::AbstractString)
    function words(s)
        found = [lowercase(w) for w in split(s,r"[^A-Za-z0-9]+") if length(w) >= 5 && !occursin(r"[0-9]",w)]
        return [w for w in found if !(w in _CHARGE_WORDS)]
    end
    name_words = words(name)
    isempty(name_words) && return true
    title_alnum = _alnum(title)
    name_alnum = _alnum(name)
    return any(w->occursin(first(w,5),title_alnum),name_words) || any(w->occursin(first(w,5),name_alnum),words(title))
end

# The findings for one species and its PubChem record (`nothing` if PubChem has none): tuples of
# (severity, check, detail).
function _species_findings(spc::CHESSCore.Species,record::Union{PubChemRecord,Nothing})
    cid = CHESSCore.pubchemid(spc)
    ismissing(cid) && return [(:info,:no_pubchem_id,"the species has no PubChem ID")]
    record === nothing && return [(:error,:not_in_pubchem,"PubChem has no compound $cid")]
    findings = Tuple{Symbol,Symbol,String}[]
    if record.isotope_atoms > 0
        push!(findings,(:error,:isotopes,"PubChem compound $cid is isotope-labelled ($(record.isotope_atoms) atoms), but species have natural isotopes"))
    end
    if record.charge != CHESSCore.charge(spc)
        push!(findings,(:error,:charge_differs,"the species has charge $(CHESSCore.charge(spc)), PubChem has $(record.charge)"))
    end
    f = CHESSCore.formula(spc)
    if f isa Dict
        if ismissing(record.formula)
            push!(findings,(:review,:formula_unknown,"PubChem has no formula for compound $cid"))
        else
            pubchem_formula,_ = _split_pubchem_charge(record.formula)
            ours = CHESSCore.formula_string(f)
            theirs = try
                CHESSCore.formula_string(CHESSCore.parse_formula(pubchem_formula))
            catch err
                err isa ArgumentError || rethrow()
                missing
            end
            if ismissing(theirs)
                push!(findings,(:review,:formula_unreadable,"PubChem's formula $(record.formula) cannot be read as an elemental formula"))
            elseif theirs != ours
                push!(findings,(:error,:formula_differs,"the species has formula $ours, PubChem has $theirs"))
            end
        end
    elseif !(f isa CHESSCore.OpaqueFormula)
        mw = CHESSCore.molecular_weight(spc)
        if !ismissing(mw) && !ismissing(record.molecular_weight)
            ours = ustrip(u"g/mol",mw)
            if abs(ours - record.molecular_weight) > max(0.05,0.001*record.molecular_weight)
                push!(findings,(:error,:mass_differs,"the species has molar mass $(round(ours;digits=3)) g/mol, PubChem has $(record.molecular_weight)"))
            end
        end
    end
    if !ismissing(record.title) && !_title_plausible(CHESSCore.name(spc),record.title)
        push!(findings,(:review,:title_differs,"PubChem calls compound $cid \"$(record.title)\""))
    end
    return findings
end

"""
    audit_pubchem(species=nothing; records=Dict(), include_info=false, batchsize=25, delay=1.0)

Author-time tool: compare registered [`CHESSCore.Species`](@ref) with the PubChem compound each one names
by its PubChem ID, and return the differences as a `DataFrame`. By default it covers every species constant
of this package, the species each reagent breaks into, and `H⁺` and `OH⁻`. Pass a collection of species, or
of `label => species` pairs, to check others.

The PubChem records come from [`fetch_pubchem_records`](@ref), paced by `batchsize` and `delay`. Pass a
`records` dictionary to reuse fetched records, or to resume after PubChem refused a request: the
`PubChemThrottled` error leaves the dictionary holding what was fetched. A dictionary that already holds
every record needs no network at all.

Each row is a finding for one species, with columns `label`, `name`, `charge`, `pubchemid`, `severity`,
`check`, `detail`, and `pubchem_title`. The severities are:

- `:error`: the ID cannot be right for the species: PubChem has no such compound, or its charge or
  isotope labelling differs, or the species' formula (or, for a species without one, its molar mass)
  differs from PubChem's.
- `:review`: possibly wrong and worth a look, such as a PubChem title that has no word starting with the
  same five letters as a word of the species' name, or a formula PubChem writes in a form that cannot be
  read.
- `:info`: shown only with `include_info=true`: a species with no PubChem ID, or two species of the same
  chemistry that share an ID.

A formula check cannot find an ID that was copied together with its formula from the wrong compound, so
read the `pubchem_title` of any species whose registration came from a lookup.

```julia-repl
julia> audit_pubchem()
0×8 DataFrame
```
"""
function audit_pubchem(species=nothing;records::AbstractDict=Dict{Int,Union{PubChemRecord,Nothing}}(),
        include_info::Bool=false,batchsize::Integer=25,delay::Real=1.0,fetch=_pubchem_properties)
    pairs = if species === nothing
        _lab_species()
    else
        [s isa Pair ? Symbol(s.first)=>s.second : Symbol(CHESSCore.name(s))=>s for s in species]
    end
    cids = [CHESSCore.pubchemid(p.second) for p in pairs if !ismissing(CHESSCore.pubchemid(p.second))]
    fetch_pubchem_records(cids;records,batchsize,delay,fetch)

    findings = DataFrame(label=Symbol[],name=String[],charge=Int[],pubchemid=Union{Int,Missing}[],
        severity=Symbol[],check=Symbol[],detail=String[],pubchem_title=Union{String,Missing}[])
    function add!(label,spc,severity,check,detail,record)
        cid = CHESSCore.pubchemid(spc)
        push!(findings,(label,CHESSCore.name(spc),CHESSCore.charge(spc),ismissing(cid) ? missing : Int(cid),
            severity,check,detail,record isa PubChemRecord ? record.title : missing))
    end
    for (label,spc) in pairs
        cid = CHESSCore.pubchemid(spc)
        record = ismissing(cid) ? nothing : records[Int(cid)]
        for (severity,check,detail) in _species_findings(spc,record)
            add!(label,spc,severity,check,detail,record)
        end
    end

    # compounds that more than one distinct species names: the same chemistry under two names is only
    # informational, different chemistry cannot both be right
    by_cid = Dict{Int,Vector{Pair{Symbol,CHESSCore.Species}}}()
    for p in pairs
        cid = CHESSCore.pubchemid(p.second)
        ismissing(cid) || push!(get!(by_cid,Int(cid),Pair{Symbol,CHESSCore.Species}[]),p)
    end
    for (cid,group) in by_cid
        length(group) > 1 || continue
        chemistry = unique([(CHESSCore.charge(s),CHESSCore.formula(s) isa Dict ? CHESSCore.formula_string(CHESSCore.formula(s)) : CHESSCore.formula(s)) for (_,s) in group])
        severity = length(chemistry) == 1 ? :info : :error
        detail = "PubChem ID $cid is shared by "*join(["\"$(CHESSCore.name(s))\"" for (_,s) in group],", ")
        for (label,spc) in group
            add!(label,spc,severity,:shared_pubchem_id,detail,records[cid])
        end
    end

    include_info || filter!(r->r.severity != :info,findings)
    rank = Dict(:error=>1,:review=>2,:info=>3)
    sort!(findings,[DataFrames.order(:severity,by=s->rank[s]),:label])
    return findings
end
