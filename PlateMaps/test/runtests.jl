using Test, PlateMaps, DataFrames, JSON, Random, Plots, HiGHS
import RunMaps
import CHESSCore

import PlateMaps: letter_code, wellnames, role_neighbors, node_roles, evenness, TYPEKEY,
    lower_bitmatrix, raise_bitmatrix, lower_occupant, raise_occupant, raise_platemap, raise_platemaps

@testset "PlateMap construction" begin
    wells = trues(2,2)
    occupant = Matrix{Union{Missing,Int}}(missing,2,2)
    @test PlateMap(wells,occupant) isa PlateMap{Int}
    @test PlateMap{Int}(wells) == PlateMap(wells,occupant)

    valid = reshape(Union{Missing,Int}[1,2,3,4],2,2)
    @test PlateMap(wells,valid) isa PlateMap{Int}

    w2 = falses(2,2); w2[1,1]=true
    occ_off = reshape(Union{Missing,Int}[1,missing,missing,missing],2,2)
    occ_off[1,1]=missing; occ_off[2,1]=1 # node at an inactive well
    @test_throws PlacementError PlateMap(w2,occ_off)

    dup = reshape(Union{Missing,Int}[1,1,missing,missing],2,2)
    @test_throws PlacementError PlateMap(wells,dup)

    @test_throws DimensionMismatch PlateMap(trues(2,2),Matrix{Union{Missing,Int}}(missing,3,3))

    @test size(PlateMap{Int}(wells)) == (2,2)
end

@testset "interface ergonomics" begin
    wells = trues(2,3)
    occ = reshape(Union{Missing,Symbol}[:a,:b,missing,:c,missing,missing],2,3)
    pm = PlateMap(wells,occ)

    @test pm[1,1] == :a
    @test pm[2,1] == :b
    @test ismissing(pm[1,2])
    @test pm[CartesianIndex(2,2)] == :c

    @test Set(nodes(pm)) == Set([:a,:b,:c])
    @test well_position(pm,:a) == CartesianIndex(1,1)
    @test well_position(pm,:c) == CartesianIndex(2,2)
    @test well_position(pm,:nonexistent) === nothing

    pairs = collect(pm)
    @test length(pairs) == 3
    @test Set(pairs) == Set([:a=>CartesianIndex(1,1),:b=>CartesianIndex(2,1),:c=>CartesianIndex(2,2)])
    @test length(pm) == 3
end

@testset "edges" begin
    e = mkedge(1,:c1,:positive)
    @test e.node1 == 1 && e.node2 == :c1 && e.role == :positive
    @test e.metadata == Dict{Symbol,Any}()

    e2 = mkedge(2,:c1,:negative;metadata=Dict(:note=>"x"))
    edges = [e,e2]
    @test edge_nodes(edges) == Set([1,:c1,2])
    @test roles(edges) == Set([:positive,:negative])

    # components: 1,2,:c1 are all connected through :c1
    @test components(edges) == [Set([1,2,:c1])]

    # two disjoint groups stay disjoint
    disjoint_edges = [mkedge(:a,:x,:positive),mkedge(:b,:y,:positive)]
    comps = components(disjoint_edges)
    @test length(comps) == 2
    @test Set([:a,:x]) in comps
    @test Set([:b,:y]) in comps

    @test components([]) == Set{Any}[]
end

