function encumber_operation(fun::Function)
    opfun_dict=Dict(
        activate! => encumber_activity,
        deactivate! => encumber_activity,
        toggle_activity! => encumber_activity,
        lock! => encumber_lock,
        unlock! => encumber_lock,
        toggle_lock! => encumber_lock,
        move_into! => encumber_movement,
        transfer! => encumber_transfer,
        set_attribute! => encumber_environment_attribute
    )
    return opfun_dict[fun]
end 





function encumber(protocol_id::Integer,fun::Function,args...)
    encumber_op=encumber_operation(fun) 
    function encumber_transaction()
    fun(args...)
    e_id=upload_encumbrance(protocol_id)
    encumber_op(e_id,args...)
    end 
    sql_transaction(encumber_transaction)
    return get_last_encumbrance_id(protocol_id)
end 

#=
macro protocol(experiment_id,name, expr)
    #=
    expt=Int(eval(experiment_id))
    expt_name=string(eval(name))
    if !isa(expt,Integer)
        error("provide an integer experiment id")
    end 

    if !isa(expt_name,String)
        error("provide a string protocol name")
    end 
    =#
    hd=expr.head
    args=expr.args
    if hd == :block 
        return esc(quote 
            expt=$experiment_id
            expt_name=$name
            p_id=upload_protocol(expt,expt_name)
            println("trigger_up")
            for arg in $args
                if arg isa Expr
                    println(typeof(arg))
                    println(typeof(p_id))
                    println(arg)
                    @encumber p_id arg
                end
            end 
        end)
    else
        return esc(quote
            expt=$experiment_id
            expt_name=$name
            p_id=upload_protocol(expt,expt_name)
            println("trigger_low")
            @encumber p_id $expr
        end)
    end 
end 
=#

function get_last_encumbrance_id(protocol_id::Integer)

    e_id=query_db("""
    SELECT Max(ID) FROM Encumbrances WHERE ProtocolID = $protocol_id""")[1,1]
    return e_id 
end 

function get_last_protocol_id(experiment_id::Integer)
    p_id = query_db("""
    SELECT Max(ID) FROM Protocols WHERE ExperimentID = $experiment_id""")[1,1]
    return p_id 
end 






function upload_protocol(exp_id::Integer,name::AbstractString,ledger_id_entered_at::Integer=get_last_ledger_id(), estimate::Dates.Time=Dates.Time(0);enforce=true)
    est_time=Dates.millisecond(estimate)
    execute_db("""
    INSERT INTO Protocols(ExperimentID,Name,LedgerIDCreatedAt,EstimatedTime) Values(?,?,?,?);
    """,(exp_id,string(name),ledger_id_entered_at,est_time))
    p_id=get_last_protocol_id(exp_id)
    if enforce
        upload_protocol_enforcement(p_id,true)
    end
    return p_id
end

function upload_protocol_enforcement(protocol_id::Integer,is_enforced::Bool;time=Dates.now())
    upload_time=db_time(time)
    ledger_id=append_ledger()
    execute_db("""INSERT INTO ProtocolEnforcement(ProtocolID,LedgerID,IsEnforced,Time) Values(?,?,?,?)""",
        (protocol_id,ledger_id,Int64(is_enforced),upload_time))
    return nothing
end

function upload_encumbrance(protocol_id::Integer, is_enforced::Bool=true;time=Dates.now())

    execute_db("""
    INSERT INTO Encumbrances(ProtocolID) Values (?)""",(protocol_id,))
    e_id=get_last_encumbrance_id(protocol_id)
    return e_id
end


function upload_encumbrance_completion(encumbrance_id::Integer,ledger_id::Integer) # pair an encumbrance to a ledger operation
    execute_db("""
    INSERT INTO EncumbranceCompletion(EncumbranceID,LedgerID) Values(?,?)""",(encumbrance_id,ledger_id))
    return nothing
end


function encumber_transfer(encumberid::Integer, source::Well,destination::Well,quant::Union{Unitful.Mass,Unitful.Volume},configuration::AbstractString="")
    execute_db("""
    INSERT INTO EncumberedTransfers(EncumbranceID,Source,Destination,Quantity,Unit,Configuration) Values(?,?,?,?,?,?)""",
        (encumberid,location_id(source),location_id(destination),ustrip(quant),string(unit(quant)),configuration))
    return nothing
end



function encumber_environment_attribute(encumberid::Integer,loc::Location,attr::Attribute)
    upload_attribute(attr)
    val=quantity(attr)
    execute_db("""INSERT INTO EncumberedEnvironments(EncumbranceID,LocationID,Attribute,Value,Unit) Values(?,?,?,?,?)""",
        (encumberid,location_id(loc),string(attribute_kind(attr).name),ustrip(val),string(unit(val))))
    return nothing
end



function encumber_movement(encumberid::Integer,parent::Location,child::Location,lock::Bool=false)
    execute_db("""INSERT INTO EncumberedMovements(EncumbranceID,Parent,Child) Values(?,?,?)""",
        (encumberid,location_id(parent),location_id(child)))
    if lock
        encumber_lock(encumberid,child) # only needed if the lock flag is true. This means that the lock state has changed (you had to be unlocked to move in the first place)
    end
    return nothing
