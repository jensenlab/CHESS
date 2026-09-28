# Observations: ground-truth statements about one facet of a location at a ledger position, recorded
# without any claim about how the state came about. Replay applies them in sequence with the
# operations: component and cost observations inside `reconstruct_contents`, and the others through
# the `*_events` unions in reconstruction_utils.jl.

const observation_tables = ("ObservedComponents","ObservedCosts","ObservedAttributes","ObservedParents","ObservedLocks","ObservedActivity")

_optional_db_time(t) = isnothing(t) ? nothing : db_time(t)

function _insert_observation(table::String,columns::Vector{String},values::Tuple;ledger_id::Integer,time::DateTime=Dates.now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing,read_ledger_id::Union{Integer,Nothing}=nothing)
    cols=vcat("LedgerID",columns,"Time","InstrumentID","InstrumentTime","ReadLedgerID")
    execute_db("INSERT INTO $table($(join(cols,","))) Values($(join(fill("?",length(cols)),",")))",
        (ledger_id,values...,db_time(time),instrument_id,_optional_db_time(instrument_time),read_ledger_id))
    return nothing
end


"""
    upload_observation(well::Well, component::StockComponent, quant; ledger_id, time, instrument_id, instrument_time, read_ledger_id)
    upload_observation(loc::Location, attribute::Attribute; ...)
    upload_observation(child::Location, parent::Union{Location,Nothing}; ...)
    upload_observation(loc::Location, facet::Symbol, value; ...)

Persist one observation (see [`observe!`](@ref) for the meaning of each form). Pure persistence,
like [`upload_transfer`](@ref): the in-memory change is the caller's responsibility, normally through
`upload(observe!, ...)`, `update(observe!, ...)` or [`observe`](@ref). `read_ledger_id` optionally
links the observation to the ledger entry of the [`Read`](@ref) that produced it.

An attribute observation whose value matches what `loc` already inherits from its parent (and `loc`
has no value of its own) is stored as "confirmed inherited": replay skips it, so `loc` keeps following
its parent. The attribute is removed from `loc`'s own attributes in memory to match.
"""
function upload_observation(well::Well,component::StockComponent,quant::Unitful.Quantity;ledger_id::Integer=append_ledger(),kwargs...)
    _insert_observation("ObservedComponents",["LocationID","ComponentID","Quantity","Unit"],
        (location_id(well),get_component_id(component),Float64(ustrip(quant)),string(unit(quant)));ledger_id=ledger_id,kwargs...)
end

function upload_observation(loc::Location,attr::Attribute;ledger_id::Integer=append_ledger(),kwargs...)
    inherited=_matches_inherited(loc,attr,ledger_id)
    if inherited
        delete!(CHESSCore.attributes(loc),attribute_kind(attr).name)
        CHESSCore.invalidate_environment!(loc)
    end
    upload_observation(loc,attr,inherited;ledger_id=ledger_id,kwargs...)
end

function upload_observation(loc::Location,attr::Attribute,inherited::Bool;ledger_id::Integer=append_ledger(),kwargs...)
    val=CHESSCore.value(attr)
    if ismissing(val) || isunknown(val)
        val=missing
    end
    upload_attribute(attr)
    _insert_observation("ObservedAttributes",["LocationID","Attribute","Value","Unit","IsInherited"],
        (location_id(loc),string(attribute_kind(attr).name),val,string(attribute_unit(attr)),Int(inherited));ledger_id=ledger_id,kwargs...)
end

function upload_observation(child::Location,newparent::Union{Location,Nothing};ledger_id::Integer=append_ledger(),kwargs...)
    parent_id=isnothing(newparent) ? missing : location_id(newparent)
    _insert_observation("ObservedParents",["Parent","Child"],(parent_id,location_id(child));ledger_id=ledger_id,kwargs...)
end

