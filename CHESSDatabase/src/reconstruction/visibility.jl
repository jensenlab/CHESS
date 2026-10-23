#=
The one place the ledger's visibility rule is written down.

A ledger row is the current revision of its slot (`SequenceID`) as of a transaction time `t` when it was
written at or before `t` and no later revision of the same slot (a row with the same `SequenceID` and a
higher `ID`) was written at or before `t`. An operation row (a transfer, a movement, a cache, ...) is
*visible* in a window `[from, to]` at time `t` when the ledger row it points at (`LedgerID`) is the current
revision of a slot inside the window.

That is exactly membership in the `ledger_subset` CTE the reconstruction queries use,

    SELECT Max(ID), SequenceID, Time FROM Ledger WHERE Time <= t AND SequenceID BETWEEN from AND to GROUP BY SequenceID

because a row is that `Max(ID)` of its slot if and only if it satisfies `Time <= t` and no same-slot row
with a higher `ID` has `Time <= t`. Written this way the rule is a per-row predicate: it can be applied to
a handful of operation rows found through an index instead of to the whole ledger.
=#

# The predicate on a ledger row aliased `ledger`, with the bounds and time given as SQL text (a literal or a
# `:name` / `?` placeholder).
_visible_predicate(ledger,from,to,t) = """
    $ledger.SequenceID BETWEEN $from AND $to AND $ledger.Time <= $t
      AND NOT EXISTS (SELECT 1 FROM Ledger r WHERE r.SequenceID = $ledger.SequenceID
                      AND r.ID > $ledger.ID AND r.Time <= $t)"""

"""
    visible_join(op; ledger="vl", from=":from", to=":to", t=":t") -> String

A SQL `INNER JOIN` fragment that keeps the rows of the operation table aliased `op` (which must have a
`LedgerID` column) whose ledger row is visible in the slot window `from..to` at transaction time `t`.
The ledger row is available as `ledger` (default `vl`), so a query can also read its `SequenceID`.
`from`, `to` and `t` are SQL text: a literal, or a placeholder such as `:from` or `?`. `predicate` replaces
the visibility rule itself; only the tests use it, to check that a wrong rule is caught.
"""
visible_join(op::AbstractString;ledger::AbstractString="vl",from::AbstractString=":from",to::AbstractString=":to",t::AbstractString=":t",
        predicate::Function=_visible_predicate) =
    "INNER JOIN Ledger $ledger ON $ledger.ID = $op.LedgerID AND " * predicate(ledger,from,to,t)

"""
    visible_ledger_id(slot::Integer, time::DateTime=Dates.now()) -> Union{Integer,Missing}

The `ID` of the current revision of ledger slot `slot` as of `time` -- the highest `ID` with that
`SequenceID` written at or before `time` -- or `missing` if the slot did not exist then.
"""
function visible_ledger_id(slot::Integer,time::DateTime=Dates.now())
    rows = query_db("SELECT ID FROM Ledger WHERE SequenceID = ? AND Time <= ? ORDER BY ID DESC LIMIT 1",(slot,db_time(time)))
    return nrow(rows) == 0 ? missing : rows[1,1]
end

"""
    is_visible(ledger_id::Integer, from::Integer, to::Integer, time::DateTime=Dates.now()) -> Bool

Whether ledger row `ledger_id` is the current revision of a slot inside `from..to` as of `time`; the
single-row form of [`visible_join`](@ref).
"""
function is_visible(ledger_id::Integer,from::Integer,to::Integer,time::DateTime=Dates.now())
    rows = query_db("SELECT 1 FROM Ledger vl WHERE vl.ID = ? AND " * _visible_predicate("vl","?","?","?"),
        (ledger_id,from,to,db_time(time),db_time(time)))
    return nrow(rows) == 1
end
