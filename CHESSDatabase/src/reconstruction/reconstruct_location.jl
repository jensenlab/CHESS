


"""
    ReconstructionReport

What a depth-limited [`reconstruct_location`](@ref) did: `depth_requested`, `depth_reached` (smaller than the
request only when a budget cut the work: `max_closure` or `children_limit`), `truncated` (the parts that were cut,
`:children`, `:contents` or `:reads`), `closure_rows` (the size of the transfer ancestry that `max_closure` was
compared with, `nothing` when it was not computed) and `notes`. Both depths are `:legacy` for a call without `depth`.
"""
struct ReconstructionReport
    depth_requested::Union{Int,Symbol}
    depth_reached::Union{Int,Symbol}
    truncated::Vector{Symbol}
    closure_rows::Union{Int,Nothing}
    notes::Vector{String}
end

function _check_depth(depth)
    depth === :legacy && return 5 # a limit keyword without a depth asks for the whole location, with the limit
    (depth isa Integer && 0 <= depth <= 5) || throw(ArgumentError("depth must be an integer from 0 to 5 or :legacy, got $(repr(depth))"))
    return Int(depth)
end

# Fills the fields of levels 0..depth (section 5 of the reconstruction plan). A level only adds fields; the value of
# a field does not depend on the depth.
function _reconstruct_to_depth!(loc::Location,sequence_id,time,max_cache,encumbrances,depth::Int,max_closure,children_limit,reads_limit)
    truncated = Symbol[]
    notes = String[]
    closure_rows = nothing
    reached = depth
    # level 0: the shell made by get_location_info holds the name and the kind
    if depth >= 1
        depth >= 2 || reconstruct_parent!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # the parent as an id-only shell
        reconstruct_activity!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
        reconstruct_lock!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
        reconstruct_lot!(loc,sequence_id,time)
    end
    if depth >= 2
        reconstruct_environment!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # the whole ancestor chain and the attributes
    end
    if depth >= 3
        reconstruct_children!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
        if !isnothing(children_limit) && loc isa GenericLocation && length(children(loc)) > children_limit
            loc.children = children(loc)[1:children_limit]
            push!(truncated,:children)
            reached = min(reached,2)
            push!(notes,"children cut to the first $children_limit; the cost of finding them is not reduced")
        end
        if loc isa CHESSCore.Well
            skip = false
            if !isnothing(max_closure)
                closure_rows = nrow(get_transfer_ancestors([location_id(loc)],0,sequence_id,time;encumbrances=encumbrances))
                skip = closure_rows > max_closure
            end
            if skip
                push!(truncated,:contents)
                reached = min(reached,2)
                push!(notes,"stock not reconstructed: the transfer ancestry has $closure_rows rows, more than max_closure=$max_closure")
            else
                reconstruct_contents!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
            end
        end
    end
    if depth >= 4
        push!(notes,"depth 4 (lineage) has no field on a Location; call trace_contents and trace_cost for it")
    end
    if depth >= 5
        if isnothing(reads_limit)
            reconstruct_reads!(loc,sequence_id,time,max_cache;encumbrances=encumbrances)
        elseif _reconstruct_newest_reads!(loc,reads_limit,sequence_id,time)
            push!(truncated,:reads)
            push!(notes,"only the newest $reads_limit reads were read")
        end
    end
    return ReconstructionReport(depth,reached,truncated,closure_rows,notes)
end

"""
    reconstruct_location!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false,depth=:legacy,report=false,max_closure=nothing,children_limit=nothing,reads_limit=nothing)

Reconstruct the entire state of a [`Location`](@ref) `location` in a CHESS Database. 

# Optional Arguments 
1) `sequence_id`: set the reconstruction to happen at a particular sequence point in the ledger. Default is the current maximum sequence ID in the Database. 
2) `time`: only consider operations that were recorded in the CHESS ledger before  `time`. `time` uses [Dates.jl](https://docs.julialang.org/en/v1/stdlib/Dates/) to standardize the time formatting. Default is Dates.now()
3) `max_cache`: only consider caches up to a certain sequence point and force the algorithm to simulate thereafter. Default is the current value of `sequence_id`. This feature is used for cache repair. 
# Keyword Arguments
1) `encumbrances`=false: Include encumbrances in the reconstruction. Encumbrances are future operations that are not in the ledger but have been planned.
2) `depth`=`:legacy`: how much of the location to reconstruct. `:legacy` is the whole location as before (environment, children, contents, lock, activity, reads, lot). An integer fills the fields of its level and every level below it, and never changes the value of a field it fills:

   | depth | fields filled |
   |---|---|
   | 0 | name and kind (identity) |
   | 1 | the parent as an id-only shell, `is_active`, `is_locked`, lot |
   | 2 | the whole ancestor chain and the attributes (`environment`) |
   | 3 | children and the stock of a well |
   | 4 | nothing more on the location: lineage (`trace_contents`, `trace_cost`) has no field to hold it |
   | 5 | reads |

   Depth 0 to 2 cost the lifetime of the location and its ancestors, not the length of the ledger. Barcodes are not a field of a `Location` and are not reconstructed at any depth.
3) `report`=false: return a [`ReconstructionReport`](@ref) (`reconstruct_location` returns `(location, report)`) instead of `nothing`/the location.
4) `max_closure`: skip the stock of a well whose transfer ancestry has more than this many rows (`truncated` lists `:contents`).
5) `children_limit`: keep only the first `children_limit` children of a `GenericLocation` (the cost of finding them is not reduced).
6) `reads_limit`: read only the newest `reads_limit` reads.
A limit keyword without `depth` means depth 5 with the limit.

Note: Combining these optional arguments allows users to traverse the state of any location at any time, past or present. Encumbrances are enforced as they would have been at the `sequence_id` and `time` of the reconstruction.

See Also: [`reconstruct_location`](@ref)
"""
function reconstruct_location!(loc::Location,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;
        encumbrances=false,depth::Union{Integer,Symbol}=:legacy,report::Bool=false,
        max_closure::Union{Integer,Nothing}=nothing,children_limit::Union{Integer,Nothing}=nothing,reads_limit::Union{Integer,Nothing}=nothing)
    if depth === :legacy && isnothing(max_closure) && isnothing(children_limit) && isnothing(reads_limit)
        reconstruct_environment!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs full parent chain and environmental attributes. We don't need to call reconstruct_parent  and reconstruct_attribute seperately if doing a full environment reconstruction
        reconstruct_children!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # finds the current children of the location but doesn't fully reconstruct them, just creates a reference. 
        reconstruct_contents!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the stock of wells
        reconstruct_lock!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the locked state (recall locks prevent movement)
        reconstruct_activity!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the activity state
        reconstruct_reads!(loc,sequence_id,time,max_cache;encumbrances=encumbrances) # reconstructs the reads recorded for the location
        reconstruct_lot!(loc,sequence_id,time) # reconstructs the lot a labware was received as
        rep = ReconstructionReport(:legacy,:legacy,Symbol[],nothing,String[])
    else
        rep = _reconstruct_to_depth!(loc,sequence_id,time,max_cache,encumbrances,_check_depth(depth),max_closure,children_limit,reads_limit)
    end
    return report ? rep : nothing