end


function encumber_lock(encumberid::Integer,loc::Location)
    execute_db("INSERT INTO EncumberedLocks(EncumbranceID,LocationID,Lock) Values(?,?,?)",
        (encumberid,location_id(loc),Int(is_locked(loc))))
    return nothing
end

function encumber_activity(encumberid::Integer,loc::Location)
    execute_db("INSERT INTO EncumberedActivity(EncumbranceID,LocationID,Activate) Values(?,?,?)",
        (encumberid,location_id(loc),Int(is_active(loc))))
    return nothing
end


function encumber_cache(encumberid::Integer, loc::Location)
    encumber_cache_parent(encumberid,loc)

    encumber_cache_children(encumberid,loc)
    
    encumber_cache_environment(encumberid,loc)
    encumber_cache_lock_activity(encumberid,loc)
    if typeof(loc) <: CHESSCore.Well
        encumber_cache_contents(encumberid,loc)
    end 
    return nothing
end 


function encumber_cache_contents(encumberid::Integer,loc::Well)
    stock_id=cache(stock(loc))
    execute_db("INSERT INTO EncumberedCachedContents(EncumbranceID,LocationID,StockID,Cost) Values(?,?,?,?)",
        (encumberid,location_id(loc),stock_id,cost(loc)))
    return nothing
end

function encumber_cache_parent(encumberid::Integer,loc::Location)
    parent_id=location_id(parent(loc))
    execute_db("INSERT INTO EncumberedCachedAncestors(EncumbranceID,LocationID,ParentID) Values(?,?,?)",
        (encumberid,location_id(loc),parent_id))
    return nothing
end


function encumber_cache_children(encumberid::Integer,loc::Location)
    child_set_id=cache_children_helper(children(loc))

    execute_db("INSERT INTO EncumberedCachedDescendants(EncumbranceID,LocationID,ChildSetID) Values(?,?,?)",
        (encumberid,location_id(loc),child_set_id))
    return nothing
end

function encumber_cache_environment(encumberid::Integer,loc::Location)

    attr_set_id=cache(attributes(loc))
    execute_db("INSERT INTO EncumberedCachedEnvironments(EncumbranceID,LocationID,AttributeSetID) Values(?,?,?)",
        (encumberid,location_id(loc),attr_set_id))
    return nothing
end

function encumber_cache_lock_activity(encumberid::Integer,loc::Location)
    execute_db("INSERT INTO EncumberedCachedLockActivity(EncumbranceID,LocationID,IsLocked,IsActive) Values(?,?,?,?)",
        (encumberid,location_id(loc),is_locked(loc),is_active(loc)))
    return nothing
end



function get_all_encumbrances(protocol_id::Integer) 
    out=query_db("""SELECT ID FROM Encumbrances WHERE ProtocolID = $protocol_id ORDER BY ID""")
    return out[:,"ID"]
end 


