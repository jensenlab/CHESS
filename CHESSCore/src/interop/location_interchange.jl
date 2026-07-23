
# A general Location <-> Dict interchange for tools outside CHESS: plain, JSON-safe Julia values
# (Dict{String,Any}/Vector/String/Real/Nothing -- no JSON library dependency needed here, producing
# actual JSON text from a plain Dict tree is a one-line job for whatever the caller already uses).
# Complements, rather than replaces, the tabular "vc"/"q" DataFrame interface (dataframe_interface.jl)
# -- that one is still the right tool for bulk, flat batches of stock definitions (e.g. a wet-lab CSV
# template); this one is for a whole Location (or tree of them) with full fidelity: attributes, reads,
# cost, lock/active state, and (for GenericLocation/Instrument) nested children. Always uncommitted
# (via build_location) -- location_id/parent are omitted, mirroring df_to_labware's design boundary;
# commit the result yourself (e.g. commit_location! in CHESSDatabase) if you want it tracked.

function _organism_to_string(o::Organism; org_context=CHESSCore, kwargs...)
    try
        return string(symbol(o; context=org_context))
    catch e
        e isa ArgumentError || rethrow()
    end
    return name(o)
end

function _string_to_organism(str::AbstractString; org_context=CHESSCore, kwargs...)
    try
        return orgparse(str; org_context=org_context)
    catch
    end
    # not registered -- fall back to splitting the "genus species strain" display name (mirrors
    # string_to_reagent's fallback for an unregistered chemical: best-effort, not lossless)
    parts = split(str)
    length(parts) == 3 || error("cannot parse organism \"$str\" -- not registered and not in \"genus species strain\" form")
    return Organism(parts[1], parts[2], parts[3])
end

"""
    stock_to_dict(s::Stock; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...) -> Dict{String,Any}

Convert `s` to a plain, JSON-safe `Dict` -- a quantity-based (exact, unambiguous) encoding, mirroring
the "q" `DataFrame` format ([`stock_to_q`](@ref)) rather than "vc"'s relative-concentration form.
Reusable standalone or nested inside a [`Well`](@ref)'s [`location_to_dict`](@ref) output.

See also: [`dict_to_stock`](@ref)
"""
function stock_to_dict(s::Stock; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...)
    sol = Dict{String,Any}()
    for (r, q) in solids(s)
        sol[reagent_to_string(r; reagent_context, kwargs...)] = Dict("amount" => ustrip(q), "unit" => unit_to_string(unit(q)))
    end
    liq = Dict{String,Any}()
    for (r, q) in liquids(s)
        liq[reagent_to_string(r; reagent_context, kwargs...)] = Dict("amount" => ustrip(q), "unit" => unit_to_string(unit(q)))
    end
    org = [_organism_to_string(o; org_context) for o in organisms(s)]
    return Dict{String,Any}("solids" => sol, "liquids" => liq, "organisms" => org)
end

"""
    dict_to_stock(d::Dict; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...) -> Stock

Inverse of [`stock_to_dict`](@ref).
"""
function dict_to_stock(d::Dict; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...)
    sol = SolidDict()
    for (n, amt) in d["solids"]
        sol[string_to_reagent(n, Solid; reagent_context, kwargs...)] = amt["amount"] * string_to_unit(amt["unit"])
    end
    liq = LiquidDict()
    for (n, amt) in d["liquids"]
        liq[string_to_reagent(n, Liquid; reagent_context, kwargs...)] = amt["amount"] * string_to_unit(amt["unit"])
    end
    org = Set{Organism}(_string_to_organism(s; org_context) for s in d["organisms"])
    return Stock(org, sol, liq)
end

"""
    attribute_to_dict(a::Attribute) -> Dict{String,Any}

`"state"` is `"value"`/`"missing"`/`"unknown"` (mirrors [`isunknown`](@ref)/`ismissing`), with
`"value"` holding the actual number only when `"state" == "value"` -- kept as a separate field
(rather than a sentinel string in `"value"` itself) so a real value can never collide with the
sentinels.

See also: [`dict_to_attribute`](@ref)
"""
function attribute_to_dict(a::Attribute)
    v = value(a)
    state = isunknown(v) ? "unknown" : ismissing(v) ? "missing" : "value"
    return Dict{String,Any}(
        "kind" => string(attribute_kind(a).name),
        "state" => state,
        "value" => state == "value" ? ustrip(quantity(a)) : nothing,
        "unit" => unit_to_string(attribute_unit(a)),
    )
end

