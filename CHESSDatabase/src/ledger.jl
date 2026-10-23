#=
The Ledger table (ID, SequenceID, Time) is a logical clock, deliberately decoupled from both
physical insertion order (ID, SQLite's own rowid) and wall-clock time (Time). There are three ways to
write to it, only two of which have names:

  - append_ledger()            -- new slot at the end of history.
  - insert_ledger(sequence_id) -- new slot in the middle; shifts every existing SequenceID >=
                                   sequence_id forward by one to make room.
  - replace_ledger(sequence_id) (below) -- a new revision of an *already-occupied* slot. The logical
                                   position doesn't move; a new row (higher ID, later Time) supersedes
                                   the old one for reconstructions as of any transaction-time at or
                                   after the replacement, while the old row remains reconstructable
                                   for any "as of time T" query where T predates it.

This is bitemporal, git-like versioning: SequenceID is valid-time (where an event sits in the story,
revisable via replace_ledger/insert_ledger), Time is transaction-time (when the system recorded it,
immutable once written). Every reconstruction query in this package resolves a SequenceID slot to its
current revision the same way: `SELECT Max(ID), SequenceID, Time ... WHERE Time <= cutoff ... GROUP BY
SequenceID` -- the highest-ID (most recently written) row no later than the requested cutoff wins. This
is also exactly what cache_repair's invalidation check tests ("has this slot been amended since the
cache was taken").

Because replace_ledger and append_ledger/insert_ledger all funnel through the same update_ledger
primitive, and SequenceID intentionally has no uniqueness constraint (a fresh revision of an existing
slot is a feature, not a bug -- see replace_ledger below), get_last_ledger_id()'s two forms mean
different things and are not interchangeable: get_last_ledger_id(sequence_id, time) resolves *a given
slot* to its current revision (safe to use for bounding reconstruction queries); the bare
get_last_ledger_id() returns the physically newest row in the whole table, regardless of which slot it
revises -- appropriate for timestamping something meant to attach to "whatever just happened" (its only
current caller is upload_protocol's ledger_id_entered_at default, provenance metadata, never used to
bound a query), but not a substitute for "the current end of the story" once anything has ever been
replaced.
=#

# The time written to a new ledger row: the current time, but never earlier than the newest row's time.
# `Ledger.Time` is the transaction time that decides which revision of a slot is current, so it must not go
# backward when the system clock does (a step back would make a newer revision look older than the one it
# replaces). The newest row is the one with the highest `ID` -- an O(1) rowid lookup, unlike `Max(Time)`.
const _monotone_ledger_time = "MAX(?, COALESCE((SELECT Time FROM Ledger ORDER BY ID DESC LIMIT 1), ?))"

"""
    append_ledger()
Add an entry to the end of ledger and return the ID of that entry.

The next sequence ID is read and the row inserted by a single statement, so two writers cannot be given
the same sequence ID (which would make the second look like an amendment of the first). Call it inside
the transaction that writes the operation, as [`upload`](@ref) and [`update`](@ref) do: if the
transaction fails, the row is rolled back with it.
"""
function append_ledger()
    now_time=db_time(Dates.now())
    execute_db("""
    INSERT INTO Ledger(SequenceID,Time)
    SELECT COALESCE(Max(SequenceID),0)+1, $_monotone_ledger_time FROM Ledger
    """,(now_time,now_time))
    return _last_inserted_ledger_id()
end

_last_inserted_ledger_id() = query_db("SELECT last_insert_rowid() AS id")[1,1]



"""
    insert_ledger()

Increase the **SequenceID** value for all ledger entries whose **SequenceID** Value is greater than or equal to `sequence_id`, then insert a ledger new entry into the sequence at `sequence_id`
"""
function insert_ledger(sequence_id::Integer)
    return sql_transaction() do
        execute_db("""
        UPDATE Ledger SET SequenceID = SequenceID +1 WHERE SequenceID >= ?
        """,(sequence_id,))
        update_ledger(sequence_id)
    end
end





"""
    update_ledger(sequenceID::Integer)

Low-level primitive: insert a new `Ledger` row at `sequenceID`, stamped with the current time (or the
newest row's time if that is later, so ledger times never go backward), and return its `ID`.
[`insert_ledger`](@ref) funnels through this. Called directly on an *already-occupied* `sequenceID`, it's the ledger's "replace" operation -- prefer
[`replace_ledger`](@ref) for that, since it asserts the slot already exists instead of silently
succeeding either way.
"""
function update_ledger(sequenceID::Integer)
    now_time=db_time(Dates.now())
    execute_db("""
    INSERT INTO Ledger(SequenceID,Time)
    SELECT ?, $_monotone_ledger_time
    """,(sequenceID,now_time,now_time))
    return _last_inserted_ledger_id()
end


"""
    replace_ledger(sequence_id::Integer)

Create a new revision of an already-used `SequenceID` slot -- the ledger's "amend" operation (see the
module-level note above `append_ledger`). Asserts `sequence_id` is currently occupied; use
[`append_ledger`](@ref) or [`insert_ledger`](@ref) for a slot that doesn't exist yet.
"""
function replace_ledger(sequence_id::Integer)
    exists=query_db("SELECT 1 FROM Ledger WHERE SequenceID = ? LIMIT 1",(sequence_id,))
    nrow(exists) == 0 && error("sequence_id $sequence_id does not exist yet -- use append_ledger or insert_ledger")
    return update_ledger(sequence_id)
end





"""
    get_last_ledger_id(time::DateTime=Dates.now())

Return the most recent ledger id entry at or before a certain time
"""
function get_last_ledger_id(time::DateTime=Dates.now())
    ledger_time = db_time(time)
    # newest row first by rowid: stops at the first row written by `time`
    x = "SELECT ID FROM Ledger WHERE Time <= ? ORDER BY ID DESC LIMIT 1"
    current_id = query_db(x,(ledger_time,))
    return nrow(current_id) == 0 ? missing : current_id[1,1]
end

function get_last_ledger_id(sequence_id::Integer,time::DateTime=Dates.now())
    return visible_ledger_id(sequence_id,time)
end

"""
    get_last_sequence_id(time::DateTime=Dates.now()) -> Integer

The newest sequence ID in the ledger as of `time`: the current end of the history.
"""
function get_last_sequence_id(time::DateTime=Dates.now())
    ledger_time = db_time(time)
    # walks `Ledger(SequenceID, ID)` from the top and stops at the first row written by `time`
    x= "SELECT SequenceID FROM Ledger WHERE Time <= ? ORDER BY SequenceID DESC LIMIT 1"
    current_id = query_db(x,(ledger_time,))
    return nrow(current_id) == 0 ? missing : current_id[1,1]
end


"""
    get_sequence_id(ledger_id::Integer) -> Integer

The sequence ID (position in the history) of ledger row `ledger_id`. Several ledger rows share a
sequence ID when an entry has been revised with [`replace_ledger`](@ref).
"""
function get_sequence_id(ledger_id::Integer)
    x="SELECT SequenceID FROM Ledger WHERE Id = ?"
    return query_db(x,(ledger_id,))[1,1]
end


function get_all_ledger_ids(sequence_id::Integer,time::DateTime=Dates.now())
    ledger_time=db_time(time)
    x="SELECT ID FROM Ledger WHERE SequenceID = ? AND Time <= ? ORDER BY ID"
    current_id=query_db(x,(sequence_id,ledger_time))
    return current_id[:,"ID"]
end


function get_ledger_time(ledger_id::Integer)
    x="SELECT Time FROM Ledger WHERE ID=?"
    return julia_time(query_db(x,(ledger_id,))[1,1])
end







function isa_transfer(ledger_id::Integer)

    x=" SELECT  LedgerID FROM Transfers WHERE LedgerID = ?"
    out=query_db(x,(ledger_id,))
    if nrow(out) == 1
        return true
    else
        return false
    end
end


function isa_movement(ledger_id::Integer)
    x=" SELECT LedgerID FROM Movements WHERE LedgerID = ?"
    out=query_db(x,(ledger_id,))
    if nrow(out) == 1
        return true
    else
        return false
    end
end

function isa_environment_attribute(ledger_id::Integer)
    x= "SELECT LedgerID FROM EnvironmentAttributes WHERE LedgerID = ?"
    out=query_db(x,(ledger_id,))
    if nrow(out) == 1
        return true
    else
        return false
    end
end


function isa_lock(ledger_id::Integer)
    x= "SELECT LedgerID FROM Locks WHERE LedgerID = ?"
    out=query_db(x,(ledger_id,))
    if nrow(out) == 1
        return true
    else
        return false
    end
end

function isa_activity(ledger_id::Integer)
    x= "SELECT LedgerID FROM Activity WHERE LedgerID = ?"
    out=query_db(x,(ledger_id,))
    if nrow(out) == 1
        return true
    else
        return false
    end
end
