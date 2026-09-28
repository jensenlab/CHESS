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
    update(fun::Function, args...; ledger_id=append_ledger(), time=Dates.now(), instrument=nothing, instrument_time=nothing) -> Integer

Run an operation and record it at a chosen point in the ledger, then validate the result and repair
any caches it invalidates. Returns the ledger ID the operation was written to.

`update` works like [`upload`](@ref), but is meant for amending history: pass
`ledger_id=replace_ledger(sequence_id)` to revise an existing entry, or `insert_ledger(sequence_id)`
to add one in the middle. A replacement must be the same kind of operation as the entry it replaces,
otherwise an error is thrown. Everything runs in one SQL transaction, so a failure leaves the
database unchanged.

See also: [`replace_ledger`](@ref), [`insert_ledger`](@ref).

# Examples

```julia
update(transfer!, well_a, well_b, 1u"g"; ledger_id=replace_ledger(54))
```
"""
function update(fun::Function,args...;ledger_id::Integer=append_ledger(),time::DateTime=Dates.now(),
        instrument::Union{Location,Nothing}=nothing,instrument_time::Union{DateTime,Nothing}=nothing)
    instrument_id = isnothing(instrument) ? nothing : location_id(instrument)
    up_fun=upload_operation(fun)
    function update_transaction()
        fun(args...;instrument=instrument)
        up_fun(args...;ledger_id=ledger_id, time=time, instrument_id=instrument_id, instrument_time=instrument_time)
        process_update(ledger_id)
    end
    sql_transaction(update_transaction)
    return ledger_id
end

function process_update(ledger_id::Integer)
        ids=get_all_ledger_ids(get_sequence_id(ledger_id))
        if length(ids) > 1 
            validate_operation_type(ids[end])==validate_operation_type(ids[end-1]) || error("the new operation is not the same type of operation as the previous one")
        end

        validate(ledger_id)
        cache_repair(ledger_id)
end

    


