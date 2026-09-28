"""
    commit_location!(loc::Location) -> Location

Commit an uncommitted (`!is_committed(loc)`) location subtree to the database, preserving its
current structure, attributes, lock/active state, and (for Wells) stock contents.

Returns a **new**, independent, committed `Location` -- `loc` itself is left unchanged and still
uncommitted (`location_id`/`name`/`kind` are immutable fields on every concrete `Location` subtype,
so committing in place is not possible). Use the returned value going forward, the same way
[`reconstruct_location`](@ref) returns an independent object rather than mutating its input.

Already-committed locations embedded in an otherwise-uncommitted subtree are left as-is (reattached,
not re-committed) -- `commit_location!` is safe to call on a mixed tree.

Whatever the new locations hold beyond a fresh location's defaults (stock, cost, attributes, lock and
activity state, and which location each child sits in) is recorded as observations on a single new
ledger entry, so the ledger alone can reconstruct it. The new locations are then cached at that entry.

See also: [`build_location`](@ref), [`release_location`](@ref), [`UncommittedLocationError`](@ref),
[`observe`](@ref).
"""
function commit_location!(loc::Location)
    is_committed(loc) && return loc
    new_locs = Location[]
    real = _commit_tree!(loc,new_locs)
    facets = reduce(vcat,_genesis_facets.(new_locs);init=Tuple[])
    if !isempty(facets)
        ledger_id = append_ledger()
        for f in facets
            upload_observation(f...;ledger_id=ledger_id)
        end
    end
    cache.(new_locs)
    return real
end

# upload a Locations row for every uncommitted location in `loc`'s subtree, collecting the newly
# committed copies in `new_locs`
function _commit_tree!(loc::Well,new_locs::Vector{Location})
    is_committed(loc) && return loc
    real_id = upload_new_location(name(loc),kind(loc))
    real = Well(real_id,name(loc),kind(loc);stock=stock(loc),attributes=attributes(loc),
        cost=cost(loc),is_active=is_active(loc))
    push!(new_locs,real)
    return real
end

function _commit_tree!(loc::Labware,new_locs::Vector{Location})
    is_committed(loc) && return loc
    real_id = upload_new_location(name(loc),kind(loc))
    cs = _commit_tree!.(children(loc),Ref(new_locs))
    real = Labware(real_id,name(loc),kind(loc);children=cs,attributes=attributes(loc),
        is_locked=is_locked(loc),is_active=is_active(loc))
    for c in cs
        c.parent = real
    end
    push!(new_locs,real)
    return real
end

function _commit_tree!(loc::GenericLocation,new_locs::Vector{Location})
    is_committed(loc) && return loc
    real_id = upload_new_location(name(loc),kind(loc))
    cs = _commit_tree!.(children(loc),Ref(new_locs))
    real = GenericLocation(real_id,name(loc),kind(loc);children=cs,attributes=attributes(loc),
        is_locked=is_locked(loc),is_active=is_active(loc))
    for c in cs
        c.parent = real
    end
    push!(new_locs,real)
    return real
end


"""
    release_location(loc::Location) -> Location

Build an uncommitted copy of `loc`'s subtree -- same name/kind/structure/attributes/lock/active
state (and, for Wells, stock), but with `location_id === nothing` throughout. The inverse of
[`commit_location!`](@ref). Never touches the database -- operates purely on `loc`'s already-
materialized in-memory state (e.g. from [`reconstruct_location`](@ref)).

Typical use: merging structures from separate databases (only one `connect_SQLite` connection can be
live at a time) -- reconstruct the subtree(s) you want from the source database, `release_location`
each one to strip the source IDs, recombine freely (e.g. `build_location` a new root and `move_into!`
each released piece into it), reconnect to the target database, and `commit_location!` the merged
result.

See also: [`commit_location!`](@ref), [`reconstruct_location`](@ref), [`build_location`](@ref).
"""
function release_location(loc::Well)
    return Well(nothing,name(loc),kind(loc);stock=stock(loc),attributes=attributes(loc),
        cost=cost(loc),is_active=is_active(loc))
end

function release_location(loc::Labware)
    cs = release_location.(children(loc))
    eph = Labware(nothing,name(loc),kind(loc);children=cs,attributes=attributes(loc),
        is_locked=is_locked(loc),is_active=is_active(loc))
    for c in cs
        c.parent = eph
    end
    return eph
end

function release_location(loc::GenericLocation)
    cs = release_location.(children(loc))
    eph = GenericLocation(nothing,name(loc),kind(loc);children=cs,attributes=attributes(loc),
        is_locked=is_locked(loc),is_active=is_active(loc))
    for c in cs
        c.parent = eph
    end
    return eph
end