"""
    dict_to_attribute(d::Dict) -> Attribute

Inverse of [`attribute_to_dict`](@ref).
"""
function dict_to_attribute(d::Dict)
    k = attribute_kinds[Symbol(d["kind"])]
    val = d["state"] == "unknown" ? Unknown :
          d["state"] == "missing" ? missing :
          d["value"] * string_to_unit(d["unit"])
    return k(val)
end

"""
    read_to_dict(r::Read) -> Dict{String,Any}

Mirrors [`attribute_to_dict`](@ref)'s `"state"`/`"value"` split; `"unit"` is `nothing` for a
qualitative [`ReadKind`](@ref), and `"time"` is an ISO-8601 string (or `nothing`).

See also: [`dict_to_read`](@ref)
"""
function read_to_dict(r::Read)
    v = value(r)
    rk = read_kind(r)
    state = isunknown(v) ? "unknown" : ismissing(v) ? "missing" : "value"
    valout = state != "value" ? nothing : is_qualitative(rk) ? v : ustrip(quantity(r))
    return Dict{String,Any}(
        "kind" => string(rk.name),
        "state" => state,
        "value" => valout,
        "unit" => is_quantitative(rk) ? unit_to_string(read_unit(r)) : nothing,
        "time" => isnothing(read_time(r)) ? nothing : string(read_time(r)),
    )
end

"""
    dict_to_read(d::Dict) -> Read

Inverse of [`read_to_dict`](@ref).
"""
function dict_to_read(d::Dict)
    rk = read_kinds[Symbol(d["kind"])]
    val = d["state"] == "unknown" ? Unknown :
          d["state"] == "missing" ? missing :
          is_quantitative(rk) ? d["value"] * string_to_unit(d["unit"]) : d["value"]
    t = isnothing(d["time"]) ? nothing : DateTime(d["time"])
    return Read(rk, val, t)
end

"""
    location_to_dict(x::Location) -> Dict{String,Any}

Convert `x` (and, recursively, its subtree) to a plain, JSON-safe `Dict`. Common to every subtype:
`"kind"` (registered [`LocationKind`](@ref) name), `"name"`, `"is_locked"`, `"is_active"`,
`"attributes"` (own [`attributes`](@ref) only, not the derived/inherited [`environment`](@ref) --
keyed by attribute name, each an [`attribute_to_dict`](@ref) result), and `"reads"` (a `Vector` of
[`read_to_dict`](@ref) results). `location_id`/parent are omitted -- see the module-level comment.

Per-subtype: `GenericLocation`/`Instrument` add `"children"` (nested `location_to_dict` results,
recursive); `Instrument` also adds informational (non-authoritative -- see [`dict_to_location`](@ref))
`"actuatable_attributes"`/`"performable_operations"`/`"readable_types"`. `Well` adds `"cost"` and
`"stock"` ([`stock_to_dict`](@ref)). `Labware` adds `"wells"` -- a `shape[1]`-row, `shape[2]`-column
nested array of per-slot `Well` dicts, in the same `(row,col)` order as `children(x)` -- plus
informational `"vendor"`/`"catalog"`. This is the one non-flat exception: a `Labware` and its wells
round-trip as a single unit, matching how a human actually thinks about a plate when planning an
experiment.

Accepts `reagent_context`/`org_context` keywords (forwarded to [`stock_to_dict`](@ref) for any `Well`,
nested arbitrarily deep) so a `Well`'s contents resolve to their registered reagent/organism names
rather than falling back to ad hoc display names -- pass whatever context you'd pass to `rgt"..."`/
`org"..."` lookups (e.g. `reagent_context=[CHESSCore,MyLabModule]`) if reagents/organisms are
registered outside plain `CHESSCore`.

See also: [`dict_to_location`](@ref)
"""
function location_to_dict(x::Location; kwargs...)
    d = Dict{String,Any}(
        "kind" => string(kind(x).name),
        "name" => name(x),
        "is_locked" => is_locked(x),
        "is_active" => is_active(x),
        "attributes" => Dict{String,Any}(string(k) => attribute_to_dict(v) for (k, v) in attributes(x)),
        "reads" => [read_to_dict(r) for r in reads(x)],
    )
    _location_to_dict!(d, x; kwargs...)
    return d
end

function _location_to_dict!(d::Dict, x::GenericLocation; kwargs...)
    d["children"] = [location_to_dict(c; kwargs...) for c in children(x)]
    return nothing
end

