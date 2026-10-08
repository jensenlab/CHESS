
"""
    struct Run
    Run(loc::Location, exp_id::Integer, controls=Integer[], blanks=Integer[])

One run of an experiment: the location it was performed in, the experiment's ID, and the location
IDs of its controls and blanks. Record it with [`upload_run`](@ref).
"""
struct Run
    location_id::Integer
    exp_id::Integer
    controls::Vector{<:Integer}
    blanks::Vector{<:Integer}
end 



function Run(loc::Location,exp_id::Integer,controls::Vector{<:Integer}=Integer[],blanks::Vector{<:Integer}=Integer[])
    return Run(location_id(loc),exp_id,controls,blanks)
end 



function blanks(run::Run)
    return run.blanks 
end 

function controls(run::Run)
    return run.controls
end 

function location_id(run::Run)
    return run.location_id 
end 

function experiment_id(run::Run) 
    return run.exp_id 
end 





