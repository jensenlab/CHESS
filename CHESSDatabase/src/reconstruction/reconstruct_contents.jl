

"""
    _reconstruction_transfer(donor,recipient,quantity,configuration::String="")

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
    UnfilledDrawError(ledger_id,encumbrance_id,source,destination,quantity,available)

A replay of the ledger drew `quantity` out of the well `source`, which held only `available` at that point. `destination` is
`missing` for a discard. `encumbrance_id` is the planned transfer being replayed (`0` for a recorded one) and `ledger_id` the
ledger entry of the transfer or discard. `shortfall` gives the amount missing.

This happens when an operation that fills the source is not in the replay, for example the protocol holding the planned fill
of an intermediate well is no longer enforced while a protocol that draws from that well still is. It is thrown by the
reconstruction functions; what the database accepts when writing is unchanged.
"""
struct UnfilledDrawError <: Exception
    ledger_id::Int
    encumbrance_id::Int
    source::Int
    destination::Union{Int,Missing}
    quantity::Any
    available::Any
end

shortfall(e::UnfilledDrawError) = e.quantity - e.available

function Base.showerror(io::IO,e::UnfilledDrawError)
    what = e.encumbrance_id > 0 ? "planned transfer (encumbrance $(e.encumbrance_id))" : (ismissing(e.destination) ? "discard (ledger entry $(e.ledger_id))" : "transfer (ledger entry $(e.ledger_id))")
    print(io,"Unfilled Draw Error: the ",what," draws ",e.quantity," from well ",e.source)
    ismissing(e.destination) || print(io," into well ",e.destination)
    print(io,", but that well holds ",e.available," at that point (short by ",shortfall(e),"). ",
          "Whatever fills well ",e.source," is not part of this reconstruction, for example a protocol that is no longer enforced.")
    nothing
end

# Throws UnfilledDrawError when `src` holds less than `quant`. A quantity in a different dimension from the well's is left to the
# transfer itself to report.
function _check_draw(src,quant,row)
    avail = CHESSCore.quantity(CHESSCore.stock(src))
    if ismissing(avail)
        avail = zero(quant)
    elseif Unitful.dimension(avail) != Unitful.dimension(quant)
        return nothing
    end
    (avail < quant && !isapprox(avail,quant)) || return nothing
    throw(UnfilledDrawError(Int(row.LedgerID),hasproperty(row,:EncumbranceID) ? Int(row.EncumbranceID) : 0,Int(row.Source),
                            ismissing(row.Destination) ? missing : Int(row.Destination),quant,avail))
end

"""
    get_species(id::Integer)

Reconstruct a bare [`Species`](@ref) from the `Species` table by `ID` -- the direct, standalone
counterpart of `get_component` for `Reagent`/`Organism`. `Species` reconstruction otherwise
only happens inline inside [`restore_dissolution!`](@ref) as part of rebuilding a `Reagent`'s
`Dissolution`; this gives it the same testable, direct path.
"""
function get_species(id::Integer)
    row = query_db("SELECT Name, Charge, Formula, MolecularWeight, CID FROM Species WHERE ID = ?",(id,))
    nrow(row)==0 && error("species $id does not exist in the database")
    row = row[1,:]
    if isequal(row["Formula"],"opaque")
        ismissing(row["MolecularWeight"]) && return Species(row["Name"],row["Charge"],CHESSCore.opaque;pubchemid=row["CID"])
        return Species(row["Name"],row["Charge"],CHESSCore.opaque(row["MolecularWeight"]*u"g/mol");pubchemid=row["CID"])
    end
    ismissing(row["Formula"]) || return Species(row["Name"],row["Charge"],row["Formula"];pubchemid=row["CID"])
    mw = ismissing(row["MolecularWeight"]) ? missing : row["MolecularWeight"]*u"g/mol"
    return Species(row["Name"],row["Charge"],mw;pubchemid=row["CID"])
end

