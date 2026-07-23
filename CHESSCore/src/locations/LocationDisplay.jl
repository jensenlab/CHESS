
# Detailed, multi-line MIME"text/plain" reports for Location, mirroring StockDisplay.jl's split
# between a one-line Base.show(io,x) (kept as-is, see Location.jl) and a richer
# Base.show(io,::MIME"text/plain",x) for REPL/display(x) use.

"""
    _present_children(x::Location)

Return `x`'s children as a plain `Vector{Location}`, skipping any unassigned slots. `GenericLocation`/
`Instrument` store children in a `Vector` (always fully assigned); `Labware` stores them in a `Matrix`
that can contain unassigned slots before every socket is populated.
"""
_present_children(x::Union{GenericLocation,Instrument}) = children(x)
function _present_children(x::Labware)
    ch = children(x)
    out = Location[]
    for i in eachindex(ch)
        isassigned(ch,i) && push!(out,ch[i])
    end
    return out
end

function _location_header(io::IO,x::Location)
    printstyled(io,name(x);bold=true)
    cats = kind(x).categories
    catstr = isempty(cats) ? "" : " ($(join(cats,", ")))"
    println(io," [",kind(x).name,catstr,"]")
    idstr = is_committed(x) ? string(location_id(x)) : "N/A"
    println(io,"  id: ",idstr,"   locked: ",is_locked(x),"   active: ",is_active(x))
    p = AbstractTrees.parent(x)
    println(io,"  parent: ",isnothing(p) ? "(root)" : name(p))
end

"""
    _children_summary(io::IO,x::Location)

Print a summary (count, occupancy, breakdown by child kind) of `x`'s children -- never enumerates
every child. Prints nothing if `x` has no children.
"""
function _children_summary(io::IO,x::Location)
    kids = _present_children(x)
    isempty(kids) && return nothing
    println(io)
    printstyled(io,"Children: ";bold=true)
    occpct = round(Float64(occupancy(x))*100;digits=1)
    println(io,length(kids)," total, ",occpct,"% occupied")
    bykind = Dict{Symbol,Int}()
    for c in kids
        bykind[kind(c).name] = get(bykind,kind(c).name,0)+1
    end
    for k in sort(collect(keys(bykind)))
        println(io,"  ",k,": ",bykind[k])
    end
    return nothing
end

"""
    _attributes_summary(io::IO,x::Location)

Print `x`'s environment (own attributes overriding inherited ones, via [`environment`](@ref)) as a
table, with an `Own`/`inherited` column distinguishing locally-set attributes from inherited ones.
Prints nothing if the environment is empty.
"""
function _attributes_summary(io::IO,x::Location)
    env = environment(x)
    isempty(env) && return nothing
    own = attributes(x)
    println(io)
    printstyled(io,"Attributes:";bold=true)
    println(io)
    names = sort(collect(keys(env)))
    df = DataFrame(Attribute=names,Value=[string(env[n]) for n in names],
                   Source=[haskey(own,n) ? "own" : "inherited" for n in names])
    show(io,df;eltypes=false,show_row_number=false,summary=false)
    println(io)
    return nothing
end

"""
    _reads_summary(io::IO,x::Location;nshow::Integer=3)

Print `x`'s reads grouped by [`ReadKind`](@ref), most recent `nshow` per kind (with a "+N more" tail
note if truncated). Prints nothing if `x` has no reads.
"""
function _reads_summary(io::IO,x::Location;nshow::Integer=3)
    rs = reads(x)
    isempty(rs) && return nothing
    println(io)
    printstyled(io,"Reads:";bold=true)
    println(io)
    bykind = Dict{Symbol,Vector{Read}}()
    for r in rs
        push!(get!(()->Read[],bykind,read_kind(r).name),r)
    end
    for k in sort(collect(keys(bykind)))
        group = sort(bykind[k];by=_read_sort_key,rev=true)
        println(io,"  ",k,":")
        for r in first(group,min(nshow,length(group)))
            t = read_time(r)
            println(io,"    ",r,"  (",isnothing(t) ? "no time" : t,")")
        end
        if length(group) > nshow
            println(io,"    +",length(group)-nshow," more")
        end
    end
    return nothing
end

function Base.show(io::IO,::MIME"text/plain",x::GenericLocation)
    _location_header(io,x)
    _children_summary(io,x)
    _attributes_summary(io,x)
    _reads_summary(io,x)
end

function Base.show(io::IO,::MIME"text/plain",x::Labware)
    _location_header(io,x)
    println(io)
    printstyled(io,"Labware:";bold=true)
    print(io," shape ",shape(x))
    isnothing(vendor(x)) || print(io,", vendor ",vendor(x))
    isnothing(catalog(x)) || print(io,", catalog ",catalog(x))
    println(io)
    _children_summary(io,x)
    _attributes_summary(io,x)
    _reads_summary(io,x)
end

function Base.show(io::IO,::MIME"text/plain",x::Well)
    _location_header(io,x)
    println(io)
    cap = wellcapacity(x)
    printstyled(io,"Well:";bold=true)
    println(io," capacity ",isnothing(cap) ? "none" : cap,"   cost ",cost(x))
    println(io)
    show(io,MIME("text/plain"),stock(x))
    println(io)
    _attributes_summary(io,x)
    _reads_summary(io,x)
end

function Base.show(io::IO,::MIME"text/plain",x::Instrument)
    _location_header(io,x)
    println(io)
    printstyled(io,"Instrument capabilities:";bold=true)
    println(io)
    println(io,"  performable operations: ",join(sort(string.(nameof.(performable_operations(x)))),", "))
    println(io,"  actuatable attributes: ",join(sort(string.(collect(actuatable_attributes(x)))),", "))
    println(io,"  readable types: ",join(sort(string.(collect(readable_types(x)))),", "))
    _children_summary(io,x)
    _attributes_summary(io,x)
    _reads_summary(io,x)
end