@testset "objectives" begin
    wells = trues(2,2)
    @test margins(wells) == ([2,2],[2,2])
    @test manhattan_distance(CartesianIndex(1,1),CartesianIndex(2,2)) == 2

    pos = Dict(1=>CartesianIndex(1,1),:c=>CartesianIndex(2,2))
    e = mkedge(1,:c,:positive)
    @test role_neighbors([e])[1][:positive] == Set([:c])
    # both endpoints of the one edge contribute their own nearest-same-role-neighbor term (2 each)
    @test total_distance(pos,[e]) == 4
    @test total_distance(pos,[]) == 0.0

    # nearest-neighbor, not sum: node 1 has two :positive neighbors at different distances -- only the
    # closer one should count toward node 1's own term (this is the behavior the old edge-sum version got
    # wrong: it would have summed both distances instead of taking the minimum)
    pos2 = Dict(1=>CartesianIndex(1,1),:near=>CartesianIndex(1,2),:far=>CartesianIndex(1,4))
    edges2 = [mkedge(1,:near,:positive),mkedge(1,:far,:positive)]
    # node 1's term: min(dist(1,near)=1, dist(1,far)=3) = 1
    # :near's term: dist(near,1) = 1 (only same-role neighbor is node 1)
    # :far's term: dist(far,1) = 3 (only same-role neighbor is node 1)
    @test total_distance(pos2,edges2) == 1 + 1 + 3

    edges = [mkedge(1,:c,:positive),mkedge(2,:c,:positive)]
    nr = node_roles(edges)
    @test nr[1] == Set([:positive])
    @test nr[:c] == Set([:positive])

    pos3 = Dict(1=>CartesianIndex(1,1),2=>CartesianIndex(1,2),:c=>CartesianIndex(2,1))
    @test evenness(wells,pos3,:positive,edges) isa Real
    @test total_evenness(wells,pos3,edges) isa Real
    @test total_evenness(wells,pos3,[]) == 0.0

    @test PlateMaps.scale(5,0,10) == 0.5
    @test_throws ErrorException hybrid(wells,pos3,edges;lambda=1.5)
    @test hybrid(wells,pos3,edges) isa Real

    # run_compactness: a group of 3 runs sharing one control -- tight placement scores lower than spread
    group_edges = [mkedge(:r1,:c,:positive),mkedge(:r2,:c,:positive),mkedge(:r3,:c,:positive)]
    tight = Dict(:r1=>CartesianIndex(1,1),:r2=>CartesianIndex(1,2),:r3=>CartesianIndex(2,1),:c=>CartesianIndex(1,1))
    spread = Dict(:r1=>CartesianIndex(1,1),:r2=>CartesianIndex(4,4),:r3=>CartesianIndex(1,4),:c=>CartesianIndex(1,1))
    @test run_compactness(tight,group_edges,[:r1,:r2,:r3]) < run_compactness(spread,group_edges,[:r1,:r2,:r3])

    # a run with no same-component run partner contributes 0 regardless of position
    lone_edges = [mkedge(:r1,:c,:positive)]
    @test run_compactness(Dict(:r1=>CartesianIndex(1,1)),lone_edges,[:r1]) == 0.0
    @test run_compactness(Dict(:r1=>CartesianIndex(4,4)),lone_edges,[:r1]) == 0.0

    # no edges at all -- nothing to be compact relative to
    @test run_compactness(Dict(:r1=>CartesianIndex(1,1)),[],[:r1]) == 0.0
end

@testset "schedule" begin
    wells = trues(4,4)
    run_nodes = [Symbol("run$i") for i in 1:4]
    edges = [mkedge(Symbol("run$i"),:pos1,:positive) for i in 1:4]
    append!(edges,[mkedge(Symbol("run$i"),:neg1,:negative) for i in 1:4])

    pms = schedule_platemap(wells,edges,run_nodes;restarts=1,iterations=50)
    @test pms isa Vector{PlateMap}
    @test length(pms) == 1 # everything is one connected component -- fits on one plate
    pm = only(pms)
    @test Set(nodes(pm)) == edge_nodes(edges)
    @test length(pm) == length(edge_nodes(edges))
    # runs are placed first -- fixed nodes always land somewhere
    for n in run_nodes
        @test !ismissing(well_position(pm,n))
    end

    pm_dist = only(schedule_platemap(wells,edges,run_nodes;objective=:distance,restarts=1,iterations=50))
    @test pm_dist isa PlateMap
    pm_even = only(schedule_platemap(wells,edges,run_nodes;objective=:evenness,restarts=1,iterations=50))
    @test pm_even isa PlateMap

    @test_throws ArgumentError schedule_platemap(wells,edges,run_nodes;solver="bogus")
    @test_throws ArgumentError schedule_platemap(wells,edges,run_nodes;plate_solver="bogus")
    @test_throws ArgumentError schedule_platemap(wells,edges,run_nodes;objective=:bogus)
    @test_throws ArgumentError schedule_platemap(trues(1,1),edges,run_nodes) # more nodes than wells

    # reproducibility
    a = schedule_platemap(wells,edges,run_nodes;restarts=1,iterations=50,rng=Xoshiro(1))
    b = schedule_platemap(wells,edges,run_nodes;restarts=1,iterations=50,rng=Xoshiro(1))
    @test a == b

    # run_restarts/run_iterations are accepted and forwarded to place_runs
    pm_runeffort = only(schedule_platemap(wells,edges,run_nodes;run_restarts=2,run_iterations=20,restarts=1,iterations=50))
    @test pm_runeffort isa PlateMap

    # empty edges -- nothing to place, but still one (empty) plate, not zero
    pms_empty = schedule_platemap(wells,[],Symbol[])
    @test length(pms_empty) == 1
    @test length(only(pms_empty)) == 0
