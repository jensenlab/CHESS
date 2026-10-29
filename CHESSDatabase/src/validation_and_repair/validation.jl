# The validation of each kind of operation an entry can hold (see `operation_classes`). Reads and instrument
# settings change nothing that is replayed, so they have none.
function validate_operation_types(ledger_id::Integer)
    classes=operation_classes(ledger_id)
    isempty(classes) && error("validate operation not supported")
    return [_validator(c) for c in classes]
end

function _validator(class::Symbol)
    class === :transfer && return validate_transfer
    class === :discard && return validate_discard
    class === :movement && return validate_movement
    class === :attribute && return validate_environment_attribute
    class === :lock && return validate_lock
    class === :activity && return validate_activity
    class === :observation && return validate_observation
    return (ledger_id;encumbrances=false) -> nothing # :read, :setting
end

function validate(ledger_id::Integer;encumbrances=false)
    for validation in validate_operation_types(ledger_id)
        validation(ledger_id;encumbrances=encumbrances)
    end
    return nothing
end



function validate_transfer(ledger_id::Integer;encumbrances=false)
    # simulate the effect of the operation at `ledger_id`. We care only if the operation is impossible. 
    participants=get_transfer_participants(ledger_id::Integer)
    wells=unique(vcat([collect(p) for p in participants]...))

    seq_id=get_sequence_id(ledger_id)
    # force simulation for any entry after seq_id using the `max_cache` argument
    # (this also checks all descendents because we are reconstructing up until current time)
    isempty(wells) || reconstruct_contents(wells,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end 


function validate_movement(ledger_id::Integer;encumbrances=false)

    seq_id=get_sequence_id(ledger_id)

    for (prt,chld) in get_movement_participants(ledger_id)
        ismissing(prt) || reconstruct_children(prt,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances) # a removal has no new parent
        reconstruct_parent(chld,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    end
    return nothing 
end 


function validate_environment_attribute(ledger_id::Integer;encumbrances=false)
    locs=unique(get_environment_attribute_participant(ledger_id))
    seq_id=get_sequence_id(ledger_id)

    for loc_id in locs
        reconstruct_attributes(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    end
    return nothing 
end 

function validate_activity(ledger_id::Integer;encumbrances=false)
    seq_id=get_sequence_id(ledger_id)
    for loc_id in unique(get_activity_participant(ledger_id))
        reconstruct_activity(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    end
    return nothing 
end

function validate_lock(ledger_id::Integer;encumbrances=false)
    seq_id=get_sequence_id(ledger_id)
    for loc_id in unique(get_lock_participant(ledger_id))
        reconstruct_lock(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    end
    return nothing 
end
