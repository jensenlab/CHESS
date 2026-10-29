#=
Simultaneous ticks: several operations recorded under one ledger entry.

The rule (decision D4, option O3 of the reconstruction plan, section 6):

  - A transfer, discard, movement, lock or activity operation is alone in its tick. Its effect depends on the
    state before it, so two of them in one tick would need an order the ledger does not store.
  - Reads, environment attributes, instrument settings and observations may share a tick, as long as no two
    of them state the same fact: the same (location, attribute), the same (instrument, setting), the same
    (location, component), the same child, lock, activity or lot of one location. Their order does not matter.
    Reads never conflict with each other.

The rule is enforced when a tick is written (`upload`, `update`, `observe`, `upload_tick`, `update_tick`) and
checked on existing data by `audit_ticks`. `tick_rule_enforcement!(false)` switches the enforcement off (and
`ENV["CHESS_TICK_RULE"]="off"` at startup); validation, cache repair and replay handle a tick with several
operations either way, so the data stays readable.
=#

# (table, class, order-dependent, SQL text that names the fact a row states)
const _TICK_TABLES = (
    ("Transfers",             :transfer,    true,  nothing),
    ("Discards",              :discard,     true,  nothing),
    ("Movements",             :movement,    true,  nothing),
    ("Locks",                 :lock,        true,  nothing),
    ("Activity",              :activity,    true,  nothing),
    ("EnvironmentAttributes", :attribute,   false, "'attribute '||LocationID||' '||Attribute"),
    ("Reads",                 :read,        false, nothing),
    ("InstrumentSettings",    :setting,     false, "'setting '||InstrumentID||' '||Setting"),
    ("ObservedComponents",    :observation, false, "'component '||LocationID||' '||ComponentID"),
    ("ObservedAttributes",    :observation, false, "'attribute '||LocationID||' '||Attribute"),
    ("ObservedParents",       :observation, false, "'parent of '||Child"),
    ("ObservedLocks",         :observation, false, "'lock '||LocationID"),
    ("ObservedActivity",      :observation, false, "'activity '||LocationID"),
    ("ObservedLots",          :observation, false, "'lot '||LocationID"),
)

# order of the classes when an entry holds several: the order validation and repair run in
const _CLASS_ORDER = (:transfer,:discard,:movement,:attribute,:lock,:activity,:observation,:read,:setting)

"""
    tick_rule_enforced

`Ref` holding whether the rule of simultaneous ticks is enforced when operations are written (default `true`). Set
with [`tick_rule_enforcement!`](@ref) or, at startup, `ENV["CHESS_TICK_RULE"] = "off"`.
"""
const tick_rule_enforced = Ref(true)

"""
    tick_rule_enforcement!(on::Bool) -> Bool

Switch the enforcement of the one-operation-per-tick rule on or off and return the previous setting. Switched off,
`upload`, `update`, `observe`, `upload_tick` and `update_tick` accept any tick; [`audit_ticks`](@ref) still reports
the ticks that break the rule.
"""
function tick_rule_enforcement!(on::Bool)
    old = tick_rule_enforced[]
    tick_rule_enforced[] = on
    return old
end

_tick_union(f) = join([f(t) for t in _TICK_TABLES]," UNION ALL ")

"""
    tick_operations(ledger_id::Integer) -> DataFrame

The operation rows recorded under ledger entry `ledger_id`, one row each, with the columns `Table`, `RowID`,
`Class`, `OrderDependent` and `Fact` (the fact the row states, `missing` for operations that state none).
"""
function tick_operations(ledger_id::Integer)
    sql = _tick_union() do (tbl,cls,dep,fact)
        "SELECT '$tbl' AS Tbl, ID AS RowID, '$cls' AS Class, $(dep ? 1 : 0) AS Dep, $(isnothing(fact) ? "NULL" : fact) AS Fact FROM $tbl WHERE LedgerID = ?"
    end
    out = query_db(sql,ntuple(_ -> ledger_id,length(_TICK_TABLES)))
    return DataFrame(Table=String.(out.Tbl),RowID=Int.(out.RowID),Class=Symbol.(out.Class),OrderDependent=out.Dep .== 1,Fact=out.Fact)