end

@testset "place_runs" begin
    wells = trues(6,6)
    run_nodes = [Symbol("run$i") for i in 1:4]
    edges = [mkedge(Symbol("run$i"),:pos1,:positive) for i in 1:4]

    pos = place_runs(wells,run_nodes,edges;restarts=5,iterations=200,rng=Xoshiro(1))
    @test Set(keys(pos)) == Set(run_nodes)
    @test length(Set(values(pos))) == length(run_nodes) # no collisions

    # clustering should do meaningfully better than a naive shuffle-only placement
    naive_wells = findall(wells)
    naive_pos = Dict(n=>w for (n,w) in zip(run_nodes,shuffle(Xoshiro(2),naive_wells)[1:length(run_nodes)]))
    @test run_compactness(pos,edges,run_nodes) <= run_compactness(naive_pos,edges,run_nodes)

    # two disjoint groups each cluster independently
    two_groups_nodes = [Symbol("a$i") for i in 1:3]
    append!(two_groups_nodes,[Symbol("b$i") for i in 1:3])
    two_groups_edges = [mkedge(Symbol("a$i"),:ca,:positive) for i in 1:3]
    append!(two_groups_edges,[mkedge(Symbol("b$i"),:cb,:positive) for i in 1:3])
    pos2 = place_runs(wells,two_groups_nodes,two_groups_edges;restarts=5,iterations=200,rng=Xoshiro(1))
    @test Set(keys(pos2)) == Set(two_groups_nodes)

    # edgeless run set -- no error, every run still gets a well
    pos3 = place_runs(wells,run_nodes,[];restarts=1,iterations=10)
    @test Set(keys(pos3)) == Set(run_nodes)

    # empty run set
    @test place_runs(wells,Symbol[],[]) == Dict{Any,CartesianIndex{2}}()

    # too many runs for the plate
    @test_throws ArgumentError place_runs(trues(1,1),run_nodes,edges)

    # reproducibility
    posa = place_runs(wells,run_nodes,edges;restarts=1,iterations=50,rng=Xoshiro(7))
    posb = place_runs(wells,run_nodes,edges;restarts=1,iterations=50,rng=Xoshiro(7))
    @test posa == posb
end

@testset "schedule MILP" begin
    wells = trues(4,4)
    run_nodes = [Symbol("run$i") for i in 1:4]
    edges = [mkedge(Symbol("run$i"),:pos1,:positive) for i in 1:4]
    append!(edges,[mkedge(Symbol("run$i"),:neg1,:negative) for i in 1:4])

    pm = only(schedule_platemap(wells,edges,run_nodes;solver="MILP",optimizer=HiGHS.Optimizer))
    @test pm isa PlateMap
    @test Set(nodes(pm)) == edge_nodes(edges)

    # MILP only supports the :distance objective
    @test_throws ArgumentError schedule_platemap(wells,edges,run_nodes;solver="MILP",objective=:evenness,optimizer=HiGHS.Optimizer)

    # MILP requires a bipartite edge set: every control's same-role neighbors must all be fixed
    bad_edges = [mkedge(:pos1,:pos2,:positive)]
    @test_throws ArgumentError schedule_platemap(wells,bad_edges,Symbol[];solver="MILP",optimizer=HiGHS.Optimizer)

    # exact solver should match (or beat) the heuristic on this tiny instance
    pm_exchange = only(schedule_platemap(wells,edges,run_nodes;solver="exchange",restarts=5,iterations=500,rng=Xoshiro(1)))
    @test total_distance(Dict(n=>well_position(pm,n) for n in nodes(pm)),edges) <=
          total_distance(Dict(n=>well_position(pm_exchange,n) for n in nodes(pm_exchange)),edges)
