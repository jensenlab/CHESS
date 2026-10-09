
"""
    const chemical_cache_path

Path to the SQLite cache of PubChem-derived properties, keyed by `LabID`: `Reagents`
(`Name`/`Type`/`MolecularWeight`/`Density`/`CID`/`Formula`, backing [`register_reagent!`](@ref)) and
`Chemicals` (`Name`/`Charge`/`MolecularWeight`/`CID`/`Formula`, backing [`register_chemical!`](@ref),
which produces [`CHESSCore.Species`](@ref) definitions). Used only by those two author-time tools -- package load
never touches this file or the network.
"""
const chemical_cache_path = joinpath(@__DIR__,"..","lab_constants_cache.db")

# --- formulas from PubChem -------------------------------------------------------------------------

# PubChem writes an ion's charge as a suffix: "Na+", "O4S-2", "C6H5O7-3". Returns (formula, charge).
function _split_pubchem_charge(pubchem_formula::AbstractString)
    m = match(r"^(.*?)([+-])(\d*)$",pubchem_formula)
    m === nothing && return (String(pubchem_formula),0)
    magnitude = isempty(m.captures[3]) ? 1 : parse(Int,m.captures[3])
    return (String(m.captures[1]),m.captures[2] == "+" ? magnitude : -magnitude)
end

"""
    _usable_formula(pubchem_formula, charge) -> String or missing

Turn a formula written by PubChem into one for a species or reagent of the given `charge`: the charge
suffix is removed and must agree with `charge`, and the remainder must read as an elemental formula
(see `CHESSCore.parse_formula`). Returns the formula in Hill order, or `missing` with a warning saying
why the formula cannot be used.
"""
function _usable_formula(pubchem_formula::Union{AbstractString,Missing},charge::Integer)
    ismissing(pubchem_formula) && return missing
    formula,pubchem_charge = _split_pubchem_charge(pubchem_formula)
    if pubchem_charge != charge
        @warn "PubChem's formula $pubchem_formula has charge $pubchem_charge, not $charge; the formula was not used"
        return missing
    end
    counts = try
        CHESSCore.parse_formula(formula)
    catch err
        err isa ArgumentError || rethrow()
        @warn "PubChem's formula $pubchem_formula cannot be read as an elemental formula ($(err.msg)); the formula was not used"
        return missing
    end
    return CHESSCore.formula_string(counts)
end

# The formula for `cid`, or missing (with a warning) if PubChem cannot be reached or its formula is unusable.
function _fetch_formula(cid::Integer,charge::Integer)
    pubchem_formula = try
        get_molecular_formula(cid)
    catch err
        @warn "could not fetch the formula of compound $cid from PubChem: $(sprint(showerror,err)); the line uses the stored molecular weight instead"
        return missing
    end
    return _usable_formula(pubchem_formula,charge)
end

# Warn if a stored molecular weight disagrees with the mass of a formula.
function _check_formula_mass(lab_id,formula::AbstractString,mw::Union{Real,Missing})
    ismissing(mw) && return nothing
    computed = ustrip(u"g/mol",CHESSCore.formula_mass(formula))
    if abs(mw - computed) > max(0.02,0.0005*computed)
        @warn "$lab_id: the stored molecular weight $mw g/mol disagrees with the mass of $formula ($(round(computed;digits=3)) g/mol); check the PubChem ID"
    end
    return nothing
end

function _ensure_formula_column!(db,table::AbstractString)
    columns = DBInterface.execute(db,"SELECT name FROM pragma_table_info('$table')") |> DataFrame
    "Formula" in columns.name || DBInterface.execute(db,"ALTER TABLE $table ADD COLUMN Formula TEXT")
    return nothing
