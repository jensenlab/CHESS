
function _organism_cache_db()
    db = SQLite.DB(chemical_cache_path)
    DBInterface.execute(db,"PRAGMA foreign_keys = ON;")
    return db
end

function _cached_organism(lab_id::AbstractString)
    db = _organism_cache_db()
    out = DBInterface.execute(db,"SELECT * FROM Organisms WHERE LabID = ?",(lab_id,)) |> DataFrame
    return nrow(out) == 0 ? nothing : out[1,:]
end

function _cache_organism!(lab_id::AbstractString,genus::AbstractString,species::AbstractString,strain::AbstractString,
        atcc_id::Union{AbstractString,Missing},notes::AbstractString)
    db = _organism_cache_db()
    atcc = ismissing(atcc_id) ? "" : atcc_id
    DBInterface.execute(db,"INSERT OR IGNORE INTO Organisms(LabID,Genus,Species,Strain,ATCCID,Notes) VALUES(?,?,?,?,?,?)",
        (lab_id,genus,species,strain,atcc,notes))
    return nothing
end

"""
    register_organism!(lab_id::AbstractString,genus::AbstractString,species::AbstractString,strain::AbstractString="";
                        atcc_id::Union{AbstractString,Missing}=missing,notes::AbstractString="")

Author-time tool, mirroring [`register_reagent!`](@ref): records `lab_id`'s genus/species/strain (plus
`atcc_id`/`notes` for the record -- [`CHESSCore.Organism`](@ref) itself only models genus/species/
strain, so those two are cached but not part of the returned line) in the local cache
([`chemical_cache_path`](@ref)), then returns a ready-to-paste `@organism` line. Paste it into
`organisms.jl` to register it, or keep it in a private, gitignored file purely for your own records
if it shouldn't be public -- a private file like this is not `include`d by the package itself, so
anything kept there is never actually registered.

Example:
```julia-repl
julia> register_organism!("SMU_UA159","Streptococcus","mutans","UA159";atcc_id="700610",notes="wild type")
"@organism SMU_UA159 \\"Streptococcus\\" \\"mutans\\" \\"UA159\\""
```
"""
function register_organism!(lab_id::AbstractString,genus::AbstractString,species::AbstractString,strain::AbstractString="";
        atcc_id::Union{AbstractString,Missing}=missing,notes::AbstractString="")
    if isnothing(_cached_organism(lab_id))
        _cache_organism!(lab_id,genus,species,strain,atcc_id,notes)
    end
    return "@organism $lab_id \"$genus\" \"$species\" \"$strain\""
end
