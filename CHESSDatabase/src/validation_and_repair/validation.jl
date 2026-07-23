function validate_operation_type(ledger_id::Integer)
    if isa_transfer(ledger_id)
        return validate_transfer
    elseif isa_movement(ledger_id)
        return validate_movement
    elseif isa_environment_attribute(ledger_id)
        return validate_environment_attribute
    elseif isa_lock(ledger_id)
        return validate_lock
    elseif isa_activity(ledger_id)
        return validate_activity
    else
        error("validate operation not supported")
    end 

end 





function validate(ledger_id::Integer;encumbrances=false)

    validation=validate_operation_type(ledger_id)


    validation(ledger_id;encumbrances=encumbrances)


end



function validate_transfer(ledger_id::Integer;encumbrances=false)
    # simulate the effect of the operation at `ledger_id`. We care only if the operation is impossible. 
    src,dest=get_transfer_participants(ledger_id::Integer)

    seq_id=get_sequence_id(ledger_id)
    # force simulation for any entry after seq_id using the `max_cache` argument
    a=reconstruct_contents(src,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances) #this also checks all descendents because we are reconstructing up until current time

    b=reconstruct_contents(src,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end 


function validate_movement(ledger_id::Integer;encumbrances=false)

    prt,chld=get_movement_participants(ledger_id)

    seq_id=get_sequence_id(ledger_id)

    a=reconstruct_children(prt,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    b=reconstruct_parent(chld,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end 


function validate_environment_attribute(ledger_id::Integer;encumbrances=false)
    loc_id=get_environment_attribute_participant(ledger_id)
    seq_id=get_sequence_id(ledger_id)

    a=reconstruct_attributes(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end 

function validate_activity(ledger_id::Integer;encumbrances=false)
    loc_id=get_activity_participant(ledger_id)
    seq_id=get_sequence_id(ledger_id)
    reconstruct_activity(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end

function validate_lock(ledger_id::Integer;encumbrances=false)
    loc_id=get_lock_participant(ledger_id)
    seq_id=get_sequence_id(ledger_id)
    reconstruct_lock(loc_id,get_last_sequence_id(),Dates.now(),seq_id;encumbrances=encumbrances)
    return nothing 
end
