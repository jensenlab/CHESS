






function upload_operation(fun::Function)
    opfun_dict=Dict(
        activate! => upload_activity,
        deactivate! => upload_activity,
        toggle_activity! => upload_activity,
        lock! => upload_lock,
        unlock! => upload_lock,
        toggle_lock! => upload_lock,
        move_into! => upload_movement,
        transfer! => upload_transfer,
        set_attribute! => upload_environment_attribute,
        record_read! => upload_read,
        assign_barcode! => update_barcode
    )
    return opfun_dict[fun]
end


"""
    upload(fun::Funciton,args...;time=DateTime=Dates.now())

Execute and upload a CHESS operation to a CHESS Database. If an error occurs in either execution or uploading, [`upload`](@ref) will return an error and rollback any changes to the database

See [`upload_operation`](@ref) for the list of supported operations. If `instrument` is given, it's
passed to `fun` itself (which gates capability, e.g. via `CHESSCore._check_capability`, for the four
operations that support it) and used to compute `instrument_id` for attribution when persisting --
`upload`/`update` don't re-check capability themselves, since it already happened inside `fun`.

#Examples

```julia
julia> connect_SQLite("test_db.db")

julia> upload(transfer!,locA,locB,5u"g")
julia> upload(set_attribute!,locA,Temperature(10u"°C"))
```
"""
function upload(fun::Function,args...;ledger_id::Union{Integer,Nothing}=nothing,time::DateTime=Dates.now(),
        instrument::Union{Instrument,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    CHESSCore.assert_all_committed(args...)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    ledger_id = something(ledger_id, append_ledger())
    up_fun=upload_operation(fun)
    function upload_transaction()
        fun(args...;instrument=instrument)
        up_fun(args...;ledger_id=ledger_id,time=time,instrument_id=instrument_id,instrument_time=instrument_time)
    end
    sql_transaction(upload_transaction)
    return ledger_id
end


    




"""
   upload_activity(location::Location)

Add an entry to the Activity table a [`Locaiton`](@ref)
    
Locations can be toggled between an active and inactive state. Activity can be used to show or hide locations in user interfaces.  
"""
function upload_activity(location::Location;ledger_id::Integer=append_ledger(),time::DateTime=Dates.now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    execute_db("INSERT OR IGNORE INTO Activity(LedgerID,LocationID,IsActive,Time) Values(?,?,?,?)",
        (ledger_id,location_id(location),Int(is_active(location)),upload_time))
    return nothing
end

function upload_attribute(attribute::Attribute)
    execute_db("INSERT OR IGNORE INTO Attributes(Attribute,BaseUnit) Values(?,?)",
        (string(attribute_kind(attribute).name),string(attribute_unit(attribute))))
    return nothing
end
#=
function upload_barcode(bc::Barcode)
    loc_id=location_id(bc)
    if ismissing(loc_id)
        loc_id= "NULL"
    end 
    return execute_db("INSERT OR IGNORE INTO Barcodes(Barcode,LocationID,Name) Values($(string(barcode(bc))),$(loc_id),$(name(bc)))")
end 
=#


function upload_location_type(k::LocationKind)
    execute_db("INSERT OR IGNORE INTO LocationTypes(Name) Values(?)",(string(k.name),))
    return nothing
end


function upload_new_location(name::String,k::LocationKind)
    upload_location_type(k)
    execute_db("INSERT INTO Locations(Name,Type) Values(?,?)",(name,string(k.name)))
    id=query_db("SELECT Max(ID) FROM Locations")
    return id[1,1]
end

function upload_lock(location::Location;ledger_id::Integer=append_ledger(),time::DateTime=Dates.now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    execute_db("INSERT OR IGNORE INTO Locks(LedgerID,LocationID,IsLocked,Time) Values(?,?,?,?)",
        (ledger_id,location_id(location),Int(is_locked(location)),upload_time))
    return nothing
end

"""
    get_component_id(reagent::Reagent)

Return the `Components.ID`/`Reagents.ComponentID` for `reagent`, uploading it first (via
[`upload_component`](@ref)) if no row with a matching natural key (name/type/molecular weight/
density/pubchem ID) already exists. `Reagent` has a small, fixed set of scalar fields, so identity is
looked up directly by those fields rather than via a content hash.
"""
function get_component_id(reagent::Reagent)
    mw = ismissing(molecular_weight(reagent)) ? missing : ustrip(uconvert(u"g/mol",molecular_weight(reagent)))
    d  = ismissing(density(reagent)) ? missing : ustrip(uconvert(u"g/mL",density(reagent)))
    conds,params = sql_where(
        "Name"=>name(reagent),
        "Type"=>string(typeof(reagent)),
        "MolecularWeight"=>mw,
        "Density"=>d,
        "CID"=>pubchemid(reagent),
    )
    id = query_db("SELECT ComponentID FROM Reagents WHERE $conds",params)
    nrow(id)==1 && return id[1,1]
    return upload_component(reagent)
end

function upload_component(reagent::Reagent)
    mw = ismissing(molecular_weight(reagent)) ? missing : ustrip(uconvert(u"g/mol",molecular_weight(reagent)))
    d  = ismissing(density(reagent)) ? missing : ustrip(uconvert(u"g/mL",density(reagent)))
    pc = pubchemid(reagent)
    execute_db("INSERT INTO Components(Type) Values(?)",("Reagent",))
    id=query_db("SELECT Max(ID) FROM Components")[1,1]
    execute_db("INSERT INTO Reagents(ComponentID,Name,Type,MolecularWeight,Density,CID) Values(?,?,?,?,?,?)",
        (id,name(reagent),string(typeof(reagent)),mw,d,pc))
    upload_composition(id,reagent)
    return id
end

"""
    get_chemical_id(chem::Chemical)

Return the `Chemicals.ID` for `chem`, uploading it first (via [`upload_chemical`](@ref)) if no row
with a matching natural key (name/charge/molecular weight) already exists.
"""
function get_chemical_id(chem::Chemical)
    mw = ismissing(molecular_weight(chem)) ? missing : ustrip(uconvert(u"g/mol",molecular_weight(chem)))
    conds,params = sql_where(
        "Name"=>name(chem),
        "Charge"=>charge(chem),
        "MolecularWeight"=>mw,
    )
    id=query_db("SELECT ID FROM Chemicals WHERE $conds",params)
    nrow(id)==1 && return id[1,1]
    return upload_chemical(chem)
end

"""
    upload_chemical(chem::Chemical)

Insert `chem` into the `Chemicals` registry (the DB counterpart of [`Chemical`](@ref) dissociation
identities -- distinct from [`Reagents`](@ref)/`Components`, since a `Chemical` never participates in
a `Stock` directly). Returns its `Chemicals.ID`.
"""
function upload_chemical(chem::Chemical)
    mw = ismissing(molecular_weight(chem)) ? missing : ustrip(uconvert(u"g/mol",molecular_weight(chem)))
    execute_db("INSERT OR IGNORE INTO Chemicals(Name,Charge,MolecularWeight) Values(?,?,?)",(name(chem),charge(chem),mw))
    return get_chemical_id(chem)
end

"""
    upload_composition(reagent_component_id::Integer, reagent::Reagent)

Persist `reagent`'s currently-resolved [`composition`](@ref) (`composition(reagent).products`) as
`CompositionRules` rows -- the DB counterpart of the in-memory `composition_rules` registry. Called
whenever a `Reagent` component is uploaded, so a reagent reconstructed from the database (see
`get_component`, `reconstruct_contents.jl`) can restore its dissociation rule without depending on the
defining lab module being loaded in that session.
"""
function upload_composition(reagent_component_id::Integer,reagent::Reagent)
    for (chem,coeff) in composition(reagent).products
        chem_id=get_chemical_id(chem)
        execute_db("INSERT OR IGNORE INTO CompositionRules(ReagentComponentID,ChemicalID,Coefficient) Values(?,?,?)",
            (reagent_component_id,chem_id,coeff))
    end
    return nothing
end

"""
    get_component_id(str::Organism)

Return the `Components.ID`/`Organisms.ComponentID` for `str`, uploading it first (via
[`upload_component`](@ref)) if no row with a matching natural key (genus/species/strain) already
exists.
"""
function get_component_id(str::Organism)
    conds,params = sql_where(
        "Genus"=>genus(str),
        "Species"=>species(str),
        "Strain"=>strain(str),
    )
    id = query_db("SELECT ComponentID FROM Organisms WHERE $conds",params)
    nrow(id)==1 && return id[1,1]
    return upload_component(str)
end

function upload_component(str::Organism)
    execute_db("INSERT INTO Components(Type) Values(?)",("Organism",))
    id=query_db("SELECT Max(ID) FROM Components")[1,1]
    execute_db("INSERT INTO Organisms(ComponentID,Genus,Species,Strain) Values(?,?,?,?)",
        (id,genus(str),species(str),strain(str)))
    return id
end




"""
    upload_transfer(sourceID::Integer,destinationID::Integer,quantity::Real,unit::AbstractString)

commit a transfer of `quantity` from  well `sourceID` to well `destinationID`
"""
function upload_transfer(source::Well,destination::Well,quant::Union{Unitful.Mass,Unitful.Volume},configuration::AbstractString="";ledger_id::Integer=append_ledger(),time::DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    instrument_upload_time = isnothing(instrument_time) ? nothing : db_time(instrument_time)
    execute_db("""INSERT INTO Transfers(LedgerID,Source,Destination,Quantity,Unit,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?,?,?)""",
        (ledger_id,location_id(source),location_id(destination),ustrip(quant),string(unit(quant)),upload_time,instrument_id,instrument_upload_time))
    return nothing
end



function upload_movement(parent::Location,child::Location,lock::Bool=false;ledger_id::Integer=append_ledger(),time::DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    instrument_upload_time = isnothing(instrument_time) ? nothing : db_time(instrument_time)
    execute_db("INSERT OR IGNORE INTO Movements(LedgerID,Parent,Child,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?)",
        (ledger_id,location_id(parent),location_id(child),upload_time,instrument_id,instrument_upload_time))
    if lock
        upload_lock(child;time=time) # only needed if the lock flag is true. This means that the lock state has changed (you had to be unlocked to move in the first place)
    end
    return nothing
end

function upload_environment_attribute(loc::Location,attr::Attribute;ledger_id::Integer=append_ledger(),time::Dates.DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    instrument_upload_time = isnothing(instrument_time) ? nothing : db_time(instrument_time)
    val=CHESSCore.value(attr)
    if ismissing(val) || isunknown(val)
        val = missing
    end
    un = attribute_unit(attr)
    upload_attribute(attr)
    execute_db("""INSERT OR IGNORE INTO EnvironmentAttributes(LedgerID,LocationID,Attribute,Value,Unit,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?,?,?)""",
        (ledger_id,location_id(loc),string(attribute_kind(attr).name),val,string(un),upload_time,instrument_id,instrument_upload_time))
    return nothing
end


function upload_barcode(bc::Barcode)
    loc_id=location_id(bc)
    n=name(bc)
    execute_db("INSERT OR IGNORE INTO Barcodes(Barcode,LocationID,Name) Values(?,?,?)",(string(barcode(bc)),loc_id,n))
end

function update_barcode(bc::Barcode,loc::Location;kwargs...)
    loc_id=location_id(bc)
    if !ismissing(loc_id) && loc_id != location_id(loc)
        error("barcode location id does not match the supplied location")
    end
    execute_db("UPDATE Barcodes SET LocationID = ? WHERE Barcode = ?",(loc_id,string(barcode(bc))))
    return nothing
end


"""
    upload_read(loc::Location,read::Read; ledger_id, time, instrument_id, instrument_time)

Persist `read` (a [`Read`](@ref)) for `loc`. Pure persistence -- matches
[`upload_movement`](@ref)/[`upload_transfer`](@ref)/[`upload_environment_attribute`](@ref): the
in-memory mutation ([`record_read!`](@ref)) is the caller's responsibility (normally
`upload(record_read!,loc,read;instrument=...)`, which calls both). `instrument_time` is accepted and
ignored -- `read`'s own [`read_time`](@ref) is what's stored as `Reads.InstrumentTime`, since a `Read`
carries its own recorded time intrinsically. `Value`/`Unit` come from `quantity(read)`: quantitative
reads store a numeric string + unit; qualitative reads store the raw string with a `NULL` unit.
"""
function upload_read(loc::Location,read::Read;ledger_id=append_ledger(),time::Dates.DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    instrument_upload_time = isnothing(read_time(read)) ? nothing : db_time(read_time(read))
    q = quantity(read)
    val = (ismissing(q) || isunknown(q)) ? missing : is_qualitative(read_kind(read)) ? q : string(ustrip(q))
    un = (ismissing(q) || isunknown(q) || is_qualitative(read_kind(read))) ? missing : string(unit(q))
    execute_db("INSERT OR IGNORE INTO Reads(LedgerID,LocationID,Type,Value,Unit,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?,?,?)",
        (ledger_id,location_id(loc),string(read_kind(read).name),val,un,upload_time,instrument_id,instrument_upload_time))
    return nothing
end

"""
    upload_instrument_setting(instrument::Instrument,setting::String,value; ledger_id, time, instrument_time)

Append a new revision of `instrument`'s `setting` to `InstrumentSettings` -- the ledger's "amend"
operation for instrument settings, mirroring [`upload_environment_attribute`](@ref)'s shape.
`value` is stored as text (see the design note on `InstrumentSettings` -- settings may be non-numeric).
Returns `ledger_id` -- since `SequenceID` can shift after the fact (`insert_ledger`/`replace_ledger`),
resolve this revision's *current* sequence position later via `get_sequence_id(ledger_id)` rather than
caching a `SequenceID` directly.
"""
function upload_instrument_setting(instrument::Instrument,setting::String,value;ledger_id::Integer=append_ledger(),time::DateTime=now(),
        instrument_time::Union{DateTime,Nothing}=nothing)
    upload_time=db_time(time)
    instrument_upload_time = isnothing(instrument_time) ? nothing : db_time(instrument_time)
    execute_db("INSERT INTO InstrumentSettings(LedgerID,InstrumentID,Setting,Value,InstrumentTime,Time) Values(?,?,?,?,?,?)",
        (ledger_id,location_id(instrument),setting,string(value),instrument_upload_time,upload_time))
    return ledger_id
end



function upload_experiment(name::AbstractString,user::String,is_public=false;time=Dates.now())
    upload_time=db_time(time)
    execute_db("""INSERT INTO Experiments(Name,User,IsPublic,Time) Values(?,?,?,?)""",
        (name,user,Int(is_public),upload_time))
    return get_last_experiment_id()
end

function upload_run(run::Run)
    control_str = join(controls(run),",")
    blank_str = join(blanks(run),",")
    execute_db("INSERT OR IGNORE INTO Runs(ExperimentID,LocationID,Controls,Blanks) Values(?,?,?,?)",
        (experiment_id(run),location_id(run),control_str,blank_str))
    return get_last_run_id()
end




