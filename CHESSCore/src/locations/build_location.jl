"""
    _build_location(kind::LocationKind,name::String,next_id::Function,child_namer::Vararg{Function})

Recursively build a [`Location`](@ref)/[`Labware`](@ref)/[`Well`](@ref) object graph for `kind`,
obtaining each node's `location_id` from `next_id(name,kind)`. This is the shared, pure (no database
calls) graph-construction logic behind both `generate_location` (real, DB-backed, in
CHESSDatabase) and [`build_location`](@ref) (no `location_id`, in-memory only).
"""
function _build_location(kind::LocationKind,name::String,next_id::Function,child_namer::Vararg{Function})
    T=concretetype(kind)
    loc_id=next_id(name,kind)
    lw=T(loc_id,name,kind)
    if T == Labware
        sh=shape(lw)
        socket_kind=location_kinds[kind.socket]
        for col in 1:sh[2]
            for row in 1:sh[1]
                well=_build_location(socket_kind,child_namer[1](row,col),next_id,child_namer[2:end]...)
                well.parent=lw
                lw.children[row,col]=well
            end
        end
    end
    return lw
end


_next_ephemeral_id(nm,k) = nothing

"""
    build_location(kind::LocationKind,name::String=string(UUIDs.uuid4()),child_namer::Vararg{Function}=plate_namer)

Build a `kind` Location entirely in memory — no database calls are made, and `location_id` is
`nothing` (see [`is_committed`](@ref)). This is the default, ordinary way to get a `Location`: a
plain in-memory Julia object, nothing exceptional about it. Useful for reasoning about hypothetical
arrangements without minting real database rows, and it's the building block CHESSCore's own tests
and fixtures use throughout. A location built this way cannot be passed to `upload`/`cache`
(CHESSDatabase) until it's committed — see [`UncommittedLocationError`](@ref). To commit a subtree
to a database, see `commit_location!` (CHESSDatabase); to strip a committed location back down to
an uncommitted one (e.g. to merge subtrees from separate databases), see `release_location`
(CHESSDatabase).

**Previewing hypothetical arrangements**: since nothing here is ever committed unless you choose to,
this is already the preview mechanism for anything that doesn't exist yet — build it, mutate it
freely (`move_into!`, `drain!`, `lock!`, ...), inspect it, and simply never call `upload`/`cache` if
you decide not to keep it. There's no "restore" step, because nothing was ever committed. For
previewing a change to an already-committed location instead, see `reconstruct_location`
(CHESSDatabase).

See also: `generate_location`, `reconstruct_location`, `commit_location!`, `release_location` (all
CHESSDatabase).
"""
function build_location(kind::LocationKind,name::String=string(UUIDs.uuid4()),child_namer::Vararg{Function}=plate_namer)
    return _build_location(kind,name,_next_ephemeral_id,child_namer...)
end


"""
    plate_namer(row,col)

Return the microplate standard name for a row and col coordinate

Ex. plate_namer(1,1)  = "A1" , plate_namer(8,12) = "H12"
"""
function plate_namer(row,col)
    return alphabet_code(row) * string(col)
end


function alphabet_code(n)

    alphabet=collect('A':'Z')
    k=length(alphabet)
    return repeat(alphabet[mod(n-1,k)+1],cld(n,k))
end