end

# the first pair of rows in `ops` that cannot share a tick, or `nothing`
function _tick_conflict(ops::AbstractDataFrame)
    nrow(ops) < 2 && return nothing
    dep = findfirst(ops.OrderDependent)
    if dep !== nothing
        other = dep == 1 ? 2 : 1
        return (first=ops[dep,:],second=ops[other,:],
            reason="a $(ops.Class[dep]) depends on the order of operations, so it must be alone in its tick")
    end
    seen = Dict{String,Int}()
    for i in 1:nrow(ops)
        ismissing(ops.Fact[i]) && continue
        j = get!(seen,ops.Fact[i],i)
        j == i && continue
        return (first=ops[j,:],second=ops[i,:],reason="both state the same fact (" * ops.Fact[i] * ")")
    end
    return nothing
end

_describe_row(r) = "$(r.Table) row $(r.RowID)"

"""
    check_tick(ledger_id::Integer)

Throw an `ArgumentError` naming the offending pair of operations if ledger entry `ledger_id` holds two that cannot
share a tick (see [`audit_ticks`](@ref) for the rule). Does nothing when the enforcement is switched off with
[`tick_rule_enforcement!`](@ref).
"""
function check_tick(ledger_id::Integer)
    tick_rule_enforced[] || return nothing
    c = _tick_conflict(tick_operations(ledger_id))
    c === nothing && return nothing
    seq = get_sequence_id(ledger_id)
    throw(ArgumentError("ledger entry $ledger_id (slot $seq) cannot hold $(_describe_row(c.first)) and $(_describe_row(c.second)): $(c.reason)"))
end

"""
    audit_ticks() -> DataFrame

Find the ledger entries that break the rule of simultaneous ticks, so that existing data can be examined before
the enforcement is relied on. Run it on a database written before the rule existed.

The rule: a transfer, discard, movement, lock or activity is alone in its tick; reads, environment attributes,
instrument settings and observations can share a tick if no two state the same fact (the same location and
attribute, instrument and setting, location and component, child, lock, activity or lot of a location).

One row per entry in violation, with the columns `LedgerID`, `SequenceID`, `Current` (whether the entry is the
current revision of its slot, so that a violation in a superseded revision can be told from one in force),
`First`, `Second` (the offending pair, as `"Table row id"`), `Reason`, and `Operations` (how many operations the
entry holds). Empty when the database has none. Superseded revisions are included.
"""
function audit_ticks()
    # entries with more than one operation; only those can break the rule
    sql = "SELECT LedgerID, COUNT(*) AS n FROM (" * _tick_union(t -> "SELECT LedgerID FROM $(t[1])") * ") GROUP BY LedgerID HAVING COUNT(*) > 1"
    candidates = query_db(sql)
    out = DataFrame(LedgerID=Int[],SequenceID=Int[],Current=Bool[],First=String[],Second=String[],Reason=String[],Operations=Int[])
    for row in eachrow(candidates)
        ismissing(row.LedgerID) && continue
        c = _tick_conflict(tick_operations(row.LedgerID))
        c === nothing && continue
        seq = get_sequence_id(row.LedgerID)
        current = visible_ledger_id(seq) == row.LedgerID
        push!(out,(row.LedgerID,seq,current,_describe_row(c.first),_describe_row(c.second),c.reason,row.n))
    end
    return sort!(out,[:SequenceID,:LedgerID])
end

"""
    operation_classes(ledger_id::Integer) -> Vector{Symbol}

The kinds of operation recorded under ledger entry `ledger_id`, from `:transfer`, `:discard`, `:movement`,
`:attribute`, `:lock`, `:activity`, `:observation`, `:read` and `:setting`, in the order validation and cache
repair handle them.
"""
function operation_classes(ledger_id::Integer)
    present = Set(tick_operations(ledger_id).Class)
    return Symbol[c for c in _CLASS_ORDER if c in present]
end

# ---------------------------------------------------------------------------------------- writing a tick

