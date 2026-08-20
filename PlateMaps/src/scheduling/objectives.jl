"""
    margins(wells::BitMatrix) -> (rowsums, colsums)

Active-well counts per row and per column.
"""
function margins(wells::BitMatrix)
    R,C = size(wells)
    rowsums = [sum(wells[r,:]) for r in 1:R]
    colsums = [sum(wells[:,c]) for c in 1:C]
    return rowsums,colsums
end

"""
    manhattan_distance(p1::CartesianIndex,p2::CartesianIndex) -> Int

L1 distance between two well positions.
"""
manhattan_distance(p1::CartesianIndex,p2::CartesianIndex) = abs(p1[1]-p2[1]) + abs(p1[2]-p2[2])

"""
    role_neighbors(edges) -> Dict{Any,Dict{Symbol,Set{Any}}}

For every node, the set of other nodes it shares a same-role edge with, grouped by role -- the
adjacency structure [`total_distance`](@ref) needs to find each node's nearest same-role neighbor.
"""
function role_neighbors(edges)
    d = Dict{Any,Dict{Symbol,Set{Any}}}()
    for e in edges
        push!(get!(() -> Set{Any}(),get!(() -> Dict{Symbol,Set{Any}}(),d,e.node1),e.role),e.node2)
        push!(get!(() -> Set{Any}(),get!(() -> Dict{Symbol,Set{Any}}(),d,e.node2),e.role),e.node1)
    end
    return d
end

"""
    total_distance(pos, edges) -> Real

For every node, and every role it participates in, the *minimum* distance to any same-role neighbor,
summed over every `(node, role)` pair -- the core generalized "minimax"-style objective. This is *not* a
sum over every edge: a node linked to several same-role neighbors is only scored by its distance to the
closest one, matching `PlateArrays`' old `distance_score_brute` (which scored every active well's
distance to its nearest positive/negative control) generalized to however many roles are present, rather
than penalizing a node for being far from every same-role neighbor it has.
"""
function total_distance(pos,edges)
    isempty(edges) && return 0.0
    rn = role_neighbors(edges)
    total = 0.0
    for (n,by_role) in rn, (r,neighbors) in by_role
        total += minimum(manhattan_distance(pos[n],pos[m]) for m in neighbors)
    end
    return total
end

"""
    run_compactness(pos, edges, run_nodes) -> Real

For every edge-connected component (see [`components`](@ref)) with 2 or more `run_nodes` members, sum
each member's Manhattan distance to the component's centroid (mean row, mean col of its members' `pos`).
Components with fewer than 2 run-node members (a run with no edges, or whose whole component has no other
run) contribute 0 -- there is nothing to be compact relative to. Used by [`place_runs`](@ref) to cluster
edge-linked runs together before control placement, so a run's specific control isn't left stranded far
from it.
"""
function run_compactness(pos,edges,run_nodes)
    total = 0.0
    run_set = Set(run_nodes)
    for comp in components(edges)
        members = collect(intersect(comp,run_set))
        length(members) < 2 && continue
        rowc = sum(pos[m][1] for m in members) / length(members)
        colc = sum(pos[m][2] for m in members) / length(members)
        for m in members
            total += abs(pos[m][1] - rowc) + abs(pos[m][2] - colc)
        end
    end
    return total
end

"""
    node_roles(edges) -> Dict{Any,Set{Symbol}}

The set of roles each node participates in, derived from `edges` (a node's roles are the union of
`.role` over every edge touching it, from either side -- `PlateMaps` doesn't track a run/control-style
asymmetry between an edge's two endpoints).
"""
function node_roles(edges)
    d = Dict{Any,Set{Symbol}}()
    for e in edges
        push!(get!(() -> Set{Symbol}(),d,e.node1),e.role)
        push!(get!(() -> Set{Symbol}(),d,e.node2),e.role)
    end
    return d
end

"""
    expected_margins(wells::BitMatrix,count::Integer) -> (rowexp,colexp)

Expected per-row/per-column count if `count` items were spread uniformly across `wells`' active cells.
"""
function expected_margins(wells::BitMatrix,count::Integer)
    rowsums,colsums = margins(wells)
    total = sum(rowsums)
    total == 0 && return (zeros(length(rowsums)),zeros(length(colsums)))
    return count .* rowsums ./ total, count .* colsums ./ total
end

"""
    evenness(wells::BitMatrix,pos,role::Symbol,edges) -> Real

Sum of squared deviations between one role's actual per-row/per-column well counts and the count
expected if that role's nodes were spread uniformly across the plate's active wells -- generalizes
`PlateArrays`' old `LHS` metric from two hardcoded roles to whichever roles are actually present.
"""
function evenness(wells::BitMatrix,pos,role::Symbol,edges)
    roles_of = node_roles(edges)
    role_nodes = [n for (n,rs) in roles_of if role in rs]
    R,C = size(wells)
    rowsums = zeros(R); colsums = zeros(C)
    for n in role_nodes
        p = pos[n]
        rowsums[p[1]] += 1
        colsums[p[2]] += 1
    end
    rowexp,colexp = expected_margins(wells,length(role_nodes))
    return sum((rowsums .- rowexp).^2) + sum((colsums .- colexp).^2)
end

"""
    total_evenness(wells::BitMatrix,pos,edges) -> Real

[`evenness`](@ref) summed over every distinct role present in `edges`.
"""
function total_evenness(wells::BitMatrix,pos,edges)
    rs = roles(edges)
    isempty(rs) && return 0.0
    return sum(evenness(wells,pos,r,edges) for r in rs)
end

"""
    scale(x,lb,ub) -> Real

Normalize `x` into `[0,1]` given known bounds `lb`/`ub` (matches `PlateArrays`' identically-named helper).
"""
scale(x::Real,lb::Real,ub::Real) = ub == lb ? 0.0 : (x - lb) / (ub - lb)

"""
    hybrid(wells,pos,edges;lambda=0.5,lb_dist=0,ub_dist=1,lb_even=0,ub_even=1) -> Real

Weighted combination of the (normalized) distance and evenness objectives -- generalizes `PlateArrays`'
`hybrid`, now over however many roles/edges are actually present rather than two hardcoded ones.
"""
function hybrid(wells::BitMatrix,pos,edges;lambda=0.5,lb_dist=0,ub_dist=1,lb_even=0,ub_even=1)
    0 <= lambda <= 1 || error("lambda must be between 0 and 1 inclusive.")
    s1 = scale(total_distance(pos,edges),lb_dist,ub_dist)
    s2 = scale(total_evenness(wells,pos,edges),lb_even,ub_even)
    return lambda*s1 + (1-lambda)*s2
end