end

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
            Formula TEXT,
            Unique(Name),
            Unique(CID)
        );
        """)
    _ensure_formula_column!(db,"Reagents")
    return db
end

function _cached_reagent(lab_id::AbstractString)
    db = _reagent_cache_db()
    out = DBInterface.execute(db,"SELECT * FROM Reagents WHERE LabID = ?",(lab_id,)) |> DataFrame
    return nrow(out) == 0 ? nothing : out[1,:]
end

function _cache_reagent!(lab_id::AbstractString,name::AbstractString,type::DataType,
        molecular_weight::Union{Real,Missing},density::Union{Real,Missing},pubchemid::Union{Integer,Missing},
        formula::Union{AbstractString,Missing}=missing)
    db = _reagent_cache_db()
    mw = ismissing(molecular_weight) ? "NULL" : molecular_weight
    d = ismissing(density) ? "NULL" : density
    cid = ismissing(pubchemid) ? "NULL" : pubchemid
    DBInterface.execute(db,"INSERT OR IGNORE INTO Reagents(LabID,Name,Type,MolecularWeight,Density,CID,Formula) VALUES(?,?,?,$mw,$d,$cid,?)",
        (lab_id,name,string(type),formula))
    return nothing
end

# The chemistry argument of an @reagent line: a formula if there is one, `opaque` if the reagent was
# declared opaque and nothing is known about its mass, otherwise the stored molecular weight.
function _chemistry_argument(formula,mw,opaque::Bool)
    ismissing(formula) || return "\"$formula\""
    ismissing(mw) && return opaque ? "opaque" : "missing"
    return "$(mw)u\"g/mol\""
end

_reagent_line(lab_id,name,type,mw,density,pubchemid;formula=missing,opaque::Bool=false) =
    "@reagent $lab_id \"$name\" $type $(_chemistry_argument(formula,mw,opaque)) $(ismissing(density) ? "missing" : "$(density)u\"g/mL\"") $(ismissing(pubchemid) ? "missing" : pubchemid)"

"""
    register_reagent!(type::DataType,lab_id::AbstractString,name::AbstractString,pubchemid::Union{Integer,Missing}=missing;opaque::Bool=false)

Author-time tool: look up `lab_id`'s formula, molecular weight, and density in the local cache
([`chemical_cache_path`](@ref)); on a cache miss, fetch them from PubChem via
[`get_molecular_formula`](@ref) and [`get_mw_density`](@ref) (requires `pubchemid`) and cache the
result. Returns a ready-to-paste `@reagent` line -- it does not `eval` anything or write to
`solids.jl`/`liquids.jl` itself. Paste the returned line into the appropriate file (alphabetized) and
commit.

`type` must be [`CHESSCore.Solid`](@ref) or [`CHESSCore.Liquid`](@ref). The line gives the reagent's
elemental formula, from PubChem, in place of a molecular weight, so the weight is derived from atomic
masses. PubChem describes the compound of the PubChem ID, so check that it is the form that is
actually weighed out: a hydrate needs the hydrate's PubChem ID, and a salt that dissolves into ions
needs a `Dissolution` in place of the formula (see [`@reagent`](@ref)). When PubChem's formula cannot
be used, because it is charged or cannot be read as an elemental formula, the tool warns and the line
falls back to the stored molecular weight.

Omit `pubchemid` for a compound with no PubChem entry, such as a rich-media broth. The line then has
`missing` chemistry, or `opaque` if `opaque=true` for an undefined mixture whose atoms are
intentionally not described.

Example:
```julia-repl
julia> register_reagent!(CHESSCore.Solid,"boric_acid","Boric Acid",7628)
"@reagent boric_acid \\"Boric Acid\\" Solid \\"BH3O3\\" 1.435u\\"g/mL\\" 7628"
```
"""
function register_reagent!(type::DataType,lab_id::AbstractString,name::AbstractString,pubchemid::Union{Integer,Missing}=missing;opaque::Bool=false)
    cached = _cached_reagent(lab_id)
    if !isnothing(cached)
        mw = ismissing(cached.MolecularWeight) ? missing : cached.MolecularWeight
        d = ismissing(cached.Density) ? missing : cached.Density
        cid = ismissing(cached.CID) ? missing : cached.CID
        formula = ismissing(cached.Formula) ? missing : cached.Formula
        if ismissing(formula) && !ismissing(cid)
            # a row cached before formulas were recorded: look the formula up now
            formula = _fetch_formula(cid,0)
            if !ismissing(formula)
                DBInterface.execute(_reagent_cache_db(),"UPDATE Reagents SET Formula = ? WHERE LabID = ?",(formula,lab_id))
            end
        end
        ismissing(formula) || _check_formula_mass(lab_id,formula,mw)
        return _reagent_line(lab_id,name,type,mw,d,cid;formula,opaque)
    end
    if ismissing(pubchemid)
        _cache_reagent!(lab_id,name,type,missing,missing,missing)
        return _reagent_line(lab_id,name,type,missing,missing,missing;opaque)
    end
    molecular_weight,density = get_mw_density(pubchemid)
    formula = _fetch_formula(pubchemid,0)
    ismissing(formula) || _check_formula_mass(lab_id,formula,molecular_weight)
    _cache_reagent!(lab_id,name,type,molecular_weight,density,pubchemid,formula)
    return _reagent_line(lab_id,name,type,molecular_weight,density,pubchemid;formula,opaque)
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
            Formula TEXT,
            Unique(Name),
            Unique(CID)
        );
        """)
    _ensure_formula_column!(db,"Chemicals")
    return db