function get_encumbrance_completion(encumbrance_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_time=db_time(time)
    entry =query_join_vector(encumbrance_ids) 
    out=query_db("""
        WITH y (EncumbranceID, LedgerID) 
        AS(
        SELECT Max(EncumbranceID),LedgerID FROM EncumbranceCompletion e  WHERE EncumbranceID in $entry Group BY EncumbranceID) 

        SELECT * FROM y 
        """
    )
    out_ledger= Union{Integer,Missing}[]
    complete=Bool[]
    for e in encumbrance_ids 
        idx= findfirst(x->x==e,out[:,"EncumbranceID"])
        if isnothing(idx)
            push!(out_ledger,missing)
            push!(complete,false)
        else
            push!(out_ledger,out[:,"LedgerID"][idx])
            push!(complete,true)
        end 
    end 
    return DataFrame(EncumbranceID=encumbrance_ids,LedgerID=out_ledger,IsComplete=complete)
end 


function get_all_protocols(sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now();enforced_only=true)
    starting=0 
    ending = sequence_id
    ledger_time=db_time(time)
    out= query_db("""
    With protocol_info(ExperimentID,ProtocolID,Name,UploadLedgerID,LedgerID,IsEnforced) AS( 
    SELECT p.ExperimentID , p.ID, p.Name ,p.LedgerIDCreatedAt, e.LedgerID, e.IsEnforced FROM Protocols p INNER JOIN ProtocolEnforcement e ON p.ID = e.ProtocolID
    ),
    ledger_subset (ID,SequenceID,Time)
        AS(
            SELECT ID, SequenceID,Time FROM Ledger WHERE Time <= $ledger_time AND SequenceID BETWEEN $starting AND $ending
            ),
    y (ExperimentID, ProtocolID, Name, UploadLedgerID,LedgerID, IsEnforced) AS( 
    
    SELECT p.ExperimentID, p.ProtocolID, p.Name, p.UploadLedgerID,Max(p.LedgerID),p.IsEnforced FROM protocol_info p INNER JOIN ledger_subset l ON p.LedgerID = l.ID GROUP BY p.ProtocolID
    ),
    z (ExperimentID, ExperimentName,ProtocolID, Name, UploadLedgerID,IsEnforced) AS(
    SELECT y.ExperimentID,Experiments.Name,y.ProtocolID,y.Name,y.UploadLedgerID,y.IsEnforced FROM y INNER JOIN Experiments ON y.ExperimentID =Experiments.ID 
    )

    SELECT * FROM z
    """
    )

    if enforced_only
        out = subset(out , :IsEnforced => x -> x .== 1)
    end 
    return out 
end 




function get_protocol_status(protocol_ids::Vector{<:Integer},sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now())
    ledger_id =get_last_ledger_id(sequence_id,time)
    entry =query_join_vector(protocol_ids)
    out=query_db("""
    
    With Complete(ProtocolID,Complete,Total) AS( 
    SELECT e.ProtocolID, Count(c.LedgerID<=$ledger_id),Count(e.ID) FROM Encumbrances e LEFT JOIN EncumbranceCompletion c ON c.EncumbranceID = e.ID  GROUP BY e.ProtocolID
    )
    SELECT * FROM Complete WHERE ProtocolID in $entry
    """
    )
    return out 
end 



function get_encumbered_transfer(encumbrance_id::Integer) 
    x="SELECT * FROM EncumberedTransfers WHERE EncumbranceID = $encumbrance_id"
    return query_db(x)
end 

function get_encumbered_movement(encumbrance_id::Integer)
    x="SELECT * FROM EncumberedMovements WHERE EncumbranceID = $encumbrance_id"
    return query_db(x)
end 

function get_encumbered_environment_attribute(encumbrance_id::Integer)
    x="SELECT * FROM EncumberedEnvironments WHERE EncumbranceID = $encumbrance_id"
    return query_db(x)
end 
function get_encumbered_lock(encumbrance_id::Integer)
    x="SELECT * FROM EncumberedLocks WHERE EncumbranceID = $encumbrance_id"
    return query_db(x)
end 
function get_encumbered_activity(encumbrance_id::Integer)
    x="SELECT * FROM EncumberedActivity WHERE EncumbranceID = $encumbrance_id"
    return query_db(x)
end 



function get_encumbrance_operation(encumbrance_id::Integer)
    if isa_encumbered_transfer(encumbrance_id)
        return get_encumbered_transfer
    elseif isa_encumbered_movement(encumbrance_id)
        return get_encumbered_movement
    elseif isa_encumbered_environment_attribute(encumbrance_id)
        return get_encumbered_environment_attribute
    elseif isa_encumbered_lock(encumbrance_id)
        return get_encumbered_lock
    elseif isa_encumbered_activity(encumbrance_id)
        return get_encumbered_activity
    else
        error("encumbrance operation not supported")
    end 

end 






function isa_encumbered_transfer(encumbrance_id::Integer)

    x=" SELECT  EncumbranceID FROM EncumberedTransfers WHERE EncumbranceID = $encumbrance_id"
    out=query_db(x)
    if nrow(out) == 1 
        return true 
    else 
        return false
    end
end 


function isa_encumbered_movement(encumbrance_id::Integer)
    x=" SELECT EncumbranceID FROM EncumberedMovements WHERE EncumbranceID = $encumbrance_id"
    out=query_db(x)
    if nrow(out) == 1 
        return true 
    else 
        return false
    end
end 

function isa_encumbered_environment_attribute(encumbrance_id::Integer)
    x= "SELECT EncumbranceID FROM EncumberedEnvironments WHERE EncumbranceID = $encumbrance_id"
    out=query_db(x)
    if nrow(out) == 1 
        return true 
    else 
        return false
    end
end 


function isa_encumbered_lock(encumbrance_id::Integer)
    x= "SELECT EncumbranceID FROM EncumberedLocks WHERE EncumbranceID = $encumbrance_id"
    out=query_db(x)
    if nrow(out) == 1 
        return true 
    else 
        return false
    end
end 

function isa_encumbered_activity(encumbrance_id::Integer)
    x= "SELECT EncumbranceID FROM EncumberedActivity WHERE EncumbranceID = $encumbrance_id"
    out=query_db(x)
    if nrow(out) == 1 
        return true 
    else 
        return false
    end
end 


const encumbrance_operation_names=Dict(
    get_encumbered_transfer => "Transfer",
    get_encumbered_movement => "Movement",
    get_encumbered_environment_attribute => "Environment Attribute",
    get_encumbered_lock => "Lock",
    get_encumbered_activity => "Activity",
)






function get_encumbrance_status(protocol_id::Integer,sequence_id=get_last_sequence_id(),time::DateTime=Dates.now())
    encumbrances=get_all_encumbrances(protocol_id) 
    operations = get_encumbrance_operation.(encumbrances)

    names = map( x-> encumbrance_operation_names[x] , operations)
    enc_df=DataFrame(EncumbranceID=encumbrances, Operation=names) 
    completion=get_encumbrance_completion(encumbrances,sequence_id,time)
    df = DataFrames.leftjoin(enc_df,completion, on = :EncumbranceID)

    return df 
end 


