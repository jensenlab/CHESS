# Containment: which labware each well belongs to. A well never leaves its labware, so the fact is
# structural: it is written once, when the well is created, and is not a cache. Nothing repairs it and
# amending the ledger does not change it. Databases made before the table existed gain it, filled from
# the parent caches, when they are connected to.

const _containment_table_statements = (
    """
    CREATE TABLE IF NOT EXISTS Containment(
        WellID INTEGER PRIMARY KEY NOT NULL,
        ContainerID INTEGER NOT NULL,
        RowIdx INTEGER,
        ColIdx INTEGER,
        FOREIGN KEY(WellID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ContainerID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """,
    "CREATE INDEX IF NOT EXISTS idx_containment_container ON Containment(ContainerID);",
)

_create_containment_table!(db) = foreach(s->DBInterface.execute(db,s),_containment_table_statements)

# the wells in a labware's children, with their positions
function _well_positions(labware::Labware)
    cs=children(labware)
    wells=Tuple{Int,Union{Int,Missing},Union{Int,Missing}}[]
    for idx in CartesianIndices(cs)
        c=cs[idx]
        c isa Well || continue
        isnothing(location_id(c)) && continue
        push!(wells,(location_id(c),idx[1],cs isa AbstractMatrix ? idx[2] : missing))
    end
    return wells
end

"""
    upload_containment(labware::Labware)

Record that each well in `labware` belongs to it. Called when a labware and its wells are created. A
well already recorded is left unchanged.
"""
function upload_containment(labware::Labware)
    for (well_id,row,col) in _well_positions(labware)
        execute_db("INSERT OR IGNORE INTO Containment(WellID,ContainerID,RowIdx,ColIdx) Values(?,?,?,?)",
            (well_id,location_id(labware),row,col))
    end
    return nothing
end

# the kind of a stored location type name, or nothing if the type is not loaded
function _stored_kind(type_name)
    k=get(location_kinds,Symbol(type_name),nothing)
    return k
end

"""
    rebuild_containment!() -> Integer

Fill the `Containment` table from the parent caches (`CachedAncestors`) and the cached child positions
(`CachedChildren`) for every well that has no row yet, and return the number of rows added. This runs
when a database is connected to, so it is only needed to repair a table by hand. A well with no cached
parent cannot be placed and is skipped.
"""
function rebuild_containment!()
    rows=query_db("""
        SELECT a.LocationID AS WellID, a.ParentID AS ContainerID, w.Type AS WellType, p.Type AS ContainerType
        FROM CachedAncestors a
        INNER JOIN Locations w ON w.ID = a.LocationID
        INNER JOIN Locations p ON p.ID = a.ParentID
        WHERE a.ID IN (SELECT MIN(ID) FROM CachedAncestors WHERE ParentID IS NOT NULL GROUP BY LocationID)
          AND a.LocationID NOT IN (SELECT WellID FROM Containment)
        """)
    added=0
    sql_transaction() do
        for r in eachrow(rows)
            wk=_stored_kind(r.WellType)
            ck=_stored_kind(r.ContainerType)
            (isnothing(wk) || isnothing(ck)) && continue
            (concretetype(wk) <: Well && concretetype(ck) <: Labware) || continue
            pos=query_db("SELECT RowIdx, ColIdx FROM CachedChildren WHERE ChildID = ? ORDER BY ID LIMIT 1",(r.WellID,))
            row,col = nrow(pos)==0 ? (missing,missing) : (pos[1,:RowIdx],pos[1,:ColIdx])
            execute_db("INSERT OR IGNORE INTO Containment(WellID,ContainerID,RowIdx,ColIdx) Values(?,?,?,?)",
                (r.WellID,r.ContainerID,row,col))
            added+=1
        end
    end
    return added
end

# a database made before containment existed gains the table, filled from its caches, when connected to
function _ensure_containment_table!()
    _table_exists("Locations") || return nothing
    if !_table_exists("Containment")
        foreach(execute_db,_containment_table_statements)
        _table_exists("CachedAncestors") && rebuild_containment!()
    end
    return nothing
end

"""
    well_container(well_id::Integer) -> Union{Int,Nothing}

The location ID of the labware that well `well_id` belongs to, or `nothing` if the well is not recorded
in `Containment`. This is the canonical well-to-container lookup: it does not depend on the rebuildable
cache tables and does not change over the history.

See also: [`well_containers`](@ref), [`container_wells`](@ref).
"""
function well_container(well_id::Integer)
    r=query_db("SELECT ContainerID FROM Containment WHERE WellID = ?",(well_id,))
    return nrow(r)==0 ? nothing : r[1,1]
end

# SQLite limits the number of parameters in one statement, so id lists are queried in chunks
const _id_chunk = 500

"""
    well_containers(well_ids::AbstractVector{<:Integer}) -> Dict{Int,Int}

The labware of each well in `well_ids`, as a dictionary from well ID to container ID. Wells that are not
recorded are left out. Any number of IDs may be given.
"""
function well_containers(well_ids::AbstractVector{<:Integer})
    out=Dict{Int,Int}()
    for chunk in Iterators.partition(unique(well_ids),_id_chunk)
        marks="("*join(fill("?",length(chunk)),",")*")"
        r=query_db("SELECT WellID, ContainerID FROM Containment WHERE WellID IN $marks",Tuple(chunk))
        for row in eachrow(r)
            out[row.WellID]=row.ContainerID
        end
    end
    return out
end

"""
    container_wells(container_id::Integer) -> DataFrame

The wells of labware `container_id`, with columns `WellID`, `RowIdx` and `ColIdx` (`missing` where the
labware has no grid), ordered by position.
"""
function container_wells(container_id::Integer)
    return query_db("SELECT WellID, RowIdx, ColIdx FROM Containment WHERE ContainerID = ? ORDER BY ColIdx, RowIdx, WellID",(container_id,))
end