function _location_to_dict!(d::Dict, x::Instrument; kwargs...)
    d["children"] = [location_to_dict(c; kwargs...) for c in children(x)]
    d["actuatable_attributes"] = sort(string.(collect(actuatable_attributes(x))))
    d["performable_operations"] = sort(string.(nameof.(performable_operations(x))))
    d["readable_types"] = sort(string.(collect(readable_types(x))))
    return nothing
end

function _location_to_dict!(d::Dict, x::Well; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...)
    d["cost"] = cost(x)
    d["stock"] = stock_to_dict(stock(x); reagent_context, org_context)
    return nothing
end

function _location_to_dict!(d::Dict, x::Labware; kwargs...)
    sh = shape(x)
    ch = children(x)
    d["wells"] = [[location_to_dict(ch[row, col]; kwargs...) for col in 1:sh[2]] for row in 1:sh[1]]
    d["vendor"] = vendor(x)
    d["catalog"] = catalog(x)
    return nothing
end

function _apply_common!(loc::Location, d::Dict)
    for (_, ad) in d["attributes"]
        set_attribute!(loc, dict_to_attribute(ad))
    end
    for rd in d["reads"]
        record_read!(loc, dict_to_read(rd))
    end
    d["is_active"] ? activate!(loc) : deactivate!(loc)
    return nothing
end

# Builds the full tree via move_into!, but deliberately never touches is_locked here -- move_into!
# throws LockedLocationError for an already-locked child, so a child must be fully attached to its
# parent before its own lock state (from its own dict) is applied. See _apply_locks! below, which
# runs once, after the whole tree is built, in a separate pass.
function _build_location_tree(d::Dict; kwargs...)
    k = location_kinds[Symbol(d["kind"])]
    return _build(concretetype(k), k, d; kwargs...)
end

function _build(::Type{T}, k::LocationKind, d::Dict; kwargs...) where {T<:Union{GenericLocation,Instrument}}
    loc = build_location(k, d["name"])
    _apply_common!(loc, d)
    for cd in d["children"]
        move_into!(loc, _build_location_tree(cd; kwargs...))
    end
    return loc
end

function _build(::Type{Well}, k::LocationKind, d::Dict; kwargs...)
    w = Well(nothing, d["name"], k; stock=dict_to_stock(d["stock"]; kwargs...), cost=d["cost"])
    _apply_common!(w, d)
    return w
end

function _build(::Type{Labware}, k::LocationKind, d::Dict; kwargs...)
    sh = k.shape
    wells_data = d["wells"]
    ch = Matrix{Location}(undef, sh...)
    for row in 1:sh[1], col in 1:sh[2]
        ch[row, col] = _build_location_tree(wells_data[row][col]; kwargs...)
    end
    lw = Labware(nothing, d["name"], k; children=ch)
    _apply_common!(lw, d)
    return lw
end

# Second pass, run once the whole tree is fully attached (see _build_location_tree above) -- safe to
# apply in any order, since setting is_locked on an already-attached node has no effect on its
# children or on movement. Skips Well: is_locked(::Well) is unconditionally true (Well.jl) and its
# lock!/unlock! are no-ops, so there's nothing to apply.
function _apply_locks!(loc::Location, d::Dict)
    loc isa Well || (d["is_locked"] ? lock!(loc) : unlock!(loc))
    if haskey(d, "children")
        for (c, cd) in zip(children(loc), d["children"])
            _apply_locks!(c, cd)
        end
    elseif haskey(d, "wells")
        sh = shape(loc)
        ch = children(loc)
        wells_data = d["wells"]
        for row in 1:sh[1], col in 1:sh[2]
            _apply_locks!(ch[row, col], wells_data[row][col])
        end
    end
    return nothing
end

"""
    dict_to_location(d::Dict; reagent_context=CHESSCore, org_context=CHESSCore, kwargs...) -> Location

Inverse of [`location_to_dict`](@ref). Reconstructs an uncommitted `Location` (`location_id ===
nothing`, via [`build_location`](@ref)) and, recursively, its subtree. The `"kind"` name is resolved against the
live [`location_kinds`](@ref) registry -- for `Instrument`, this means `"actuatable_attributes"`/
`"performable_operations"`/`"readable_types"` in `d` are informational only and never consulted; the
reconstructed `Instrument`'s real capabilities always come from its resolved `LocationKind`, exactly
like `"vendor"`/`"catalog"` for a `Labware`.
"""
function dict_to_location(d::Dict; kwargs...)
    loc = _build_location_tree(d; kwargs...)
    _apply_locks!(loc, d)
    return loc
end
