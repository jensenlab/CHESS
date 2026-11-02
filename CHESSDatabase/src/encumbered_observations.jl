# Encumbered observations: a protocol plans that a well holds a component at an amount, the way it plans a transfer.
# Replay applies it in encumbrance order, after every ledger entry, as the planned transfers are applied (see
# `reconstruct_contents`). The lot of the component is not part of an observation.

const _encumbered_observation_table_statements = (
    """
    CREATE TABLE IF NOT EXISTS EncumberedObservations(
        ID INTEGER PRIMARY KEY NOT NULL,
        EncumbranceID INTEGER,
        LocationID INTEGER,
        ComponentID INTEGER,
        Quantity REAL,
        Unit TEXT,
        FOREIGN KEY(EncumbranceID) REFERENCES Encumbrances(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LocationID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(ComponentID) REFERENCES Components(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """,
)

_create_encumbered_observation_table!(db) = foreach(s->DBInterface.execute(db,s),_encumbered_observation_table_statements)

# a database made before encumbered observations existed gains the table when it is connected to
function _ensure_encumbered_observation_table!()
    _table_exists("Encumbrances") && !_table_exists("EncumberedObservations") && foreach(execute_db,_encumbered_observation_table_statements)
    return nothing
end

"""
    encumber_observation(encumberid::Integer, well::Well, component::StockComponent, quant)

Record the planned observation that `well` holds `component` at exactly `quant` under encumbrance `encumberid`.
[`encumber`](@ref) calls this for `encumber(protocol_id, observe!, well, component, quant)`.
"""
function encumber_observation(encumberid::Integer,well::Well,component::StockComponent,quant::Unitful.Quantity)
    execute_db("""INSERT INTO EncumberedObservations(EncumbranceID,LocationID,ComponentID,Quantity,Unit) Values(?,?,?,?,?)""",
        (encumberid,location_id(well),get_component_id(component),Float64(ustrip(quant)),string(unit(quant))))
    return nothing
end

get_encumbered_observation(encumbrance_id::Integer) = query_db("SELECT * FROM EncumberedObservations WHERE EncumbranceID = $encumbrance_id")

function isa_encumbered_observation(encumbrance_id::Integer)
    return nrow(query_db("SELECT EncumbranceID FROM EncumberedObservations WHERE EncumbranceID = $encumbrance_id")) == 1
end

# The enforced encumbrances as of the slot `enforced_through`, the rule every encumbered query uses.
const _enforced_encumbrances_sql = """
    encumbrance_subset (EncumbranceID)
    AS(SELECT e.ID
        FROM (Select ProtocolID, Max(SequenceID), LedgerID, IsEnforced FROM ProtocolEnforcement INNER JOIN enforcement_subset ON ProtocolEnforcement.LedgerID = enforcement_subset.ID  GROUP BY ProtocolID)  p INNER JOIN Encumbrances e on e.ProtocolID = p.ProtocolID  WHERE IsEnforced = 1
    )"""

"""
    get_encumbered_observations(locs::Vector{<:Integer},time::DateTime=Dates.now();enforced_through::Integer=get_last_sequence_id())

The planned component observations on `locs` of the protocols that are enforced as of the slot `enforced_through`, with the
columns of [`get_content_observations`](@ref). `LedgerID` is `0` and `SequenceID` is the last sequence ID plus the
encumbrance's ID, the slot the planned transfers take, so the planned operations replay in the order they were encumbered.
`EncumbranceID` gives the encumbrance.
"""
function get_encumbered_observations(locs::Vector{<:Integer},time::DateTime=Dates.now();enforced_through::Integer=get_last_sequence_id())
    empty = DataFrame(LedgerID=Int[],SequenceID=Int[],LocationID=Int[],ComponentID=Union{Int,Missing}[],
        Quantity=Union{Float64,Missing}[],Unit=Union{String,Missing}[],EncumbranceID=Int[])
    isempty(locs) && return empty
    _table_exists("EncumberedObservations") || return empty
    ledger_time=db_time(time)
    entry=query_join_vector(locs)
    out = query_db("""
        WITH enforcement_subset (ID,SequenceID)
        AS(SELECT Max(ID),SequenceID FROM Ledger WHERE Time <= $ledger_time AND SequenceID <= $enforced_through GROUP BY SequenceID),
        $(_enforced_encumbrances_sql)
        SELECT 0 AS LedgerID, $(get_last_sequence_id())+o.EncumbranceID AS SequenceID, o.LocationID AS LocationID, o.ComponentID AS ComponentID,
               o.Quantity AS Quantity, o.Unit AS Unit, o.EncumbranceID AS EncumbranceID
        FROM encumbrance_subset e INNER JOIN EncumberedObservations o ON e.EncumbranceID = o.EncumbranceID
        WHERE o.LocationID IN $entry ORDER BY o.EncumbranceID, o.ID""")
    return nrow(out) == 0 ? empty : out
end