function upload_observation(loc::Location,facet::Symbol,value;ledger_id::Integer=append_ledger(),kwargs...)
    if facet === :cost
        _insert_observation("ObservedCosts",["LocationID","Cost"],(location_id(loc),Float64(value));ledger_id=ledger_id,kwargs...)
    elseif facet === :locked
        _insert_observation("ObservedLocks",["LocationID","IsLocked"],(location_id(loc),Int(value));ledger_id=ledger_id,kwargs...)
    elseif facet === :active
        _insert_observation("ObservedActivity",["LocationID","IsActive"],(location_id(loc),Int(value));ledger_id=ledger_id,kwargs...)
    else
        throw(ArgumentError("unknown observable facet :$facet; expected :cost, :locked or :active"))
    end
end

# true when `loc` has no value of its own for `attr`'s kind just before `ledger_id`, and the value it
# inherits from its parents there equals `attr`
function _matches_inherited(loc::Location,attr::Attribute,ledger_id::Integer)
    ismissing(CHESSCore.value(attr)) && return false
    prior=get_sequence_id(ledger_id)-1
    nm=attribute_kind(attr).name
    own=CHESSCore.attributes(reconstruct_attributes(location_id(loc),prior))
    haskey(own,nm) && !ismissing(CHESSCore.value(own[nm])) && return false
    env=environment(reconstruct_environment(location_id(loc),prior))
    return haskey(env,nm) && env[nm] == attr
end