"""
    restore_dissolution!(reagent::Reagent, component_id::Integer)

Restore `reagent`'s dissociation rule from the `Dissolutions`/`Species` tables (see
`upload_dissolution`, `src/database/uploads.jl`), registering it via [`set_dissolution!`](@ref) so a
reagent reconstructed from the database behaves identically to one defined by its original lab module
in the current session -- no longer dependent on that module being loaded. No-op if nothing was
persisted for `component_id` (e.g. locations uploaded before this table existed).
"""
function restore_dissolution!(reagent::Reagent,component_id::Integer)
    rows = query_db("""
        SELECT r.SpeciesID, r.Coefficient
        FROM Dissolutions r
        WHERE r.ReagentComponentID = ?
    """,(component_id,))
    nrow(rows)==0 && return nothing
    products = Dict(get_species(row.SpeciesID) => row.Coefficient for row in eachrow(rows))
    set_dissolution!(reagent,Dissolution(products))
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
        c = query_db("SELECT Name, Type,MolecularWeight,Density FROM Reagents WHERE ComponentID = ?",(id,))[1,:]
        # stored as the bare type name; older databases may hold the module-qualified form ("CHESSCore.Liquid")
        typ=getfield(CHESSCore,Symbol(last(split(c["Type"],'.'))))
        reagent = typ(c["Name"],c["MolecularWeight"]*u"g/mol",c["Density"]*u"g/mL")
        restore_dissolution!(reagent,id)
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
            out_stock +=  (r.Quantity * _parse_unit(r.Unit)) * component
        end
    end 
    return out_stock
end 



function _get_content_caches_global(location_id::Integer, starting::Integer=0, ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    ledger_time=db_time(time)
    enforced_through=ending
    if encumbrances
        return query_db("
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ),
        enforcement_subset (ID,SequenceID)
        AS(SELECT Max(ID),SequenceID FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $enforced_through GROUP BY SequenceID),

                    encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN enforcement_subset ON ProtocolEnforcement.LedgerID = enforcement_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),
        
            y (ID,LedgerID,SequenceID,EncumbranceID,LocationID,StockID)
        AS(SELECT e.EncumbranceID,0,0,e.EncumbranceID,v.LocationID, v.StockID
            FROM encumbrance_subset e INNER JOIN EncumberedCachedContents v ON e.EncumbranceID = v.EncumbranceID
        UNION ALL 
            SELECT Max(c.ID),c.LedgerID,l.SequenceID,0,c.LocationID,c.StockID
            FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID = $location_id AND c.Time <= $ledger_time Group By l.SequenceID) 
            SELECT * FROM y WHERE LocationID=$location_id ORDER BY EncumbranceID,SequenceID ")
    else
        return query_db("
            WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID), SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID 
            ) ,
        y (ID,LedgerID,SequenceID, EncumbranceID,LocationID,StockID)
        AS( SELECT Max(c.ID),c.LedgerID,l.SequenceID,0, c.LocationID,c.StockID FROM CachedContents c INNER JOIN ledger_subset l ON c.LedgerID = l.ID WHERE c.LocationID =$location_id AND c.Time <= $ledger_time Group By LedgerID ORDER BY SequenceID ) 
        SELECT * from y
        " )
        
end
end

# good luck to whoever tries to figure this out. Ben probably won't remember enough to be helpful. 
# leger_subset grabs all of the ledger entries that reflect the parameters of the query: when to start and finish and at what time we are reconstructing the transfers
# encumbrance_subset grabs all of the encumbrances that were active during the time of ledger_subset 
# y grabs all of the regular and encumbered transfers using ledger_subset and encumbrance_subset respectively 
# x does a recursive search to grab all of the transfers from y that play a role in reconstrucint locs 

"""
    get_transfer_ancestors(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)

Find every transfer relevant to reconstructing `locs`' contents between `starting` and `ending`
sequence points.

The result has a `Core` column (`1`/`0`). `Core=1` rows are the genuine ancestor closure: `locs`
themselves plus every location transitively feeding them (found the traditional way, recursively
following `Source = <already-found Source>.Destination`). `Core=0` ("collateral") rows are *other*
outgoing transfers of a `Core=1` location, to a destination that never itself feeds back into the
closure -- needed so replay can correctly account for stock a core location sent away to something
`reconstruct_contents` doesn't otherwise care about (see the module docs above `x`'s definition for
why this ever mattered). Collateral destinations never need their own correct reconstruction --
`reconstruct_contents` bootstraps them as bare `Empty()` stubs instead of recursing, which is what
keeps a busy/shared well's reconstruction from pulling in a large, mostly-irrelevant slice of the
whole ledger's history: the *query* still has to look at every collateral edge (that's inherent to
correctly zeroing out a core well's balance), but no collateral destination ever triggers its own
expensive reconstruction.
"""
# the rows of Transfers and Discards, each with the ID of the row and its table (0 a transfer, 1 a discard)
const _transfer_rows = "(SELECT LedgerID,Source,Destination,Quantity,Unit,ID AS RowID,0 AS Kind FROM Transfers UNION ALL SELECT LedgerID,Source,NULL AS Destination,Quantity,Unit,ID AS RowID,1 AS Kind FROM Discards)"