end

@testset "multi-plate" begin
    # two disjoint groups of 3 nodes each, forced onto separate plates by a small capacity
    group_a = [Symbol("a$i") for i in 1:3]
    group_b = [Symbol("b$i") for i in 1:3]
    edges = [mkedge(:a1,:a2,:positive),mkedge(:a2,:a3,:positive),mkedge(:b1,:b2,:positive),mkedge(:b2,:b3,:positive)]
    fixed_nodes = Symbol[] # nothing fixed; every node is placed by the control stage

    wells = trues(2,2) # capacity 4 -- two groups of 3 can't share one plate (3+3 > 4)
    pms = schedule_platemap(wells,edges,fixed_nodes;restarts=2,iterations=100,rng=Xoshiro(1))
    @test pms isa Vector{PlateMap}
    @test length(pms) == 2
    node_sets = [Set(nodes(pm)) for pm in pms]
    @test Set(group_a) in node_sets
    @test Set(group_b) in node_sets
    # every node placed exactly once across the whole batch
    all_nodes = vcat((collect(nodes(pm)) for pm in pms)...)
    @test length(all_nodes) == length(unique(all_nodes)) == 6

    # plate_solver="MILP" should use no more plates than greedy on the same instance
    pms_milp = schedule_platemap(wells,edges,fixed_nodes;plate_solver="MILP",optimizer=HiGHS.Optimizer,restarts=1,iterations=50)
    @test length(pms_milp) <= length(pms)

    # a large plate fits both groups on one plate instead
    big_wells = trues(4,4)
    pms_one = schedule_platemap(big_wells,edges,fixed_nodes;restarts=1,iterations=50)
    @test length(pms_one) == 1
    @test Set(nodes(only(pms_one))) == Set(vcat(group_a,group_b))

    # infeasibility: a single component larger than one plate's capacity
    too_big_edges = [mkedge(:c1,:c2,:positive),mkedge(:c2,:c3,:positive),mkedge(:c3,:c4,:positive),mkedge(:c4,:c5,:positive)]
    @test_throws ArgumentError schedule_platemap(wells,too_big_edges,Symbol[]) # 5-node component, capacity 4

    # a fixed node with no edges at all still forms its own atomic (singleton) group
    lone_fixed = [:lone]
    pms_lone = schedule_platemap(wells,edges,vcat(fixed_nodes,lone_fixed);restarts=1,iterations=50)
    @test any(:lone in nodes(pm) for pm in pms_lone)

    # unknown plate_solver
    @test_throws ArgumentError schedule_platemap(wells,edges,fixed_nodes;plate_solver="bogus")
end

