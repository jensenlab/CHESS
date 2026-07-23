

"""
    _reconstruction_transfer(donor,recipient,quantity)

Internal, non-exported helper used only by the ledger-replay simulation below. Returns new
`(donor,recipient)` objects reflecting a transfer of `quantity`, without mutating the originals — the
replay needs to keep both the pre- and post-transfer versions of each well in its own history log
(`all_locs`), so it can't just mutate in place like [`transfer!`](@ref) does.

This is `deepcopy`-based like the old public non-mutating `transfer` (removed — see
[`reconstruct_location`](@ref)/[`build_location`](@ref) for the actual preview pattern), but it's safe
here specifically because `src`/`dest` in this context are always standalone reconstruction shells
(`parent === nothing`, no children) built directly by `t(loc_id,n)` a few lines up — never part of a
live connected tree — so `deepcopy` has nothing extra to copy.
"""
function _reconstruction_transfer(donor,recipient,quantity,configuration::String="")
    d=deepcopy(donor)
    r=deepcopy(recipient)
    transfer!(d,r,quantity,configuration)
    return d,r
end

"""
    get_chemical(id::Integer)

Reconstruct a bare [`Chemical`](@ref) from the `Chemicals` table by `ID` -- the direct, standalone
counterpart of [`get_component`](@ref) for `Reagent`/`Organism`. `Chemical` reconstruction otherwise
only happens inline inside [`restore_composition!`](@ref) as part of rebuilding a `Reagent`'s
`CompositionRule`; this gives it the same testable, direct path.
"""
function get_chemical(id::Integer)
    row = query_db("SELECT Name, Charge, MolecularWeight FROM Chemicals WHERE ID = ?",(id,))
    nrow(row)==0 && error("chemical $id does not exist in the database")
    row = row[1,:]
    mw = ismissing(row["MolecularWeight"]) ? missing : row["MolecularWeight"]*u"g/mol"
    return Chemical(row["Name"],row["Charge"],mw)
end

"""
    restore_composition!(reagent::Reagent, component_id::Integer)

Restore `reagent`'s dissociation rule from the `CompositionRules`/`Chemicals` tables (see
`upload_composition`, `src/database/uploads.jl`), registering it via [`set_composition!`](@ref) so a
reagent reconstructed from the database behaves identically to one defined by its original lab module
in the current session -- no longer dependent on that module being loaded. No-op if nothing was
persisted for `component_id` (e.g. locations uploaded before this table existed).
"""
function restore_composition!(reagent::Reagent,component_id::Integer)
    rows = query_db("""
        SELECT r.ChemicalID, r.Coefficient
        FROM CompositionRules r
        WHERE r.ReagentComponentID = ?
    """,(component_id,))
    nrow(rows)==0 && return nothing
    products = Dict(get_chemical(row.ChemicalID) => row.Coefficient for row in eachrow(rows))
    set_composition!(reagent,CompositionRule(products))
    return nothing
end

function get_component(id::Integer)
    comp_type=query_db("SELECT Type FROM Components WHERE ID=?",(id,))
    if nrow(comp_type)==0
        error("component $id does not exist in the database")
    else
        comp_type=comp_type[1,1]
    end

    if comp_type == "Reagent"
        c = query_db("SELECT Name, Type,MolecularWeight,Density,CID FROM Reagents WHERE ComponentID = ?",(id,))[1,:]
        typ=eval(Symbol(c["Type"]))
        reagent = typ(c["Name"],c["MolecularWeight"]*u"g/mol",c["Density"]*u"g/mL",c["CID"])
        restore_composition!(reagent,id)
        return reagent

    elseif comp_type =="Organism"
        c= query_db("SELECT Genus, Species, Strain FROM Organisms WHERE ComponentID = ?",(id,))[1,:]
        return Organism(c["Genus"],c["Species"],c["Strain"])
    else
        error("component $id not found in the database")
        return nothing
    end 


end


function get_stock(stock_id::Integer)
    x=query_db("SELECT ComponentID, Quantity,Unit FROM CachedComponents WHERE StockID = ?",(stock_id,))
    out_stock=Empty() 

    for r in eachrow(x) 
        component= get_component(r.ComponentID)
        if ismissing(r.Quantity) 
            out_stock += component
        else 
            out_stock +=  (r.Quantity * Unitful.uparse(r.Unit)) * component
        end 
    end 
    return out_stock
end 