"""
    observe(loc::Location, facet...; read_ledger_id=nothing, ledger_id=nothing, time=Dates.now(), instrument=nothing, instrument_time=nothing)
    observe(loc::Location; recursive=true, read_ledger_id=nothing, ledger_id=nothing, time=Dates.now(), instrument=nothing, instrument_time=nothing)

Record an observation of `loc` in the database: a statement of what its state *is* at a ledger
position, whatever history predicted there. Later operations replay on top of it, and nothing before
it can change the observed value. Returns the ledger id of the observation.

With `facet` arguments, observe one fact, e.g. `observe(well, rgt"glucose", 2u"g")` (see
[`observe!`](@ref) for every form); `loc` is updated in memory too.

With no `facet`, observe all of `loc` as it currently is in memory: every stock component (and a zero
for any component history predicts but `loc` lacks), its cost, its own attributes (and `missing` for
any own attribute history predicts but `loc` lacks), its parent, lock and activity. `recursive`
also observes every location inside `loc`. All of it shares one ledger entry.

By default the observation is appended to the ledger. Pass the `ledger_id` of an entry made with
[`insert_ledger`](@ref) to record it at an earlier point: the change is then validated and the
caches after it repaired, as with [`update`](@ref).

See also: [`observation_discrepancies`](@ref), [`backfill_observations`](@ref).
"""
function observe(loc::Location,facet...;read_ledger_id::Union{Integer,Nothing}=nothing,ledger_id::Union{Integer,Nothing}=nothing,
        time::DateTime=Dates.now(),instrument::Union{Location,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    CHESSCore.assert_all_committed(loc,filter(x->x isa Location,facet)...)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    appended = isnothing(ledger_id)
    ledger_id = something(ledger_id,append_ledger())
    function observe_transaction()
        CHESSCore.observe!(loc,facet...;instrument=instrument)
        upload_observation(loc,facet...;ledger_id=ledger_id,time=time,instrument_id=instrument_id,
            instrument_time=instrument_time,read_ledger_id=read_ledger_id)
        appended || process_update(ledger_id)
    end
    sql_transaction(observe_transaction)
    return ledger_id
end

function observe(loc::Location;recursive::Bool=true,read_ledger_id::Union{Integer,Nothing}=nothing,ledger_id::Union{Integer,Nothing}=nothing,
        time::DateTime=Dates.now(),instrument::Union{Location,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    nodes = recursive ? vcat(loc,get_all_within(loc,Location)) : Location[loc]
    CHESSCore.assert_all_committed(nodes...)
    isnothing(CHESSCore.parent(loc)) || CHESSCore.assert_all_committed(CHESSCore.parent(loc))
    CHESSCore._check_capability(instrument,observe!)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    appended = isnothing(ledger_id)
    ledger_id = something(ledger_id,append_ledger())
    function observe_transaction()
        prior=get_sequence_id(ledger_id)-1
        ids=location_id.(nodes)
        predicted_attrs=Dict(zip(ids,CHESSCore.attributes.(reconstruct_attributes(ids,prior))))
        well_ids=[location_id(n) for n in nodes if n isa Well]
        predicted_stocks=isempty(well_ids) ? Dict{Int,Stock}() : Dict(zip(well_ids,CHESSCore.stock.(reconstruct_contents(well_ids,prior))))
        for n in nodes
            for f in _full_facets(n,get(predicted_stocks,location_id(n),Empty()),predicted_attrs[location_id(n)])
                upload_observation(f...;ledger_id=ledger_id,time=time,instrument_id=instrument_id,
                    instrument_time=instrument_time,read_ledger_id=read_ledger_id)
            end
        end
        appended || process_update(ledger_id)
    end
    sql_transaction(observe_transaction)
    return ledger_id
end

# every component of a stock with its quantity
_components(s::Stock) = merge(Dict{StockComponent,Any}(),solids(s),liquids(s),organisms(s))

# `upload_observation` argument tuples declaring all of `n` as it is in memory. Components and own
# attributes that `n` lacks but history predicts are declared absent.
function _full_facets(n::Location,predicted_stock::Stock,predicted_attrs::AttributeDict)
    facets=Tuple[]
    if n isa Well
        current=_components(CHESSCore.stock(n))
        for (c,q) in current
            push!(facets,(n,c,q))
        end
        for (c,q) in _components(predicted_stock)
            haskey(current,c) || push!(facets,(n,c,zero(q)))
        end
        push!(facets,(n,:cost,CHESSCore.cost(n)))
    end
    own=CHESSCore.attributes(n)
    for attr in values(own)
        push!(facets,(n,attr,false))
    end
    for (nm,attr) in predicted_attrs
        haskey(own,nm) || push!(facets,(n,Attribute(attribute_kind(attr),missing),false))
    end
    if !(n isa Well)
        push!(facets,(n,CHESSCore.parent(n)))
        push!(facets,(n,:locked,is_locked(n)))
    end
    push!(facets,(n,:active,is_active(n)))
    return facets
end

# `upload_observation` argument tuples declaring what a newly committed location `n` holds beyond a
# fresh location's defaults (empty, no cost or attributes, unlocked, active, no parent)
function _genesis_facets(n::Location)
    facets=Tuple[]
    if n isa Well
        for (c,q) in _components(CHESSCore.stock(n))
            push!(facets,(n,c,q))
        end
        CHESSCore.cost(n) == 0 || push!(facets,(n,:cost,CHESSCore.cost(n)))
    end
    for attr in values(CHESSCore.attributes(n))
        ismissing(CHESSCore.value(attr)) || push!(facets,(n,attr,false))
    end
    if n isa GenericLocation
        for child in children(n)
            push!(facets,(child,n))
        end
    end
    !(n isa Well) && is_locked(n) && push!(facets,(n,:locked,true))
    is_active(n) || push!(facets,(n,:active,false))
    return facets
end


"""
    isa_observation(ledger_id::Integer)

`true` if the ledger entry `ledger_id` holds at least one observation.
"""
function isa_observation(ledger_id::Integer)
    return any(tbl -> nrow(query_db("SELECT 1 FROM $tbl WHERE LedgerID = ? LIMIT 1",(ledger_id,))) > 0,observation_tables)
end

# the observation rows of every revision of `sequence_id`'s ledger slot, one DataFrame per table
function _observation_participants(sequence_id::Integer)
    entry=query_join_vector(get_all_ledger_ids(sequence_id))
    return Dict(tbl => query_db("SELECT * FROM $tbl WHERE LedgerID IN $entry") for tbl in observation_tables)
end

_content_participants(p) = Vector{Int}(unique(skipmissing(vcat(p["ObservedComponents"].LocationID,p["ObservedCosts"].LocationID))))

function validate_observation(ledger_id::Integer;encumbrances=false)
    seq_id=get_sequence_id(ledger_id)
    p=_observation_participants(seq_id)
    last_seq=get_last_sequence_id()
    wells=_content_participants(p)
    isempty(wells) || reconstruct_contents(wells,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
    moved=p["ObservedParents"]
    for row in eachrow(moved)
        ismissing(row.Parent) || reconstruct_children(row.Parent,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
        reconstruct_parent(row.Child,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
    end
    for loc_id in unique(p["ObservedAttributes"].LocationID)
        reconstruct_attributes(loc_id,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
    end
    for loc_id in unique(p["ObservedLocks"].LocationID)
        reconstruct_lock(loc_id,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
    end
    for loc_id in unique(p["ObservedActivity"].LocationID)
        reconstruct_activity(loc_id,last_seq,Dates.now(),seq_id;encumbrances=encumbrances)
    end
    return nothing
end

# repair the caches of everything observed at `ledger_id`, from sequence point `from` on
function repair_observation_caches(ledger_id::Integer,from::Integer=get_sequence_id(ledger_id))
    p=_observation_participants(get_sequence_id(ledger_id))
    seq_id=from
    wells=_content_participants(p)
    isempty(wells) || repair_content_caches(Vector{Int}(wells),seq_id)
    attrs=unique(p["ObservedAttributes"].LocationID)
    isempty(attrs) || repair_environment_attribute_caches(Vector{Int}(attrs),seq_id)
    moved=p["ObservedParents"]
    if nrow(moved) > 0
        repair_movement_caches(unique(collect(skipmissing(moved.Parent))),Vector{Int}(unique(moved.Child)),seq_id)
    end
    locks=unique(p["ObservedLocks"].LocationID)
    isempty(locks) || repair_lock_caches(Vector{Int}(locks),seq_id)
    active=unique(p["ObservedActivity"].LocationID)
    isempty(active) || repair_activity_caches(Vector{Int}(active),seq_id)
    return nothing
end


"""
    observation_discrepancies(location_ids; sequence_id=get_last_sequence_id(), time=Dates.now())

Compare every observation of `location_ids` up to `sequence_id` with what history predicted just
before it, and return the ones that differ as a `DataFrame` with columns `LedgerID`, `SequenceID`,
`LocationID`, `Facet` (`"component"`, `"cost"`, `"attribute"`, `"parent"`, `"locked"` or `"active"`),
`Key` (the component or attribute, else `missing`), `Predicted` and `Observed`.

Attributes are compared with the location's effective environment, so a value it inherits counts.
Parents are reported as location ids (`missing` for none).
"""
function observation_discrepancies(location_ids::Vector{<:Integer};sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    out=DataFrame(LedgerID=Int[],SequenceID=Int[],LocationID=Int[],Facet=String[],Key=Any[],Predicted=Any[],Observed=Any[])
    ledger_time=db_time(time)
    entry=query_join_vector(location_ids)
    subset="""WITH ledger_subset (ID,SequenceID,Time)
        AS(SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $sequence_id GROUP BY SequenceID)"""
    rows(tbl,loc_col="LocationID") = query_db("$subset SELECT o.*, l.SequenceID FROM $tbl o INNER JOIN ledger_subset l ON o.LedgerID = l.ID WHERE o.$loc_col IN $entry ORDER BY l.SequenceID")
    report!(row,loc_id,facet,key,predicted,observed) = push!(out,(row.LedgerID,row.SequenceID,loc_id,facet,key,predicted,observed))

    for row in eachrow(rows("ObservedComponents"))
        observed=row.Quantity*_parse_unit(row.Unit)
        component=get_component(row.ComponentID)
        comps=_components(CHESSCore.stock(reconstruct_contents(row.LocationID,row.SequenceID-1)))
        predicted=haskey(comps,component) ? uconvert(unit(observed),comps[component]) : zero(observed)
        isapprox(predicted,observed;rtol=1e-9) || report!(row,row.LocationID,"component",component,predicted,observed)
    end
    for row in eachrow(rows("ObservedCosts"))
        predicted=CHESSCore.cost(reconstruct_contents(row.LocationID,row.SequenceID-1))
        isapprox(predicted,row.Cost;rtol=1e-9) || report!(row,row.LocationID,"cost",missing,predicted,row.Cost)
    end
    for row in eachrow(rows("ObservedAttributes"))
        kind=get_attribute(row.Attribute)
        observed=ismissing(row.Value) ? Attribute(kind,missing) : kind(row.Value*_parse_unit(row.Unit))
        env=environment(reconstruct_environment(row.LocationID,row.SequenceID-1))
        predicted=get(env,kind.name,Attribute(kind,missing))
        isequal(CHESSCore.value(predicted),CHESSCore.value(observed)) || report!(row,row.LocationID,"attribute",kind.name,predicted,observed)
    end
    for row in eachrow(rows("ObservedParents","Child"))
        prt=CHESSCore.parent(reconstruct_parent(row.Child,row.SequenceID-1))
        predicted=isnothing(prt) ? missing : location_id(prt)
        isequal(predicted,row.Parent) || report!(row,row.Child,"parent",missing,predicted,row.Parent)
    end
    for row in eachrow(rows("ObservedLocks"))
        predicted=is_locked(reconstruct_lock(row.LocationID,row.SequenceID-1))
        predicted == Bool(row.IsLocked) || report!(row,row.LocationID,"locked",missing,predicted,Bool(row.IsLocked))
    end
    for row in eachrow(rows("ObservedActivity"))
        predicted=is_active(reconstruct_activity(row.LocationID,row.SequenceID-1))
        predicted == Bool(row.IsActive) || report!(row,row.LocationID,"active",missing,predicted,Bool(row.IsActive))
    end
    sort!(out,:SequenceID)
    return out
end

observation_discrepancies(location_id::Integer;kwargs...) = observation_discrepancies([location_id];kwargs...)


"""
    backfill_observations()

One-off migration for a database written before observations existed, where some state is known only
from a cache (for example a bottle's contents, cached when it was committed). Returns the number of
ledger entries added.

Walks every cache in sequence order and compares it with what the ledger alone predicts at that
point. Wherever they differ, the cached state is recorded as observations on a new ledger entry
inserted right after the cache's, and the caches from there on are repaired. Afterwards every cache
can be recomputed from the ledger.

Labware membership is structural rather than recorded, so it stays with the caches: which labware a
well (or anything else filling a labware slot) belongs to, and the grid of slots inside a labware.
"""
function backfill_observations()
    tables=("CachedContents","CachedEnvironments","CachedAncestors","CachedDescendants","CachedLockActivity")
    # repairs write new cache rows as this runs; only the rows that existed beforehand are compared
    max_ids=Dict(tbl => coalesce(query_db("SELECT Max(ID) FROM $tbl")[1,1],0) for tbl in tables)
    union_sql=join(["SELECT LedgerID FROM $tbl" for tbl in tables]," UNION ")
    ledger_ids=query_db("""
        WITH ledger_subset (ID,SequenceID) AS (SELECT Max(ID),SequenceID FROM Ledger GROUP BY SequenceID)
        SELECT l.ID FROM ledger_subset l INNER JOIN ($union_sql) c ON c.LedgerID = l.ID
        GROUP BY l.ID ORDER BY l.SequenceID
        """).ID
    added=0
    for lid in ledger_ids
        seq=get_sequence_id(lid)
        facets=_unexplained_cache_facets(lid,seq,max_ids)
        isempty(facets) && continue
        new_lid=insert_ledger(seq+1)
        for f in facets
            upload_observation(f...;ledger_id=new_lid)
        end
        repair_observation_caches(new_lid,seq)
        added+=1
    end
    return added
end

# the latest pre-existing cache row of each location cached at ledger entry `lid`
function _original_caches(tbl::String,lid::Integer,max_ids)
    return query_db("SELECT *, Max(ID) FROM $tbl WHERE LedgerID = ? AND ID <= ? GROUP BY LocationID",(lid,max_ids[tbl]))
end

_location(id::Integer) = ((n,t)=get_location_info(id); t(id,n))

# `upload_observation` argument tuples for everything cached at `lid` that the ledger alone doesn't
# predict at sequence point `seq`
function _unexplained_cache_facets(lid::Integer,seq::Integer,max_ids)
    facets=Tuple[]

    rows=_original_caches("CachedContents",lid,max_ids)
    if nrow(rows) > 0
        predicted=reconstruct_contents(Vector{Int}(rows.LocationID),seq,Dates.now(),seq-1)
        for (row,w) in zip(eachrow(rows),predicted)
            cached=ismissing(row.StockID) ? Empty() : get_stock(row.StockID)
            was=_components(CHESSCore.stock(w))
            now_=_components(cached)
            for (c,q) in now_
                haskey(was,c) && isapprox(uconvert(unit(q),was[c]),q;rtol=1e-9) || push!(facets,(w,c,q))
            end
            for (c,q) in was
                haskey(now_,c) || push!(facets,(w,c,zero(q)))
            end
            isapprox(CHESSCore.cost(w),row.Cost;rtol=1e-9) || push!(facets,(w,:cost,row.Cost))
        end
    end

    rows=_original_caches("CachedEnvironments",lid,max_ids)
    if nrow(rows) > 0
        predicted=reconstruct_attributes(Vector{Int}(rows.LocationID),seq,Dates.now(),seq-1)
        for (row,loc) in zip(eachrow(rows),predicted)
            was=CHESSCore.attributes(loc)
            for r in eachrow(query_db("SELECT * FROM CachedAttributes WHERE AttributeSetID = ?",(row.AttributeSetID,)))
                kind=get_attribute(r.AttributeID)
                attr=ismissing(r.Value) ? Attribute(kind,missing) : kind(r.Value*_parse_unit(r.Unit))
                haskey(was,kind.name) && isequal(CHESSCore.value(was[kind.name]),CHESSCore.value(attr)) || push!(facets,(loc,attr,false))
            end
            cached=Set(query_db("SELECT AttributeID FROM CachedAttributes WHERE AttributeSetID = ?",(row.AttributeSetID,)).AttributeID)
            for (nm,attr) in was
                string(nm) in cached || ismissing(CHESSCore.value(attr)) || push!(facets,(loc,Attribute(attribute_kind(attr),missing),false))
            end
        end
    end

    # parents, from both sides: a child's own parent cache, and a (non-labware) parent's child set
    parents=Dict{Int,Union{Int,Missing}}()
    rows=_original_caches("CachedAncestors",lid,max_ids)
    if nrow(rows) > 0
        predicted=reconstruct_parent(Vector{Int}(rows.LocationID),seq,Dates.now(),seq-1)
        for (row,loc) in zip(eachrow(rows),predicted)
            loc isa Well && continue # wells are fused to their labware
            !ismissing(row.ParentID) && _location(row.ParentID) isa Labware && continue # as is anything filling a labware slot
            prt=CHESSCore.parent(loc)
            isequal(isnothing(prt) ? missing : location_id(prt),row.ParentID) || (parents[row.LocationID]=row.ParentID)
        end
    end
    rows=_original_caches("CachedDescendants",lid,max_ids)
    for row in eachrow(rows)
        _location(row.LocationID) isa GenericLocation || continue # a labware's wells are structural
        predicted=Set(location_id.(children(reconstruct_children(row.LocationID,seq,Dates.now(),seq-1))))
        for child in query_db("SELECT ChildID FROM CachedChildren WHERE CachedChildSetID = ?",(row.ChildSetID,)).ChildID
            child in predicted || haskey(parents,child) || (parents[child]=row.LocationID)
        end
    end
    for (child,prt) in parents
        push!(facets,(_location(child),ismissing(prt) ? nothing : _location(prt)))
    end

    rows=_original_caches("CachedLockActivity",lid,max_ids)
    if nrow(rows) > 0
        ids=Vector{Int}(rows.LocationID)
        locks=reconstruct_lock(ids,seq,Dates.now(),seq-1)
        active=reconstruct_activity(ids,seq,Dates.now(),seq-1)
        for (row,l,a) in zip(eachrow(rows),locks,active)
            !(l isa Well) && is_locked(l) != Bool(row.IsLocked) && push!(facets,(l,:locked,Bool(row.IsLocked)))
            is_active(a) != Bool(row.IsActive) && push!(facets,(a,:active,Bool(row.IsActive)))
        end
    end
    return facets
end
