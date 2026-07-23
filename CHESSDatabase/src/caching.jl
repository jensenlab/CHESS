function cache(loc::Location,sequence_id::Union{Integer,Nothing}=nothing,time::DateTime=Dates.now())
    CHESSCore.assert_all_committed(loc)
    CHESSCore.assert_all_committed(get_all_within(loc,Location)...)
    sequence_id = something(sequence_id, get_last_sequence_id())
    ledger_id=get_last_ledger_id(sequence_id)
    cache_parent(loc,ledger_id,time)
    cache_children(loc,ledger_id,time)
    cache_environment(loc,ledger_id,time)
    cache_lock_activity(loc,ledger_id,time)
    if typeof(loc) <: CHESSCore.Well
        cache_contents(loc,ledger_id,time)
    end
    return nothing
end


function cache_parent(loc::Location,ledger_id::Integer,time::DateTime=Dates.now())
    upload_time=db_time(time)
    parent_id=location_id(parent(loc))
    execute_db("INSERT INTO CachedAncestors(LocationID,ParentID,LedgerID,Time) Values(?,?,?,?)",
        (location_id(loc),parent_id,ledger_id,upload_time))
    return nothing
end

function cache_children(loc::Location,ledger_id::Integer,time::DateTime=Dates.now())
    child_set_id=cache_children_helper(children(loc))
    upload_time=db_time(time)
    execute_db("INSERT INTO CachedDescendants(LocationID,ChildSetID,LedgerID,Time) Values(?,?,?,?)",
        (location_id(loc),child_set_id,ledger_id,upload_time))
    return nothing
end




function get_child_set_id(c)
    ids=location_id.(c)
    id=query_db("SELECT ID FROM CachedChildSets WHERE ChildSetHash = ?",(hash_bytes(ids),)) # search to see if attribute set is in the database
    if nrow(id)==1
        return id[1,1]
    else
        return nothing

    end
end



function cache_children_helper(c::Matrix{<:Location})
    loc_ids=location_id.(c)
id=get_child_set_id(c)
if isnothing(id)
    execute_db("INSERT OR IGNORE INTO CachedChildSets(ChildSetHash) Values(?)",(hash_bytes(loc_ids),))
    id=get_child_set_id(c)
    rows,cols=size(c)
    for col in 1:cols
        for row in 1:rows
            execute_db("INSERT OR IGNORE INTO CachedChildren(CachedChildSetID,ChildID,RowIdx,ColIdx) Values(?,?,?,?)",
                (id,location_id(c[row,col]),row,col))
        end
    end
end
return id
end

function cache_children_helper(c::Vector{<:Location})
    loc_ids=location_id.(c)
    id=get_child_set_id(c)
    if isnothing(id)
        execute_db("INSERT OR IGNORE INTO CachedChildSets(ChildSetHash) Values(?)",(hash_bytes(loc_ids),))
        id=get_child_set_id(c)
        for child in c
            execute_db("INSERT OR IGNORE INTO CachedChildren(CachedChildSetID,ChildID) Values(?,?)",(id,location_id(child)))
        end
    end
    return id
end

function cache_children_helper(c::Tuple{})
    loc_ids=location_id.(c)
    id=get_child_set_id(c)
    if isnothing(id)
        execute_db("INSERT OR IGNORE INTO CachedChildSets(ChildSetHash) Values(?)",(hash_bytes(loc_ids),))
        id=get_child_set_id(c)
        for child in c
            execute_db("INSERT OR IGNORE INTO CachedChildren(CachedhildSetID,ChildID) Values(?,?)",(id,location_id(child)))
        end
    end
    return id
end


function cache_contents(loc::Well,ledger_id::Integer,time::DateTime=Dates.now())
    stock_id=cache(stock(loc))
    upload_time=db_time(time)
    execute_db("INSERT OR IGNORE INTO CachedContents(LocationID,StockID,LedgerID,Cost,Time) Values(?,?,?,?,?)",
        (location_id(loc),stock_id,ledger_id,cost(loc),upload_time))
    return nothing
end



function get_stock_id(s::Stock)
    id=query_db("SELECT ID FROM CachedStocks WHERE StockHash = ?",(hash_bytes(s),)) # search to see if stock is in the database
    if nrow(id)==1
        return id[1,1]
    else
        return nothing

    end
end



function cache(s::Stock)
    id=get_stock_id(s)
    if isnothing(id)
        execute_db("INSERT OR IGNORE INTO CachedStocks(StockHash) Values(?)",(hash_bytes(s),)) # upload the hash as a new id
        id=get_stock_id(s)
        sols=solids(s)
        for solid in reagents(sols)
            sol_id=get_component_id(solid)
            quant=sols[solid]
            execute_db("INSERT OR IGNORE INTO CachedComponents(StockID,ComponentID,Quantity,Unit) Values(?,?,?,?)",
                (id,sol_id,Float64(ustrip(quant)),string(unit(quant))))
        end
        liqs=liquids(s)
        for liquid in reagents(liqs)
            liq_id=get_component_id(liquid)
            quant=liqs[liquid]
            execute_db("INSERT OR IGNORE INTO CachedComponents(StockID,ComponentID,Quantity,Unit) Values(?,?,?,?)",
                (id,liq_id,Float64(ustrip(quant)),string(unit(quant))))
        end
        for org in organisms(s)
            org_id=get_component_id(org)  # uploads a new organism if necessary
            execute_db("INSERT INTO CachedComponents(StockID,ComponentID) Values(?,?)",(id,org_id))
        end
        return id

    else
        return id
    end

end

function cache_environment(loc::Location,ledger_id::Integer,time::DateTime=Dates.now())
    attr_set_id=cache(attributes(loc))
    upload_time=db_time(time)
    execute_db("INSERT INTO CachedEnvironments(LocationID,AttributeSetID,LedgerID,Time) Values(?,?,?,?)",
        (location_id(loc),attr_set_id,ledger_id,upload_time))
    return nothing
end



function get_attribute_set_id(a::AttributeDict)
    id=query_db("SELECT ID FROM CachedAttributeSets WHERE AttributeSetHash = ?",(hash_bytes(a),)) # search to see if attribute set is in the database
    if nrow(id)==1
        return id[1,1]
    else
        return nothing

    end
end




function cache(a::AttributeDict)
    id=get_attribute_set_id(a)
    if isnothing(id)
        execute_db("INSERT OR IGNORE INTO CachedAttributeSets(AttributeSetHash) Values(?)",(hash_bytes(a),)) # upload the hash as a new id
        id=get_attribute_set_id(a)
        attrs=collect(keys(a))
        for attr in attrs
            val=quantity(a[attr])
            upload_attribute(a[attr])
            execute_db("INSERT OR IGNORE INTO CachedAttributes(AttributeSetID,AttributeID,Value,Unit) Values(?,?,?,?)",
                (id,string(attr),ustrip(val),string(unit(val))))
        end
    end
    return id
end


function cache_lock_activity(loc::Location,ledger_id::Integer,time::DateTime=Dates.now())
    upload_time=db_time(time)
    execute_db("INSERT INTO CachedLockActivity(LocationID,IsLocked,IsActive,LedgerID,Time) Values(?,?,?,?,?)",
        (location_id(loc),is_locked(loc),is_active(loc),ledger_id,upload_time))
    return nothing
end