function _get_transfer_ancestors_global(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false,enforced_through::Integer=ending)  # find all transfers for a set of locations betweeen `starting` and `ending` ledger ids
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
        enforcement_subset (ID,SequenceID)
        AS(SELECT Max(ID),SequenceID FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $enforced_through GROUP BY SequenceID),

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN enforcement_subset ON ProtocolEnforcement.LedgerID = enforcement_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

        ),

         y (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(SELECT 0,$(get_last_sequence_id())+c.EncumbranceID, c.EncumbranceID, c.Source,c.Destination,c.Quantity,c.Unit
            FROM encumbrance_subset e INNER JOIN EncumberedTransfers c ON e.EncumbranceID = c.EncumbranceID
        UNION ALL
            SELECT t.LedgerID,l.SequenceID,0,t.Source, t.Destination, t.Quantity, t.Unit
            FROM $(transfer_events) t INNER JOIN ledger_subset l ON t.LedgerID = l.ID ) ,
        x (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit)
        AS(
         SELECT y.LedgerID,y.SequenceID,y.EncumbranceID, Source,Destination,y.Quantity,y.Unit
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit
            FROM y  ,x
            WHERE x.Source = y.Destination
        ),
        ancestor_wells (LocationID) AS (
            SELECT Source FROM x UNION SELECT Destination FROM x
        ),
        full_set (LedgerID,SequenceID,EncumbranceID,Source,Destination,Quantity,Unit,Core) AS (
            SELECT *, 1 FROM x
            UNION
            SELECT y.LedgerID,y.SequenceID,y.EncumbranceID,y.Source,y.Destination,y.Quantity,y.Unit, 0
                FROM y INNER JOIN ancestor_wells ON y.Source = ancestor_wells.LocationID
                WHERE NOT EXISTS (SELECT 1 FROM x WHERE x.LedgerID = y.LedgerID AND x.EncumbranceID = y.EncumbranceID)
        )
        SELECT DISTINCT * FROM full_set ORDER BY SequenceID
        """
    else
        x=
        """
            WITH RECURSIVE ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            ) ,

         -- restrict to transfers inside the requested window before walking ancestors, as the
         -- encumbrance branch does: a transfer after `ending` must not pull its source into the
         -- closure, or that source's earlier outgoing transfers come back as collateral rows
         -- for a well that was never bootstrapped.
         -- RowID and Kind identify the row itself (a ledger entry can hold several transfers), so that
         -- the result keeps every row of a tick instead of one per ledger entry
         y (LedgerID,Source,Destination,Quantity,Unit,RowID,Kind)
        AS(SELECT t.LedgerID,t.Source,t.Destination,t.Quantity,t.Unit,t.RowID,t.Kind
            FROM $(_transfer_rows) t INNER JOIN ledger_subset l ON t.LedgerID = l.ID),

         x (LedgerID,Source,Destination,Quantity,Unit,RowID,Kind)
        AS(
        SELECT y.LedgerID, Source,Destination,y.Quantity,y.Unit,y.RowID,y.Kind
            FROM y
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT y.LedgerID,y.Source,y.Destination,y.Quantity,y.Unit,y.RowID,y.Kind
            FROM y ,x
            WHERE x.Source = y.Destination
        ),
        ancestor_wells (LocationID) AS (
            SELECT Source FROM x UNION SELECT Destination FROM x
        ),
        full_set (LedgerID,Source,Destination,Quantity,Unit,RowID,Kind,Core) AS (
            SELECT *, 1 FROM x
            UNION
            SELECT y.LedgerID, Source, Destination, y.Quantity, y.Unit, y.RowID, y.Kind, 0
                FROM y INNER JOIN ancestor_wells ON y.Source = ancestor_wells.LocationID
                WHERE NOT EXISTS (SELECT 1 FROM x WHERE x.RowID = y.RowID AND x.Kind = y.Kind)
        )
        SELECT full_set.LedgerID,Source,Destination,Quantity,Unit,Max(Core) AS Core,ledger_subset.SequenceID
            FROM full_set INNER JOIN ledger_subset ON full_set.LedgerID = ledger_subset.ID
            GROUP BY full_set.Kind, full_set.RowID ORDER BY ledger_subset.SequenceID, full_set.LedgerID, full_set.Kind, full_set.RowID
        """

    end
return query_db(x)
end

function _get_transfer_descendents_global(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false,enforced_through::Integer=ending)  # find all transfers stemming from a set of locations betweeen `starting` and `ending` ledger ids
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
        enforcement_subset (ID,SequenceID)
        AS(SELECT Max(ID),SequenceID FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $enforced_through GROUP BY SequenceID),

        encumbrance_subset (EncumbranceID)
        AS(SELECT e.ID
            FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN enforcement_subset ON ProtocolEnforcement.LedgerID = enforcement_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1

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
        UNION
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

         x (LedgerID,EncumbranceID,Source,Destination,Quantity,Unit,RowID)
        AS(
        SELECT Transfers.LedgerID,0, Source,Destination,Transfers.Quantity,Transfers.Unit,Transfers.ID
            FROM Transfers
            WHERE Destination in $entry OR Source in $entry
        UNION
        SELECT t.LedgerID,0,t.Source,t.Destination,t.Quantity,t.Unit,t.ID
            FROM Transfers t  ,x
            WHERE t.Source = x.Destination
        )
        SELECT x.LedgerID,x.EncumbranceID,x.Source,x.Destination,x.Quantity,x.Unit,ledger_subset.ID,ledger_subset.SequenceID,ledger_subset.Time
            FROM x INNER JOIN ledger_subset ON x.LedgerID = ledger_subset.ID  ORDER BY ledger_subset.SequenceID, x.LedgerID, x.RowID
        """

    end 
