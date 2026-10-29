# Discards: material withdrawn from a well that goes into no other well. A discard is a ledgered
# operation like a transfer, but with only a source. Replay treats it as a withdrawal from the source,
# and amending the ledger validates and repairs it the way it does for a transfer.

const _discard_table_statements = (
    """
    CREATE TABLE IF NOT EXISTS Discards(
        ID INTEGER PRIMARY KEY NOT NULL,
        LedgerID INTEGER,
        Source INTEGER,
        Quantity REAL,
        Unit TEXT,
        Time INTEGER,
        InstrumentID INTEGER,
        InstrumentTime INTEGER,
        FOREIGN KEY(Source) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(LedgerID) REFERENCES Ledger(ID) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY(InstrumentID) REFERENCES Locations(ID) ON UPDATE CASCADE ON DELETE RESTRICT
    );
    """,
    "CREATE INDEX IF NOT EXISTS idx_discards_ledger ON Discards(LedgerID);",
    "CREATE INDEX IF NOT EXISTS idx_discards_source ON Discards(Source);",
)

_create_discard_table!(db) = foreach(s->DBInterface.execute(db,s),_discard_table_statements)

# a database made before discards existed gains the table when it is connected to
function _ensure_discard_table!()
    _table_exists("Locations") && !_table_exists("Discards") && foreach(execute_db,_discard_table_statements)
    return nothing
end

"""
    upload_discard(source::Well, quant::Union{Unitful.Mass,Unitful.Volume}; ledger_id, time, instrument_id, instrument_time)

Commit a discard of `quant` from `source`. Pure persistence, like [`upload_transfer`](@ref): the
in-memory change is [`discard!`](@ref), normally run through `upload(discard!, ...)` or
`update(discard!, ...)`.
"""
function upload_discard(source::Well,quant::Union{Unitful.Mass,Unitful.Volume};ledger_id::Integer=append_ledger(),time::DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    execute_db("INSERT INTO Discards(LedgerID,Source,Quantity,Unit,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?,?)",
        (ledger_id,location_id(source),ustrip(quant),string(unit(quant)),db_time(time),instrument_id,_optional_db_time(instrument_time)))
    return nothing
end

"""
    upload_remove_from_parent(child::Location; ledger_id, time, instrument_id, instrument_time)

Commit that `child` was taken out of its parent. It is a `Movements` row with no parent. Pure
persistence: the in-memory change is [`remove_from_parent!`](@ref).
"""
function upload_remove_from_parent(child::Location;ledger_id::Integer=append_ledger(),time::DateTime=now(),
        instrument_id::Union{Integer,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    execute_db("INSERT INTO Movements(LedgerID,Parent,Child,Time,InstrumentID,InstrumentTime) Values(?,?,?,?,?,?)",
        (ledger_id,missing,location_id(child),db_time(time),instrument_id,_optional_db_time(instrument_time)))
    return nothing
end

"""
    isa_discard(ledger_id::Integer)

`true` if the ledger entry `ledger_id` is a discard.
"""
isa_discard(ledger_id::Integer) = nrow(query_db("SELECT 1 FROM Discards WHERE LedgerID = ?",(ledger_id,))) > 0

# the source of every discard recorded under `ledger_id`
function get_discard_source(ledger_id::Integer)
    return Vector{Int}(query_db("SELECT Source FROM Discards WHERE LedgerID = ? ORDER BY ID",(ledger_id,)).Source)
end

function validate_discard(ledger_id::Integer;encumbrances=false)
    src=unique(get_discard_source(ledger_id))
    seq_id=get_sequence_id(ledger_id)
    # replaying from this entry on fails if the amended history withdraws more than a well holds
    isempty(src) || reconstruct_contents(src,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing
end

# repair the content caches of every source discarded from in any revision of this entry's slot, and of
# the wells downstream of them
function repair_discard_caches(ledger_id::Integer)
    sequence_id=get_sequence_id(ledger_id)
    sources=unique(reduce(vcat,get_discard_source.(get_all_ledger_ids(sequence_id));init=Int[]))
    repair_content_caches(Vector{Int}(sources),sequence_id)
end
