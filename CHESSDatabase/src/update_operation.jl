macro update(expr,ledger_id=append_ledger(),time=Dates.now()) 
    fun=eval(expr.args[1])
    upload_op=upload_operation(fun)
    return esc(quote 
        function update_transaction()
            $expr
            l_id=$ledger_id
            $upload_op(eval.($(expr.args[2:end]))...;ledger_id=l_id,time=$time)
            $process_update(l_id)
        end
        sql_transaction(update_transaction)
    end )
end 

"""
    update(fun::Function, args...; replace=nothing, insert=nothing, time=Dates.now(), instrument=nothing, instrument_time=nothing) -> Integer

Run an operation and record it at a chosen point in the ledger, then validate the result and repair
any caches it invalidates. Returns the ledger ID the operation was written to.

`update` works like [`upload`](@ref), but is meant for amending history:

- `replace=s` records a new revision of the entry at sequence ID `s` (see [`replace_ledger`](@ref)).
  The replacement must be the same kind of operation as the entry it replaces, otherwise an error is
  thrown.
- `insert=s` adds a new entry at sequence ID `s`, moving later entries back by one (see
  [`insert_ledger`](@ref)).
- With neither, the operation is appended at the end of the ledger.

The ledger row, the operation, validation, and cache repair all happen in one SQL transaction, so if
any step fails the database is left exactly as it was. `fun` is also applied to the in-memory
objects in `args`, as with `upload`, and that change is not undone on failure; reconstruct from the
database to see the recorded state.

`ledger_id=` is still accepted in place of `replace`/`insert`, for a ledger row allocated
beforehand, but a row allocated that way is not rolled back if `update` fails.

See also: [`replace_ledger`](@ref), [`insert_ledger`](@ref).

# Examples

```julia
update(transfer!, well_a, well_b, 1u"g"; replace=54)
```
"""
function update(fun::Function,args...;replace::Union{Integer,Nothing}=nothing,insert::Union{Integer,Nothing}=nothing,
        ledger_id::Union{Integer,Nothing}=nothing,time::DateTime=Dates.now(),
        instrument::Union{Location,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    count(!isnothing,(replace,insert,ledger_id)) <= 1 || throw(ArgumentError("pass at most one of replace, insert, and ledger_id"))
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    up_fun=upload_operation(fun)
    function update_transaction()
        # allocate the ledger row inside the transaction, so a failure below rolls it back (and, for
        # insert, the renumbering of later entries) instead of leaving an empty revision behind
        l_id = !isnothing(replace) ? replace_ledger(replace) :
               !isnothing(insert) ? insert_ledger(insert) :
               isnothing(ledger_id) ? append_ledger() : ledger_id
        fun(args...;instrument=instrument)
        up_fun(args...;ledger_id=l_id, time=time, instrument_id=instrument_id, instrument_time=instrument_time)
        process_update(l_id)
        return l_id
    end
    return sql_transaction(update_transaction)
end

"""
    process_update(ledger_id::Integer)

The checks [`update`](@ref) runs after recording an amendment at `ledger_id`: that a replacement is
the same kind of operation as the entry it replaces, that the amended history can still be replayed
(`validate`), and repair of any caches the amendment made stale (`cache_repair`).
"""
function process_update(ledger_id::Integer)
        ids=get_all_ledger_ids(get_sequence_id(ledger_id))
        if length(ids) > 1 
            validate_operation_type(ids[end])==validate_operation_type(ids[end-1]) || error("the new operation is not the same type of operation as the previous one")
        end

        validate(ledger_id)
        cache_repair(ledger_id)
end

    


