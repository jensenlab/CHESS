
"""
    const chemical_cache_path

Path to the SQLite cache of PubChem-derived properties, keyed by `LabID`: `Reagents`
(`Name`/`Type`/`MolecularWeight`/`Density`/`CID`, backing [`register_reagent!`](@ref)) and `Chemicals`
(`Name`/`Charge`/`MolecularWeight`/`CID`, backing [`register_chemical!`](@ref)) -- named to match
[`CHESSCore.Reagent`](@ref)/[`CHESSCore.Chemical`](@ref) exactly, not the other way around. Used only
by those two author-time tools -- package load never touches this file or the network.
"""
const chemical_cache_path = joinpath(@__DIR__,"..","lab_constants_cache.db")

function _reagent_cache_db()
    db = SQLite.DB(chemical_cache_path)
    DBInterface.execute(db,"PRAGMA foreign_keys = ON;")
    DBInterface.execute(db,"""
        CREATE TABLE IF NOT EXISTS Reagents(
            LabID TEXT PRIMARY KEY,
            Name TEXT,
            Type TEXT,
            MolecularWeight REAL,
            Density REAL,
            CID INTEGER,
            Unique(Name),
            Unique(CID)
        );
        """)
    return db
end

function _cached_reagent(lab_id::AbstractString)
    db = _reagent_cache_db()
    out = DBInterface.execute(db,"SELECT * FROM Reagents WHERE LabID = ?",(lab_id,)) |> DataFrame
    return nrow(out) == 0 ? nothing : out[1,:]
end

function _cache_reagent!(lab_id::AbstractString,name::AbstractString,type::DataType,
        molecular_weight::Union{Real,Missing},density::Union{Real,Missing},pubchemid::Union{Integer,Missing})
    db = _reagent_cache_db()
    mw = ismissing(molecular_weight) ? "NULL" : molecular_weight
    d = ismissing(density) ? "NULL" : density
    cid = ismissing(pubchemid) ? "NULL" : pubchemid
    DBInterface.execute(db,"INSERT OR IGNORE INTO Reagents(LabID,Name,Type,MolecularWeight,Density,CID) VALUES(?,?,?,$mw,$d,$cid)",
        (lab_id,name,string(type)))
    return nothing
end

_reagent_line(lab_id,name,type,mw,density,pubchemid) =
    "@reagent $lab_id \"$name\" $type $(ismissing(mw) ? "missing" : "$(mw)u\"g/mol\"") $(ismissing(density) ? "missing" : "$(density)u\"g/mL\"") $(ismissing(pubchemid) ? "missing" : pubchemid)"

"""
    register_reagent!(type::DataType,lab_id::AbstractString,name::AbstractString,pubchemid::Union{Integer,Missing}=missing)

Author-time tool: look up `lab_id`'s molecular weight/density in the local cache
([`chemical_cache_path`](@ref)); on a cache miss, fetch them from PubChem via
[`get_mw_density`](@ref) (requires `pubchemid`) and cache the result. Returns a ready-to-paste
`@reagent` line -- it does not `eval` anything or write to `solids.jl`/`liquids.jl` itself. Paste the
returned line into the appropriate file (alphabetized) and commit.

`type` must be [`CHESSCore.Solid`](@ref) or [`CHESSCore.Liquid`](@ref). Omit `pubchemid` for a
compound with no PubChem entry (e.g. a rich-media broth) -- molecular weight/density are recorded as
`missing`.

Example:
```julia-repl
julia> register_reagent!(CHESSCore.Solid,"boric_acid","Boric Acid",7628)
"@reagent boric_acid \\"Boric Acid\\" Solid 61.84u\\"g/mol\\" 1.435u\\"g/mL\\" 7628"
```
"""
function register_reagent!(type::DataType,lab_id::AbstractString,name::AbstractString,pubchemid::Union{Integer,Missing}=missing)
    cached = _cached_reagent(lab_id)
    if !isnothing(cached)
        mw = ismissing(cached.MolecularWeight) ? missing : cached.MolecularWeight
        d = ismissing(cached.Density) ? missing : cached.Density
        cid = ismissing(cached.CID) ? missing : cached.CID
        return _reagent_line(lab_id,name,type,mw,d,cid)
    end
    if ismissing(pubchemid)
        _cache_reagent!(lab_id,name,type,missing,missing,missing)
        return _reagent_line(lab_id,name,type,missing,missing,missing)
    end
    molecular_weight,density = get_mw_density(pubchemid)
    _cache_reagent!(lab_id,name,type,molecular_weight,density,pubchemid)
    return _reagent_line(lab_id,name,type,molecular_weight,density,pubchemid)
end

function _chemical_cache_db()
    db = SQLite.DB(chemical_cache_path)
    DBInterface.execute(db,"PRAGMA foreign_keys = ON;")
    DBInterface.execute(db,"""
        CREATE TABLE IF NOT EXISTS Chemicals(
            LabID TEXT PRIMARY KEY,
            Name TEXT,
            Charge INTEGER,
            MolecularWeight REAL,
            CID INTEGER,
            Unique(Name),
            Unique(CID)
        );
        """)
    return db
end

function _cached_chemical(lab_id::AbstractString)
    db = _chemical_cache_db()
    out = DBInterface.execute(db,"SELECT * FROM Chemicals WHERE LabID = ?",(lab_id,)) |> DataFrame
    return nrow(out) == 0 ? nothing : out[1,:]
end

function _cache_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,
        molecular_weight::Union{Real,Missing},pubchemid::Integer)
    db = _chemical_cache_db()
    mw = ismissing(molecular_weight) ? "NULL" : molecular_weight
    DBInterface.execute(db,"INSERT OR IGNORE INTO Chemicals(LabID,Name,Charge,MolecularWeight,CID) VALUES(?,?,?,$mw,?)",
        (lab_id,name,charge,pubchemid))
    return nothing
end

_chemical_line(lab_id,name,charge,mw) = "@chemical $lab_id \"$name\" $charge $(mw)u\"g/mol\""

"""
    register_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,pubchemid::Integer)

Author-time tool, mirroring [`register_reagent!`](@ref) for [`CHESSCore.Chemical`](@ref) identities
(ions) instead of [`CHESSCore.Reagent`](@ref)s: looks up `lab_id`'s molecular weight in the local cache
([`chemical_cache_path`](@ref)); on a cache miss, fetches it from PubChem via [`get_mw_density`](@ref)
(density is fetched but discarded -- `Chemical` has no density field) and caches the result. Returns a
ready-to-paste `@chemical` line -- `Chemical` itself has no `pubchemid` field, so this is authoring
convenience only, not permanent provenance. Paste the returned line into
`chemicals/dissociation.jl` and commit.

Example:
```julia-repl
julia> register_chemical!("Na⁺","Na+",1,923)
"@chemical Na⁺ \\"Na+\\" 1 22.9897693u\\"g/mol\\""
```
"""
function register_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,pubchemid::Integer)
    cached = _cached_chemical(lab_id)
    if !isnothing(cached)
        mw = ismissing(cached.MolecularWeight) ? missing : cached.MolecularWeight
        return _chemical_line(lab_id,name,charge,mw)
    end
    molecular_weight,_ = get_mw_density(pubchemid)
    _cache_chemical!(lab_id,name,charge,molecular_weight,pubchemid)
    return _chemical_line(lab_id,name,charge,molecular_weight)
end