# one operation of a tick: a tuple `(fun, args...)`
function _run_tick_operations!(ops,ledger_id::Integer,time::DateTime,instrument,instrument_id,instrument_time)
    for op in ops
        fun = first(op)
        args = Base.tail(op)
        fun(args...;instrument=instrument)
        upload_operation(fun)(args...;ledger_id=ledger_id,time=time,instrument_id=instrument_id,instrument_time=instrument_time)
    end
end

function _check_tick_operations(ops)
    isempty(ops) && throw(ArgumentError("a tick needs at least one operation"))
    for op in ops
        (op isa Tuple && !isempty(op) && first(op) isa Function) ||
            throw(ArgumentError("each operation of a tick is a tuple (operation, arguments...), for example (transfer!, a, b, 1u\"mL\"); got $(repr(op))"))
        CHESSCore.assert_all_committed(Base.tail(op)...)
    end
end

"""
    upload_tick(operations...; time=Dates.now(), instrument=nothing, instrument_time=nothing) -> Integer

Record several operations as one tick (one ledger entry) and return the ledger ID. Each operation is a tuple of an
operation function and its arguments, as would be passed to [`upload`](@ref):

```julia
upload_tick((set_attribute!, incubator, Temperature(37u"°C")),
            (set_attribute!, incubator, Humidity(0.9)),
            (record_read!, plate, read))
```

The operations are applied in memory in the order given and recorded together. Operations that depend on order
(transfer, discard, movement, lock, activity) cannot share a tick, and neither can two operations that state the
same fact; the error names the pair, and nothing is recorded. See [`audit_ticks`](@ref) for the rule.
"""
function upload_tick(operations::Tuple...;time::DateTime=Dates.now(),instrument::Union{Location,Nothing}=nothing,
        instrument_time::Union{DateTime,Nothing}=nothing)
    _check_tick_operations(operations)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    function tick_transaction()
        l_id = append_ledger()
        _run_tick_operations!(operations,l_id,time,instrument,instrument_id,instrument_time)
        check_tick(l_id)
        return l_id
    end
    return sql_transaction(tick_transaction)
end

"""
    update_tick(operations...; replace=nothing, insert=nothing, time=Dates.now(), instrument=nothing, instrument_time=nothing) -> Integer

Record the complete set of operations of a tick at a chosen point in the ledger, then validate the result and
repair the caches it invalidates, as [`update`](@ref) does for one operation.

- `replace=s` records a new revision of the entry at sequence ID `s`. The operations given are the whole of the new
  revision: an operation of the old revision that is not repeated is dropped, so a replacement has to state every
  operation it keeps. The kinds of operation must be the same as in the entry replaced.
- `insert=s` adds a new entry at sequence ID `s`.
- With neither, the tick is appended.

The same rule as [`upload_tick`](@ref) applies, and any failure leaves the database as it was.
"""
function update_tick(operations::Tuple...;replace::Union{Integer,Nothing}=nothing,insert::Union{Integer,Nothing}=nothing,
        time::DateTime=Dates.now(),instrument::Union{Location,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    isnothing(replace) || isnothing(insert) || throw(ArgumentError("pass at most one of replace and insert"))
    _check_tick_operations(operations)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    function tick_transaction()
        l_id = !isnothing(replace) ? replace_ledger(replace) : !isnothing(insert) ? insert_ledger(insert) : append_ledger()
        _run_tick_operations!(operations,l_id,time,instrument,instrument_id,instrument_time)
        check_tick(l_id)
        process_update(l_id)
        return l_id
    end
    return sql_transaction(tick_transaction)
end

# `update(...; replace=s)` states one operation, so it must not stand in for a slot of several
function _refuse_multi_operation_slot(slot::Integer)
    current = visible_ledger_id(slot)
    ismissing(current) && return nothing
    n = nrow(tick_operations(current))
    n > 1 && throw(ArgumentError("slot $slot holds $n operations (ledger entry $current); a replacement of one operation would drop the others. Use update_tick to replace the complete set"))
    return nothing
end