@testset "RunMaps extension" begin
    rm = RunMaps.RunMap{Symbol}()
    run_nodes = Symbol[]
    for g in 1:2
        for i in 1:3
            r = Symbol("r$(g)_$i")
            push!(run_nodes,r)
            RunMaps.link!(rm,r,Symbol("pos$g"),:positive)
            RunMaps.link!(rm,r,Symbol("neg$g"),:negative)
        end
    end

    wells = trues(4,6)
    pms = schedule_platemap(wells,rm,(:positive,:negative);restarts=3,iterations=200,rng=Xoshiro(1))
    @test pms isa Vector{PlateMap}
    @test length(pms) == 1 # both groups fit comfortably on one 24-well plate
    pm = only(pms)
    @test length(nodes(pm)) == length(RunMaps.runs(rm))

    # the run nodes themselves never serve :positive/:negative (they're always the edge subject, never
    # the linked/target node), so they're the ones fixed first by place_runs
    for n in run_nodes
        @test !ismissing(well_position(pm,n))
    end
    # the control nodes (:pos1,:neg1,:pos2,:neg2) are the ones actually optimized
    @test Set(RunMaps.roles(rm,:pos1)) == Set([:positive])

    # placeable_roles accepts a bare Symbol too
    pm_single = only(schedule_platemap(wells,rm,:positive;restarts=1,iterations=20))
    @test pm_single isa PlateMap

    # describe: a registered node reports its outgoing/incoming roles and neighbors
    d = PlateMaps.describe(pm,rm,:r1_1)
    @test d.registered
    @test :positive in d.outgoing_roles
    @test :pos1 in d.linked_runs
    d_control = PlateMaps.describe(pm,rm,:pos1)
    @test d_control.registered
    @test :positive in d_control.incoming_roles
    @test :r1_1 in d_control.linking_runs
    # unregistered node
    d_unreg = PlateMaps.describe(pm,rm,:nonexistent)
    @test d_unreg.registered == false

    # DataFrame
    df = DataFrame(pm,rm)
    @test all(in(names(df)),["registered","outgoing_roles","incoming_roles"])

    # plot smoke test
    @test plot(pm,rm) isa Plots.Plot

    # chaining schedule_duplicates/schedule_controls! into schedule_platemap
    dup_map = RunMaps.schedule_duplicates([:A,:B],1)
    active = RunMaps.runs(dup_map)
    pools = Dict(:positive=>[:p1,:p2],:negative=>[:n1,:n2])
    RunMaps.schedule_controls!(dup_map,active,pools,Dict(:positive=>1,:negative=>1),4)
    wells2 = trues(4,4)
    pm2 = only(schedule_platemap(wells2,dup_map,(:positive,:negative);restarts=2,iterations=100))
    @test pm2 isa PlateMap
    @test length(nodes(pm2)) == length(RunMaps.runs(dup_map))
end

@testset "CHESSCore extension" begin
    kind = CHESSCore.LocationKind(:TestPlate;shape=(4,6))
    @test wells_from_locationkind(kind) == trues(4,6)

    shapeless = CHESSCore.LocationKind(:NotLabware)
    @test_throws ArgumentError wells_from_locationkind(shapeless)

    run_nodes = [Symbol("run$i") for i in 1:4]
    edges = [mkedge(Symbol("run$i"),:pos1,:positive) for i in 1:4]
    append!(edges,[mkedge(Symbol("run$i"),:neg1,:negative) for i in 1:4])

    pms = schedule_platemap(kind,edges,run_nodes;restarts=1,iterations=50)
    @test pms isa Vector{PlateMap}
    pm = only(pms)
    @test size(pm) == (4,6)
    @test Set(nodes(pm)) == edge_nodes(edges)

    @test_throws ArgumentError schedule_platemap(shapeless,edges,run_nodes)

    # composes with the RunMaps extension: schedule_platemap(kind, rm, placeable_roles) should
    # re-dispatch to PlateMapsRunMapsExt's (::BitMatrix, ::RunMap, placeable_roles) method internally
    rm = RunMaps.RunMap{Symbol}()
    for i in 1:4
        RunMaps.link!(rm,Symbol("run$i"),:pos1,:positive)
        RunMaps.link!(rm,Symbol("run$i"),:neg1,:negative)
    end
    pm_rm = only(schedule_platemap(kind,rm,(:positive,:negative);restarts=1,iterations=50))
    @test pm_rm isa PlateMap
    @test size(pm_rm) == (4,6)
    @test length(nodes(pm_rm)) == length(RunMaps.runs(rm))

    # multi-plate composition through both extensions at once: a RunMap with 2 disjoint groups on a
    # small kind should come back as 2 PlateMaps, exercising the "one interface generalizes" claim
    small_kind = CHESSCore.LocationKind(:SmallPlate;shape=(2,2))
    rm2 = RunMaps.RunMap{Symbol}()
    RunMaps.link!(rm2,:x1,:x2,:positive); RunMaps.link!(rm2,:x2,:x3,:positive)
    RunMaps.link!(rm2,:y1,:y2,:positive); RunMaps.link!(rm2,:y2,:y3,:positive)
    pms_multi = schedule_platemap(small_kind,rm2,:positive;restarts=1,iterations=50)
    @test length(pms_multi) == 2

    # joined multi-plate DataFrame: plate column plus the registered/outgoing_roles/incoming_roles
    # columns DataFrame(pm,rm) already produces, stacked across all plates actually used
    df_multi = DataFrame(pms_multi,rm2)
    @test all(in(names(df_multi)),["plate","registered","outgoing_roles","incoming_roles"])
    @test sort(unique(df_multi.plate)) == 1:length(pms_multi)