function get_content_caches(location_id::Integer, starting::Integer=0, ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    ledger_time=db_time(time)
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,StockID,Cost)
        AS(SELECT e.ID,0,0,e.EncumbranceID,v.LocationID, v.StockID,v.Cost
            FROM encumbrance_subset e INNER JOIN EncumberedCachedContents v ON e.EncumbranceID = v.EncumbranceID 
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0,c.LocationID,c.StockID,c.Cost
            FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.Time <= $ledger_time Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID, EncumbranceID,LocationID,StockID,Cost)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.StockID,c.Cost FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id AND c.Time <= $ledger_time Group By LedgerID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
end
end

# good luck to whoever tries to figure this out. Ben probably won't remember enough to be helpful. 
# leger_subset grabs all of the ledger entries that reflect the parameters of the query: when to start and finish and at what time we are reconstructing the transfers
# encumbrance_subset grabs all of the encumbrances that were active during the time of ledger_subset 
# y grabs all of the regular and encumbered transfers using ledger_subset and encumbrance_subset respectively 
# x does a recursive search to grab all of the transfers from y that play a role in reconstrucint locs 

function get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)  # find all transfers for a set of locations betweeen `starting` and `ending` ledger ids
    ledger_time= db_time(time)
    entry=query_join_vector(locs)
    x=""
    if encumbrances 
        x= 
        """
                    WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),

         y (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+c.EncumbranceID, c.EncumbranceID, c.Source,c.Destination,c.Quantity,c.Unit
            FROM encumbrance_subset e INNER JOIN EncumberedTransfers c ON e.EncumbranceID = c.EncumbranceID
        UNION ALL 
            SELECT t.LedgerID,l.SequenceID,0,t.Source, t.Destination, t.Quantity, t.Unit
            FROM Transfers t INNER JOIN ledger_subset l ON t.LedgerID = l.ID ) ,
        x (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
         SELECT y.LedgerID,y.SequenceID,y.EncumbranceID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION ALL
        SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y  ,x
            WHERE x.Source = y.Destination
        )
        SELECT DISTINCT  * FROM x ORDER BY SequenceID
        """
    else 
        x=
        """
            WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

         x (LedgerID,Source,Destination,Quantity,Unit)
        AS(
        SELECT Transfers.LedgerID, Source,Destination,Transfers.Quantity,Transfers.Unit
            FROM Transfers
            WHERE Destination in $entry OR Source in $entry
        UNION ALL
        SELECT t.LedgerID,t.Source,t.Destination,t.Quantity,t.Unit
            FROM Transfers t  ,x
            WHERE x.Source = t.Destination
        )
        SELECT DISTINCT  * FROM x INNER JOIN ledger_subset ON x.LedgerID = ledger_subset.ID  ORDER BY SequenceID
        """

    end 
return query_db(x)
end 

function get_transfer_descendents(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)  # find all transfers stemming from a set of locations betweeen `starting` and `ending` ledger ids
    ledger_time= db_time(time)
    entry=query_join_vector(locs)
    x=""
    if encumbrances 
        x= 
        """
                    WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN ledger_subset ON ProtocolEnforcement.LedgerID = ledger_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),

         y (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+c.EncumbranceID, c.EncumbranceID, c.Source,c.Destination,c.Quantity,c.Unit
            FROM encumbrance_subset e INNER JOIN EncumberedTransfers c ON e.EncumbranceID = c.EncumbranceID
        UNION ALL 
            SELECT t.LedgerID,l.SequenceID,0,t.Source, t.Destination, t.Quantity, t.Unit
            FROM Transfers t INNER JOIN ledger_subset l ON t.LedgerID = l.ID ) ,
        x (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
         SELECT y.LedgerID,y.SequenceID,y.EncumbranceID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION ALL
        SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y  ,x
            WHERE y.Source = x.Destination
        )
        SELECT DISTINCT  * FROM x ORDER BY SequenceID
        """
    else 
        x=
        """
            WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

         x (LedgerID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
        SELECT Transfers.LedgerID,0, Source,Destination,Transfers.Quantity,Transfers.Unit
            FROM Transfers
            WHERE Destination in $entry OR Source in $entry
        UNION ALL
        SELECT t.LedgerID,0,t.Source,t.Destination,t.Quantity,t.Unit
            FROM Transfers t  ,x
            WHERE t.Source = x.Destination
        )
        SELECT DISTINCT  * FROM x INNER JOIN ledger_subset ON x.LedgerID = ledger_subset.ID  ORDER BY SequenceID
        """

    end 
return query_db(x)
end 