end

"""
    reconstruct_location(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;encumbrances=false,depth=:legacy,report=false,max_closure=nothing,children_limit=nothing,reads_limit=nothing)

Reconstruct the entire state of location in a CHESS Database using only an integer location_id

# Optional Arguments
1) `sequence_id`: set the reconstruction to happen at a particular sequence point in the ledger. Default is the current maximum sequence ID in the Database. 
2) `time`: only consider operations that were recorded in the CHESS ledger before  `time`. `time` uses [Dates.jl](https://docs.julialang.org/en/v1/stdlib/Dates/) to standardize the time formatting. Default is Dates.now()
3) `max_cache`: only consider caches up to a certain sequence point and force the algorithm to simulate thereafter. Default is the current value of `sequence_id`. This feature is used for cache repair. 
# Keyword Arguments
1) `encumbrances`=false: Include encumbrances in the reconstruction. Encumbrances are future operations that are not in the ledger but have been planned.
2) `depth`=`:legacy`: how much of the location to reconstruct. `:legacy` is the whole location as before (environment, children, contents, lock, activity, reads, lot). An integer fills the fields of its level and every level below it, and never changes the value of a field it fills:

   | depth | fields filled |
   |---|---|
   | 0 | name and kind (identity) |
   | 1 | the parent as an id-only shell, `is_active`, `is_locked`, lot |
   | 2 | the whole ancestor chain and the attributes (`environment`) |
   | 3 | children and the stock of a well |
   | 4 | nothing more on the location: lineage (`trace_contents`, `trace_cost`) has no field to hold it |
   | 5 | reads |

   Depth 0 to 2 cost the lifetime of the location and its ancestors, not the length of the ledger. Barcodes are not a field of a `Location` and are not reconstructed at any depth.
3) `report`=false: return a [`ReconstructionReport`](@ref) (`reconstruct_location` returns `(location, report)`) instead of `nothing`/the location.
4) `max_closure`: skip the stock of a well whose transfer ancestry has more than this many rows (`truncated` lists `:contents`).
5) `children_limit`: keep only the first `children_limit` children of a `GenericLocation` (the cost of finding them is not reduced).
6) `reads_limit`: read only the newest `reads_limit` reads.
A limit keyword without `depth` means depth 5 with the limit.

Note: Combining these optional arguments allows users to traverse the state of any location at any time, past or present. Encumbrances are enforced as they would have been at the sequence_id and time of the reconstruction.

**Previewing hypothetical changes**: `reconstruct_location` builds a *fresh, independent* object graph
from the ledger on every call — mutating the result (e.g. with `move_into!`, `drain!`, `lock!`, ...)
never touches any other object, live or otherwise, since nothing else shares its identity. This makes
it the way to preview a hypothetical change to a real, already-persisted location: reconstruct a
disposable copy, mutate it however you like, inspect it, then just let it go — there's nothing to
"restore" since the live object you started from was never touched. Call `reconstruct_location` again
for another independent snapshot. For hypothetical locations that don't exist yet, see
[`build_location`](@ref) instead.

See Also: [`reconstruct_location!`](@ref), [`build_location`](@ref)
"""
function reconstruct_location(location_id::Integer,sequence_id::Integer=get_last_sequence_id(),time::DateTime=Dates.now(),max_cache::Integer=sequence_id;
        encumbrances=false,depth::Union{Integer,Symbol}=:legacy,report::Bool=false,
        max_closure::Union{Integer,Nothing}=nothing,children_limit::Union{Integer,Nothing}=nothing,reads_limit::Union{Integer,Nothing}=nothing)

    n,t=get_location_info(location_id)

    loc=t(location_id,n)

    rep=reconstruct_location!(loc,sequence_id,time,max_cache;encumbrances=encumbrances,depth=depth,report=true,
        max_closure=max_closure,children_limit=children_limit,reads_limit=reads_limit)
    return report ? (loc,rep) : loc
end