end

@testset "visualization" begin
    wells = trues(2,2)
    occ = reshape(Union{Missing,Int}[1,2,missing,missing],2,2)
    pm = PlateMap(wells,occ)
    @test plot(pm) isa Plots.Plot
end

@testset "DataFrame interface" begin
    wells = trues(2,2)
    occ = reshape(Union{Missing,Int}[1,2,missing,missing],2,2)
    pm = PlateMap(wells,occ)
    df = DataFrame(pm)
    @test names(df) == ["well","row","col","active","occupant"]
    @test df.well[1] == "A1"
    @test pm == PlateMap(df)

    df.extra .= "example"
    @test pm == PlateMap(df)

    @test_throws ErrorException PlateMap(DataFrame(a=[1,2],b=[3,4]))

    # multi-plate compile-to-one-file round trip
    occ2 = reshape(Union{Missing,Int}[3,4,missing,missing],2,2)
    pm2 = PlateMap(wells,occ2)
    pms = PlateMap[pm,pm2]
    df_multi = DataFrame(pms)
    @test "plate" in names(df_multi)
    @test sort(unique(df_multi.plate)) == [1,2]
    @test platemaps_from_dataframe(df_multi) == pms

    @test_throws ErrorException platemaps_from_dataframe(DataFrame(pm))
end

@testset "JSON interface" begin
    wells = trues(2,2)
    occ = reshape(Union{Missing,Int}[1,2,missing,missing],2,2)
    pm = PlateMap(wells,occ)
    @test json_to_platemap(platemap_to_json(pm)) == pm

    occ_sym = reshape(Union{Missing,Symbol}[:a,:b,missing,missing],2,2)
    pm_sym = PlateMap(wells,occ_sym)
    @test json_to_platemap(platemap_to_json(pm_sym)) == pm_sym

    m = trues(2,2)
    @test raise_bitmatrix(JSON.parse(JSON.json(lower_bitmatrix(m)))) == m

    bad = JSON.parse(JSON.json(Dict(TYPEKEY=>"NotABitMatrix")))
    @test_throws ErrorException raise_bitmatrix(bad)

    bad_pm = JSON.parse(JSON.json(Dict(TYPEKEY=>"NotAPlateMap")))
    @test_throws ErrorException raise_platemap(bad_pm)

    unknown_type = JSON.parse(JSON.json(Dict(TYPEKEY=>"Occupant","size"=>[2,2],"node_type"=>"MadeUpType","data"=>[nothing,nothing,nothing,nothing])))
    @test_throws ErrorException raise_occupant(unknown_type)

    # multi-plate compile-to-one-file round trip
    occ2 = reshape(Union{Missing,Int}[3,4,missing,missing],2,2)
    pm2 = PlateMap(wells,occ2)
    pms = PlateMap[pm,pm2]
    @test json_to_platemaps(platemaps_to_json(pms)) == pms

    bad_batch = JSON.parse(JSON.json(Dict(TYPEKEY=>"NotABatch")))
    @test_throws ErrorException raise_platemaps(bad_batch)
end