function transfers_touch(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_descendents([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    for row in eachrow(out)
        push!(out_set,(row.Destination,row.LedgerID,row.EncumbranceID))
    end
    return out_set
end 

function transfers_touched_by(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_ancestors([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    for row in eachrow(out)
        push!(out_set,(row.Destination,row.LedgerID,row.EncumbranceID))
    end
    return out_set
end 




function fetch_content_cache(location_id::Integer,starting::Integer,ending::Integer,time=DateTime=Dates.now();encumbrances=false)
    caches=get_content_caches(location_id,starting,ending,time;encumbrances=encumbrances) 
    stock_id=missing
    foot=0
    cost=0
    if nrow(caches) > 0 
        row=caches[end,:]
        stock_id=row.StockID
        foot=row.SequenceID
        cost=row.Cost
    else
        return Empty() ,0 ,0
    
    end 
    
    stock=Empty()
    if !ismissing(stock_id)
        stock=get_stock(stock_id)
    end 

    return stock , cost, foot
end 



function reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(), max_cache::Integer=sequence_id, loc_df::DataFrame = location_reconstruction_df;encumbrances=false)
    all_locs=deepcopy(loc_df)
    cache_feet=[]
    for loc_id in location_ids
        n,t=get_location_info(loc_id)
        loc=t(loc_id,n)
        if !(loc isa CHESSCore.Well)
            push!(all_locs,(loc_id,0,loc))
            continue 
        end 
        stock,cost,cache_foot = fetch_content_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        if !isnothing(stock)
            deposit!(loc,stock,cost)
        end

        push!(all_locs,(CHESSCore.location_id(loc),cache_foot,loc))
        push!(cache_feet,cache_foot)


    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    transfers=get_transfer_ancestors(location_ids,foot+1,sequence_id,time;encumbrances=encumbrances)



    # grab the sequence id of each location we need to complete this set of transfers
    cache_dict=Dict{Integer,Integer}()
    for row in reverse(eachrow(transfers))

        seq_id=min(row.SequenceID-1,sequence_id)
        # set it back to the sequence id we are looking at if the transfer is encumbered
    

        cache_dict[row.Source]=seq_id
        cache_dict[row.Destination]=seq_id
    end 
    reconstructions_needed=Set{Integer}()
    for loc_id in keys(cache_dict)

        new_stock,new_cost,new_foot=fetch_content_cache(loc_id,foot,cache_dict[loc_id],time;encumbrances=false)
        n,t=get_location_info(loc_id)
        new_loc=t(loc_id,n)
        if !isnothing(new_stock)
            deposit!(new_loc,new_stock,new_cost)
            push!(all_locs,(loc_id,new_foot,new_loc))
        else
            push!(reconstructions_needed,loc_id)
        end 
    end
    if length(reconstructions_needed) > 0 
        locs=reconstruct_contents(collect(reconstructions_needed),foot,time,max_cache,all_locs)
        for loc in locs 
            push!(all_locs,(CHESSCore.location_id(loc),foot,loc))
        end 
    end 

    #start simulation

    for row in eachrow(transfers)
        seq_id=row.SequenceID -1
        dest =find_most_recent_location(all_locs,row.Destination,seq_id)

        src = find_most_recent_location(all_locs,row.Source,seq_id)
        quant= row.Quantity * Unitful.uparse(row.Unit)
        new_src,new_dest=_reconstruction_transfer(src,dest,quant)
        push!(all_locs,(CHESSCore.location_id(dest),seq_id+1,new_dest))
        push!(all_locs,(CHESSCore.location_id(src),seq_id+1,new_src))
    end 

    final_out = find_most_recent_location.((all_locs,), location_ids)


    return final_out
end 

function reconstruct_contents(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_df::DataFrame=location_reconstruction_df;encumbrances=false)
    return reconstruct_contents([location_id],sequence_id,time,max_cache,loc_df;encumbrances=encumbrances)[1]
end 
    


function reconstruct_contents!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_df::DataFrame=location_reconstruction_df;encumbrances=false)


    parallel_locs=reconstruct_contents(location_id.(locations),sequence_id,time,max_cache,loc_df,encumbrances=encumbrances)

    for i in eachindex(locations)
        if locations[i] isa CHESSCore.Well
            locations[i].stock=CHESSCore.stock(parallel_locs[i])
            locations[i].cost=CHESSCore.cost(parallel_locs[i])
        else
            continue 
        end 
    end 
    return nothing
end 

function reconstruct_contents!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_df::DataFrame=location_reconstruction_df;encumbrances=false)
    parallel_loc=reconstruct_contents(location_id(location),sequence_id,time,max_cache,loc_df,encumbrances=encumbrances)
    if location isa CHESSCore.Well
        location.stock=CHESSCore.stock(parallel_loc)
        location.cost=CHESSCore.cost(parallel_loc)
    end 
    return nothing 
end 

    


        