return query_db(x)
end 

function transfers_touch(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_descendents([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    for row in eachrow(out)
        ismissing(row.Destination) && continue # a discard reaches no other well
        push!(out_set,(row.Destination,row.LedgerID,row.EncumbranceID))
    end
    return out_set
end 

function transfers_touched_by(location_id,starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now();encumbrances=false)
    out=get_transfer_ancestors([location_id],starting,ending,time;encumbrances=encumbrances) 
    out_set=Tuple{Integer,Integer,Integer}[]
    # the ancestors have an EncumbranceID column only with encumbrances=true; without them every transfer is a recorded one
    has_encumbrance = hasproperty(out,:EncumbranceID)
    for row in eachrow(out)
        ismissing(row.Destination) && continue # a discard reaches no other well
        push!(out_set,(row.Destination,row.LedgerID,has_encumbrance ? row.EncumbranceID : 0))
    end
    return out_set
end 




"""
    fetch_content_cache(location_id::Integer,starting::Integer,ending::Integer,time::DateTime=Dates.now();encumbrances=false)

Look up `location_id`'s most recent cached [`Stock`](@ref) within `starting..ending`. Returns
`(stock, foot)`.

`stock` is `nothing` when no `CachedContents` row exists in that window at all -- distinct from a
row that exists and legitimately caches an empty stock (which returns `Empty()`, not `nothing`).
Callers (see [`reconstruct_contents`](@ref)) rely on this distinction: `nothing` means "we don't
actually know this location's content here, go reconstruct it," while `Empty()` means "confirmed
empty as of this cache point."
"""
function fetch_content_cache(location_id::Integer,starting::Integer,ending::Integer,time::DateTime=Dates.now();encumbrances=false)
    caches=get_content_caches(location_id,starting,ending,time;encumbrances=encumbrances)
    nrow(caches) == 0 && return nothing, 0

    row=caches[end,:]
    stock_id=row.StockID
    foot=row.SequenceID

    stock=Empty()
    if !ismissing(stock_id)
        stock=get_stock(stock_id)
    end

    return stock, foot
end

"""
    reconstruct_contents(location_id::Integer, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Location
    reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false) -> Vector{<:Location}

Rebuild the stock of wells from the ledger's transfer history, returning new locations for
the given IDs. [`reconstruct_contents!`](@ref) writes the result into existing
[`Location`](@ref)s instead. IDs that are not [`Well`](@ref)s come back as bare locations with no contents.

A well's contents can depend on every well that ever transferred into it, so reconstruction starts
from the most recent cached stock of each well and replays only the transfers since then. Passing
several wells at once shares that work.

The optional arguments work as in [`reconstruct_location!`](@ref): `sequence_id` and `time` choose the
point in history, `max_cache` limits which caches may be used, and `encumbrances=true` includes
planned future operations.
"""
function reconstruct_contents(location_ids::Vector{<:Integer}, sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(), max_cache::Integer=sequence_id, loc_index::Dict{<:Integer,<:Vector} = location_reconstruction_index;encumbrances=false,enforced_through::Integer=sequence_id)
    all_locs=_reconstruct_contents_index(location_ids,sequence_id,time,max_cache,loc_index;encumbrances=encumbrances,enforced_through=enforced_through)
    return find_most_recent_location.((all_locs,), location_ids)
end

# The replay behind `reconstruct_contents`: the index of every location it reconstructed, each with one entry per slot at
# which its state changed. `trace`, when given, receives `(location id, slot) => (event, LedgerID)` for each change to a location.
function _reconstruct_contents_index(location_ids::Vector{<:Integer}, sequence_id::Integer, time::DateTime, max_cache::Integer, loc_index::Dict{<:Integer,<:Vector};encumbrances=false,trace=nothing,enforced_through::Integer=sequence_id)
    all_locs=deepcopy(loc_index)
    cache_feet=[]
    for loc_id in location_ids
        n,t=get_location_info(loc_id)
        loc=t(loc_id,n)
        if !(loc isa CHESSCore.Well)
            push_location!(all_locs,loc_id,0,loc)
            continue
        end
        stock,cache_foot = fetch_content_cache(loc_id,0,max_cache,time;encumbrances=encumbrances)
        if !isnothing(stock)
            deposit!(loc,stock)
        end

        push_location!(all_locs,CHESSCore.location_id(loc),cache_foot,loc)
        push!(cache_feet,cache_foot)


    end 
    foot=0
    if length(cache_feet)>0 
        foot = min(minimum(cache_feet),sequence_id)
    end
    transfers=get_transfer_ancestors(location_ids,foot+1,sequence_id,time;encumbrances=encumbrances,enforced_through=enforced_through)



    # locations that are part of the genuine ancestor closure (Core=1 in some row) need a real,
    # possibly-recursive bootstrap below. Locations that only appear because a core location's
    # *other* outgoing transfer happened to land on them ("collateral", Core=0 everywhere they
    # appear) never get read back out of this call -- see get_transfer_ancestors's docstring --
    # so they're built as bare Empty() stubs instead, without ever touching the cache tables or
    # recursing. This is what keeps a busy/shared well's reconstruction from cascading into a large,
    # mostly-irrelevant slice of the ledger just because get_transfer_ancestors had to look at it.
    core_locs=Set{Integer}()
    if nrow(transfers) > 0 && hasproperty(transfers,:Core)
        for row in eachrow(transfers)
            if row.Core == 1
                push!(core_locs,row.Source)
                ismissing(row.Destination) || push!(core_locs,row.Destination)
            end
        end
    end

    # component observations on every well whose own state this call reads back: the
    # requested wells plus the core ancestor closure. Collateral destinations never need them.
    target_wells=filter(id -> find_most_recent_location(all_locs,id) isa CHESSCore.Well,location_ids)
    observations=get_content_observations(collect(union(core_locs,target_wells)),foot+1,sequence_id,time;encumbrances=encumbrances,enforced_through=enforced_through)

    # grab the sequence id of each location we need to complete this set of transfers
    cache_dict=Dict{Integer,Integer}()
    for row in reverse(eachrow(transfers))

        seq_id=min(row.SequenceID-1,sequence_id)
        # set it back to the sequence id we are looking at if the transfer is encumbered


        cache_dict[row.Source]=seq_id
        ismissing(row.Destination) || (cache_dict[row.Destination]=seq_id)
    end
    # a core well must also be bootstrapped from before its first observation
    for row in eachrow(observations)
        row.LocationID in core_locs || continue
        seq_id=min(row.SequenceID-1,sequence_id)
        cache_dict[row.LocationID]=min(get(cache_dict,row.LocationID,seq_id),seq_id)
    end
    reconstructions_needed=Set{Integer}()
    for loc_id in keys(cache_dict)

        if !(loc_id in core_locs)
            n,t=get_location_info(loc_id)
            push_location!(all_locs,loc_id,foot,t(loc_id,n))
            continue
        end

        new_stock,new_foot=fetch_content_cache(loc_id,foot,cache_dict[loc_id],time;encumbrances=false)
        n,t=get_location_info(loc_id)
        new_loc=t(loc_id,n)
        if !isnothing(new_stock)
            deposit!(new_loc,new_stock)
            push_location!(all_locs,loc_id,new_foot,new_loc)
        else
            push!(reconstructions_needed,loc_id)
        end
    end
    if length(reconstructions_needed) > 0
        # the bootstrap holds recorded history only: every planned operation touching a core well is in `transfers` and
        # `observations` above and is applied by the replay below, so a bootstrap that applied them too would apply them twice
        locs=reconstruct_contents(collect(reconstructions_needed),foot,time,max_cache,all_locs;encumbrances=false,enforced_through=enforced_through)
        for loc in locs
            push_location!(all_locs,CHESSCore.location_id(loc),foot,loc)
        end
    end

    #start simulation: transfers and observations in sequence order. A tick holds several transfers only in
    # data written before the rule of simultaneous ticks (ticks.jl): they are applied one after the other, in the
    # order the closure returns them (the order they were recorded in), each on the result of the one before, so
    # none is lost. The sort is stable, so transfers come before the observations of the same slot.
    events=vcat([(row.SequenceID,row) for row in eachrow(transfers)],
                [(key.SequenceID,rows) for (key,rows) in pairs(groupby(observations,[:LocationID,:SequenceID];sort=false))])
    sort!(events;by=first,alg=MergeSort)

    # (location, slot) pairs that an event of this replay has already changed: a later event of the same slot
    # continues from that state instead of the state before the slot
    touched=Set{Tuple{Int,Int}}()
    for (_,row) in events
        if !(row isa DataFrameRow)
            isnothing(trace) || (trace[(Int(row[1,:LocationID]),Int(row[1,:SequenceID]))] = ("observe_components",Int(row[1,:LedgerID])))
            _apply_content_observations!(all_locs,row;touched=touched)
            continue
        end
        seq_id=row.SequenceID -1
        src_seq=(Int(row.Source),Int(row.SequenceID)) in touched ? row.SequenceID : seq_id
        quant= row.Quantity * _parse_unit(row.Unit)
        src = find_most_recent_location(all_locs,row.Source,src_seq)

        if row.Core == 0 || ismissing(row.Destination) # a discard has no destination to track
            # Collateral: this row exists only so a *core* location's balance is correctly reduced
            # by whatever it sent elsewhere -- the destination itself is never read back out of this
            # call (see get_transfer_ancestors's docstring), so there's no need to find, deepcopy, or
            # track it at all. Just withdraw from a copy of the source and discard the rest.
            _check_draw(src,quant,row)
            new_src = deepcopy(src)
            withdraw!(new_src,quant)
            push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
            push!(touched,(Int(row.Source),Int(row.SequenceID)))
            isnothing(trace) || (trace[(Int(row.Source),Int(row.SequenceID))] = (ismissing(row.Destination) ? "discard" : "transfer out",Int(row.LedgerID)))
            continue
        end

        dest = find_most_recent_location(all_locs,row.Destination,(Int(row.Destination),Int(row.SequenceID)) in touched ? row.SequenceID : seq_id)
        _check_draw(src,quant,row)
        new_src,new_dest=_reconstruction_transfer(src,dest,quant)
        push_location!(all_locs,CHESSCore.location_id(dest),seq_id+1,new_dest)
        push_location!(all_locs,CHESSCore.location_id(src),seq_id+1,new_src)
        push!(touched,(Int(row.Destination),Int(row.SequenceID)),(Int(row.Source),Int(row.SequenceID)))
        if !isnothing(trace)
            trace[(Int(row.Destination),Int(row.SequenceID))] = ("transfer in",Int(row.LedgerID))
            trace[(Int(row.Source),Int(row.SequenceID))] = ("transfer out",Int(row.LedgerID))
        end
    end

    return all_locs
end 

function reconstruct_contents(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)
    return reconstruct_contents([location_id],sequence_id,time,max_cache,loc_index;encumbrances=encumbrances)[1]
end

"""
    reconstruct_contents!(location::Location, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)
    reconstruct_contents!(locations::Vector{<:Location}, sequence_id=get_last_sequence_id(), time=Dates.now(), max_cache=sequence_id; encumbrances=false)

Set the stock of each [`Well`](@ref) in `locations` to its reconstructed state. Other
locations are left alone. Arguments work as in [`reconstruct_contents`](@ref).
"""
function reconstruct_contents!(locations::Vector{<:Location},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)


    parallel_locs=reconstruct_contents(location_id.(locations),sequence_id,time,max_cache,loc_index,encumbrances=encumbrances)

    for i in eachindex(locations)
        if locations[i] isa CHESSCore.Well
            locations[i].stock=CHESSCore.stock(parallel_locs[i])
        else
            continue 
        end 
    end 
    return nothing
end 

function reconstruct_contents!(location::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id,loc_index::Dict{<:Integer,<:Vector}=location_reconstruction_index;encumbrances=false)
    parallel_loc=reconstruct_contents(location_id(location),sequence_id,time,max_cache,loc_index,encumbrances=encumbrances)
    if location isa CHESSCore.Well
        location.stock=CHESSCore.stock(parallel_loc)
    end 
    return nothing 
end 

    


        








"""
    get_content_observations(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())

Every component observation on `locs` between `starting` and `ending` sequence points,
ordered by `SequenceID`.
"""
function _get_content_observations_global(locs::Vector{<:Integer},starting::Integer=0,ending::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    isempty(locs) && return DataFrame(LedgerID=Int[],SequenceID=Int[],LocationID=Int[],ComponentID=Union{Int,Missing}[],
        Quantity=Union{Float64,Missing}[],Unit=Union{String,Missing}[])
    ledger_time=db_time(time)
    entry=query_join_vector(locs)
    return query_db("""
        WITH ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT Max(ID),SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending GROUP BY SequenceID
            )
        SELECT o.LedgerID,l.SequenceID,o.LocationID,o.ComponentID,o.Quantity,o.Unit
            FROM ObservedComponents o INNER JOIN ledger_subset l ON o.LedgerID = l.ID WHERE o.LocationID IN $entry
        ORDER BY SequenceID, o.ID
        """)
end

"""
    _apply_content_observations!(all_locs, rows; touched=nothing)

Replay one location's observations at one sequence point (`rows` share a `LocationID` and
`SequenceID`) on top of its most recent reconstructed state, and record the result at that sequence
point. Skipped when that location's state is only known from a point at or after the observation --
a cache written there already reflects it. `touched` is the set of `(location, slot)` pairs that earlier events of the
same replay changed; a location in it continues from the state those left at `seq_id`, not from the state before it.
"""
function _apply_content_observations!(all_locs,rows;touched=nothing)
    loc_id=rows[1,:LocationID]
    seq_id=rows[1,:SequenceID]
    after_same_slot = !isnothing(touched) && (Int(loc_id),Int(seq_id)) in touched
    entry=find_most_recent_entry(all_locs,loc_id,after_same_slot ? seq_id : seq_id-1)
    isnothing(entry) && return nothing
    loc=deepcopy(entry[2])
    for row in eachrow(rows)
        quant=row.Quantity*_parse_unit(row.Unit)
        loc.stock=set_component(CHESSCore.stock(loc),get_component(row.ComponentID),quant)
    end
    push_location!(all_locs,loc_id,seq_id,loc)
    isnothing(touched) || push!(touched,(Int(loc_id),Int(seq_id)))
    return nothing
end
