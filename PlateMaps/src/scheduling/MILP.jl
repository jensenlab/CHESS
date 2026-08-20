function _neighbors4(row::Int,col::Int,R::Int,C::Int)
    return [(max(row-1,1),col),(min(row+1,R),col),(row,min(col+1,C)),(row,max(col-1,1))]
end

"""
    _neighboring_disk(row,col,ring,R,C) -> Vector{Tuple{Int,Int}}

Every grid cell reachable within `ring` 4-connected hops of `(row,col)` (a cumulative disk, not a shell)
-- ported from `PlateArrays`' old `neighboring_ring` (the ring-trick's building block).
"""
function _neighboring_disk(row::Int,col::Int,ring::Int,R::Int,C::Int)
    cells = [(row,col)]
    sol = copy(cells)
    for _ in 1:ring
        cells = unique(reduce(vcat,[_neighbors4(r,c,R,C) for (r,c) in cells]))
        append!(sol,cells)
    end
    return unique(sol)
end

"""
    _milp_solve(wells, edges, fixed_pos; objective=:distance, optimizer=_default_optimizer[], timelimit=100,
                rng=Random.default_rng()) -> Dict{Any,CartesianIndex{2}}

Exact solver for control placement relative to already-fixed run positions, generalizing `PlateArrays`'
old ring-trick MILP from two hardcoded roles to however many are present. This is the two-stage design
that reopens MILP tractability after an earlier, fully-joint formulation was found intractable (see the
design notes): with run positions fixed *before* the solve, a run's own nearest-same-role-control term is
exactly the old ring-trick (a fixed query point, an unknown-position target), and a control's own
nearest-same-role-run term is even simpler than before -- every run it could link to sits at a known,
fixed position, so "distance to the nearest one" is a constant, precomputable per candidate well, not a
ring at all.

**Requires a bipartite edge set**: every control's same-role neighbors must themselves be fixed nodes
(never another control) -- true whenever `edges` comes from a `ControlMap` (or anything shaped like one),
since its edges only ever connect a run to a control. Throws `ArgumentError` if this doesn't hold.

**Only `objective=:distance` is supported** -- `:evenness`/`:hybrid` aren't yet formulated for the exact
solver (they'd need the per-role row/column margin terms linearized too); use `solver="exchange"` for those.

Accepts and ignores extra `kwargs` (e.g. `run_restarts`/`run_iterations`, meant for [`place_runs`](@ref)),
since `schedule_platemap` forwards one shared keyword bag to both the plate solver and this control
solver.
"""
function _milp_solve(wells::BitMatrix,edges,fixed_pos::AbstractDict;objective::Symbol=:distance,
        optimizer=_default_optimizer[],timelimit=100,rng::AbstractRNG=Random.default_rng(),kwargs...)
    objective == :distance || throw(ArgumentError(
        "MILP only supports objective=:distance (evenness/hybrid aren't yet formulated for the exact solver -- use solver=\"exchange\")"))

    all_nodes = collect(edge_nodes(edges))
    fixed_nodes = collect(keys(fixed_pos))
    control_nodes = collect(setdiff(all_nodes,fixed_nodes))
    well_idxs = findall(wells)
    free_wells = collect(setdiff(well_idxs,values(fixed_pos)))
    length(control_nodes) <= length(free_wells) || throw(ArgumentError(
        "more control nodes ($(length(control_nodes))) than free active wells ($(length(free_wells)))"))

    rn = role_neighbors(edges)
    for n in control_nodes, (r,neighs) in get(rn,n,Dict{Symbol,Set{Any}}())
        all(m -> haskey(fixed_pos,m), neighs) || throw(ArgumentError(
            "MILP requires a bipartite edge set (every control's same-role neighbors must be fixed nodes) -- node $n has a same-role neighbor that isn't fixed"))
    end

    R,C = size(wells)
    n_control = length(control_nodes)
    n_well = length(free_wells)
    control_idx = Dict(n=>i for (i,n) in enumerate(control_nodes))
    well_idx = Dict(w=>i for (i,w) in enumerate(free_wells))

    model = Model(optimizer)
    set_time_limit_sec(model,Float64(timelimit))
    @variable(model,x[1:n_control,1:n_well],Bin)
    @constraint(model,[c=1:n_control],sum(x[c,w] for w in 1:n_well)==1) # each control placed exactly once
    @constraint(model,[w=1:n_well],sum(x[c,w] for c in 1:n_control)<=1) # each free well holds at most one control

    obj_terms = Any[]

    # control-side terms: nearest fixed same-role run is a constant per candidate well -- no ring needed
    for n in control_nodes
        ci = control_idx[n]
        for (r,neighs) in get(rn,n,Dict{Symbol,Set{Any}}())
            costs = [minimum(manhattan_distance(w,fixed_pos[m]) for m in neighs) for w in free_wells]
            push!(obj_terms,sum(costs[wi]*x[ci,wi] for wi in 1:n_well))
        end
    end

    # run-side terms: ring-trick, one per (fixed node, role) -- generalizes PlateArrays' dwx/dwy pattern
    M = max(R,C)
    for n in fixed_nodes
        p = fixed_pos[n]
        for (r,neighs) in get(rn,n,Dict{Symbol,Set{Any}}())
            control_ids = [control_idx[m] for m in neighs if haskey(control_idx,m)]
            isempty(control_ids) && continue
            dw = @variable(model,lower_bound=0,base_name="dw_$(n)_$(r)")
            for ring in 0:M
                disk_well_ids = Int[]
                for rc in _neighboring_disk(p[1],p[2],ring,R,C)
                    ci = CartesianIndex(rc)
                    haskey(well_idx,ci) && push!(disk_well_ids,well_idx[ci])
                end
                indicator_sum = isempty(disk_well_ids) ? 0 : sum(x[ci,wi] for ci in control_ids for wi in disk_well_ids)
                @constraint(model,dw >= ring+1-(ring+1)*indicator_sum)
            end
            push!(obj_terms,dw)
        end
    end

    @objective(model,Min,sum(obj_terms))
    optimize!(model)

    full_pos = copy(fixed_pos)
    for n in control_nodes
        ci = control_idx[n]
        for wi in 1:n_well
            round(JuMP.value(x[ci,wi])) == 1 && (full_pos[n] = free_wells[wi]; break)
        end
    end
    return full_pos
end
