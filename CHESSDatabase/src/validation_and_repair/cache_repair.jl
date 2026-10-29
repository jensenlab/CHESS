function repair_operation_types(ledger_id::Integer)
    classes=operation_classes(ledger_id)
    isempty(classes) && error("cache repair operation not supported")
    return [_repairer(c) for c in classes]
end

function _repairer(class::Symbol)
    class === :transfer && return repair_content_caches
    class === :discard && return repair_discard_caches
    class === :movement && return repair_movement_caches
    class === :attribute && return repair_environment_attribute_caches
    class === :lock && return repair_lock_caches
    class === :activity && return repair_activity_caches
    class === :observation && return repair_observation_caches
    return ledger_id -> nothing # :read, :setting: nothing is cached from them
end

"""
    cache_repair(ledger_id::Integer)

Repairs caches affected by updates, insertions, and deletions from the ledger.

When a cache is invalidated by an operation, a new cache is written to replace the old cache in future reconstructions. 

The old cache will still be utilized for reconstrutions triggered at a time before the cache was repaired.
"""
function cache_repair(ledger_id::Integer)

    for repair in repair_operation_types(ledger_id)
        repair(ledger_id)
    end
    return nothing

end


# see get_transfer_participants, get_movement_participants,get_activity_participants, etc... 
function get_participants(fun::Function,sequence_id::Integer)

    ls=get_all_ledger_ids(sequence_id)

    # every row of every revision of the slot: an entry can hold several operations of a kind
    return reduce(vcat,[fun(l) for l in ls])
end 