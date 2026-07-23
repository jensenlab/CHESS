
function get_last_experiment_id(time::DateTime=Dates.now())
    ledger_time = db_time(time)
    x = "SELECT Max(ID) FROM Experiments WHERE TIME <= ?"
    current_id = query_db(x,(ledger_time,))
    return current_id[1,1]
end

function get_last_run_id()
    x = "SELECT Max(ID) FROM Runs"
    current_id = query_db(x)
    return current_id[1,1]
end 





function get_run(run_id::Integer)
    run_info=query_db("SELECT * FROM Runs WHERE ID =?",(run_id,))
    if nrow(run_info) == 0 
        error("run id not found")
    end 
    out=run_info[1,:]
    exp_id=out["ExperimentID"]
    loc_id=out["LocationID"]
    control_str= out["Controls"]
    blank_str=out["Blanks"]

    control_vec = parse_int_string(control_str)
    blank_vec = parse_int_string(blank_str)

    return Run(loc_id,exp_id,control_vec,blank_vec)

    
end 


function parse_int_string(str::AbstractString)
    # check to see whether string is empty 
    if length(str) == 0 
        return Int64[]
    else # parse the string 
        split_str= split(str,",") # split the string by comma separators
        split_str= filter(x->length(x)> 0,split_str)


        return parse.(Int,split_str)
    end 
end 







function get_all_runs(exp_id::Integer)
    run_info=query_db("SELECT * FROM Runs WHERE ExperimentID =?",(exp_id,))


    all_runs = Run[] 

    for i in 1:nrow(run_info)
            out=run_info[i,:]
        exp_id=out["ExperimentID"]
        loc_id=out["LocationID"]
        control_str= out["Controls"]
        blank_str=out["Blanks"]
        control_vec = parse_int_string(control_str)
        blank_vec = parse_int_string(blank_str)
        push!(all_runs,Run(loc_id,exp_id,control_vec,blank_vec))
    end 
    return all_runs 
end 