end

function _cached_chemical(lab_id::AbstractString)
    db = _chemical_cache_db()
    out = DBInterface.execute(db,"SELECT * FROM Chemicals WHERE LabID = ?",(lab_id,)) |> DataFrame
    return nrow(out) == 0 ? nothing : out[1,:]
end

function _cache_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,
        molecular_weight::Union{Real,Missing},pubchemid::Integer,formula::Union{AbstractString,Missing}=missing)
    db = _chemical_cache_db()
    mw = ismissing(molecular_weight) ? "NULL" : molecular_weight
    DBInterface.execute(db,"INSERT OR IGNORE INTO Chemicals(LabID,Name,Charge,MolecularWeight,CID,Formula) VALUES(?,?,?,$mw,?,?)",
        (lab_id,name,charge,pubchemid,formula))
    return nothing
end

_chemical_line(lab_id,name,charge,mw;formula=missing) =
    "@species $lab_id \"$name\" $charge $(ismissing(formula) ? "$(mw)u\"g/mol\"" : "\"$formula\"")"

"""
    register_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,pubchemid::Integer)

Author-time tool, mirroring [`register_reagent!`](@ref) for [`CHESSCore.Species`](@ref) (ions and
neutral species) instead of [`CHESSCore.Reagent`](@ref)s: looks up `lab_id`'s formula and molecular
weight in the local cache ([`chemical_cache_path`](@ref)); on a cache miss, fetches them from PubChem
via [`get_molecular_formula`](@ref) and [`get_mw_density`](@ref) (density is fetched but discarded --
`Species` has no density field) and caches the result. Returns a ready-to-paste `@species` line giving
the elemental formula, from which the molecular weight is derived. PubChem writes an ion's charge as a
suffix of its formula (`"Na+"`, `"O4S-2"`); the tool removes it after checking that it agrees with
`charge`. When the formula cannot be used, because its charge disagrees or it cannot be read as an
elemental formula, the tool warns and the line falls back to the stored molecular weight. The line
carries no PubChem ID, so the ID is authoring convenience only, not permanent provenance. Paste the
returned line into the appropriate file in `chemicals/` and commit.

Example:
```julia-repl
julia> register_chemical!("Na⁺","Na+",1,923)
"@species Na⁺ \\"Na+\\" 1 \\"Na\\""
```
"""
function register_chemical!(lab_id::AbstractString,name::AbstractString,charge::Integer,pubchemid::Integer)
    cached = _cached_chemical(lab_id)
    if !isnothing(cached)
        mw = ismissing(cached.MolecularWeight) ? missing : cached.MolecularWeight
        formula = ismissing(cached.Formula) ? missing : cached.Formula
        if ismissing(formula)
            # a row cached before formulas were recorded: look the formula up now
            formula = _fetch_formula(pubchemid,charge)
            if !ismissing(formula)
                DBInterface.execute(_chemical_cache_db(),"UPDATE Chemicals SET Formula = ? WHERE LabID = ?",(formula,lab_id))
            end
        end
        ismissing(formula) || _check_formula_mass(lab_id,formula,mw)
        return _chemical_line(lab_id,name,charge,mw;formula)
    end
    molecular_weight,_ = get_mw_density(pubchemid)
    formula = _fetch_formula(pubchemid,charge)
    ismissing(formula) || _check_formula_mass(lab_id,formula,molecular_weight)
    _cache_chemical!(lab_id,name,charge,molecular_weight,pubchemid,formula)
    return _chemical_line(lab_id,name,charge,molecular_weight;formula)
end
