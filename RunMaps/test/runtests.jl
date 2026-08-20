using Test, RunMaps, DataFrames, JSON, HiGHS

import RunMaps: assign_groups_greedy, assign_groups_MILP

RunMaps._default_optimizer[] = HiGHS.Optimizer

@testset "Construction" begin
    map = RunMap()
    @test n_runs(map) == 0
    @test n_edges(map) == 0

    typed = RunMap{Int}()
    @test typed isa RunMap{Int}
    @test n_edges(typed) == 0
end

@testset "add_run!" begin
    map = RunMap()
    add_run!(map, 1)
    @test has_run(map, 1)
    @test linked_runs(map, 1) == []

    add_run!(map, 1) # idempotent
    @test n_runs(map) == 1
end

@testset "link! basic round-trip" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)

    @test linked_runs(map, 1) == ["posA"]
    @test linking_runs(map, "posA") == [1]

    # implicit node creation
    @test has_run(map, 1)
    @test has_run(map, "posA")

    @test has_link(map, 1, "posA")
    @test has_link(map, 1, "posA"; type=:positive)
    @test !has_link(map, 1, "posA"; type=:negative)
end

@testset "multiple relation types per run" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "negA", :negative)
    link!(map, 1, "blankA", :blank)

    @test Set(linked_runs(map, 1)) == Set(["posA", "negA", "blankA"])
    @test linked_runs(map, 1; type=:positive) == ["posA"]
    @test Set(relation_types(map, 1)) == Set([:positive, :negative, :blank])

    # string/symbol relation_type equivalence
    map2 = RunMap()
    link!(map2, 1, "posA", "positive")
    @test linked_runs(map2, 1; type=:positive) == ["posA"]
end

@testset "roles(map) -- all relation types across the whole map" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 2, "negA", :negative)
    link!(map, 3, "dupA", :duplicate)

    @test Set(roles(map)) == Set([:positive, :negative, :duplicate])
    @test roles(RunMap()) == Symbol[]
end

@testset "multiple runs linking to the same node" begin
    map = RunMap()
    link!(map, 1, "blank", :blank)
    link!(map, 2, "blank", :blank)
    link!(map, 3, "blank", :blank)

    @test Set(linking_runs(map, "blank")) == Set([1, 2, 3])
    @test Set(roles(map, "blank")) == Set([:blank])
end

@testset "a run as another run's linked node (chain)" begin
    map = RunMap()
    link!(map, "A", "B", :control) # A's linked node is B
    link!(map, "B", "C", :control) # B (itself someone's linked node) has its own linked node, C

    @test Set(linked_runs(map, "A")) == Set(["B"])
    @test Set(linking_runs(map, "B")) == Set(["A"]) # B is linked-to by A
    @test Set(linked_runs(map, "B")) == Set(["C"])  # B also has its own linked node
    @test Set(linking_runs(map, "C")) == Set(["B"])

    @test n_runs(map) == 3       # one pool, three distinct nodes
    @test n_components(map) == 1 # A-B-C forms one connected chain
end

@testset "duplicate link! calls" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "posA", :positive)
    @test n_edges(map) == 1

    link!(map, 1, "posA", :positive; metadata=Dict(:a => 1))
    link!(map, 1, "posA", :positive; metadata=Dict(:b => 2))
    @test n_edges(map) == 1
    @test edge_metadata(map, 1, "posA", :positive) == Dict(:a => 1, :b => 2)
end

@testset "unlink!" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "posA", :negative)

    unlink!(map, 1, "posA", :positive)
    @test !has_link(map, 1, "posA"; type=:positive)
    @test has_link(map, 1, "posA"; type=:negative)

    unlink!(map, 1, "posA")
    @test !has_link(map, 1, "posA")
    @test has_run(map, 1) # orphan node survives
    @test has_run(map, "posA")

    # no-op on nonexistent edge
    unlink!(map, 999, "nope")
    @test n_edges(map) == 0
end

@testset "remove_run!" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "negA", :negative)
    link!(map, 2, "posA", :positive)

    remove_run!(map, 1)
    @test !has_run(map, 1)
    @test linked_runs(map, 1) == []
    @test linking_runs(map, "posA") == [2]
    @test linking_runs(map, "negA") == []

    remove_run!(map, "posA")
    @test !has_run(map, "posA")
    @test linked_runs(map, 2) == []

    # no-op on never-registered node
    remove_run!(map, 999)
end

@testset "remove_run! cascades both directions" begin
    map = RunMap()
    link!(map, "A", "B", :control) # B is the linked_run of A
    link!(map, "B", "C", :control) # B is also the run of an edge to C

    remove_run!(map, "B")
    @test !has_run(map, "B")
    @test linked_runs(map, "A") == [] # edge A->B gone
    @test linking_runs(map, "C") == [] # edge B->C gone
    @test has_run(map, "A") && has_run(map, "C") # A and C themselves survive
end

@testset "metadata" begin
    map = RunMap()
    @test edge_metadata(map, 1, "posA", :positive) === nothing

    link!(map, 1, "posA", :positive)
    @test edge_metadata(map, 1, "posA", :positive) == Dict{Symbol,Any}()

    link!(map, 2, "posB", :positive; metadata=Dict(:dilution => 10))
    @test edge_metadata(map, 2, "posB", :positive) == Dict(:dilution => 10)

    set_metadata!(map, 1, "posA", :positive, Dict(:note => "ok"))
    @test edge_metadata(map, 1, "posA", :positive) == Dict(:note => "ok")

    @test_throws ArgumentError set_metadata!(map, 999, "nope", :positive, Dict())
end

@testset "empty/missing lookups" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)

    @test linked_runs(map, 999) == []
    @test linking_runs(map, "nope") == []

    unlink!(map, 1, "posA")
    @test linked_runs(map, 1) == [] # orphaned but registered
end

@testset "edges/iteration" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 2, "negA", :negative)

    e = edges(map)
    @test length(e) == n_edges(map) == 2
    @test Set((x.run, x.linked_run, x.relation_type) for x in e) ==
          Set([(1, "posA", :positive), (2, "negA", :negative)])

    @test Set(collect(map)) == Set(e)
end

@testset "DataFrame round-trip" begin
    map = RunMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "blankA", :blank; metadata=Dict(:note => "plate1"))
    link!(map, 2, "posA", :positive)

    df = DataFrame(map)
    @test df isa DataFrame
    @test nrow(df) == n_edges(map)
    @test Set(names(df)) == Set(["run", "linked_run", "relation_type", "metadata"])

    map2 = RunMap(df)
    @test Set(edges(map)) == Set(edges(map2))

    # custom column names
    df3 = DataFrame(map)
    rename!(df3, :run => :sample)
    map3 = RunMap(df3; run_col=:sample)
    @test Set(edges(map)) == Set(edges(map3))
end

@testset "components" begin
    @testset "single connected component" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "a", :positive)
        link!(map, 2, "b", :negative)

        @test n_components(map) == 1
        comps = components(map)
        @test length(comps) == 1
        c = comps[1]
        @test Set(edges(c)) == Set(edges(map))
        @test Set(runs(c)) == Set(runs(map))
    end

    @testset "multiple disjoint components" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "b", :positive)

        @test n_components(map) == 2
        node_sets = Set(Set(runs(c)) for c in components(map))
        @test node_sets == Set([Set([1, "a"]), Set([2, "b"])])
        @test Set(component_sizes(map)) == Set([2, 2])
    end

    @testset "orphan nodes as singletons" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        add_run!(map, 99)
        add_run!(map, "orphanC")

        @test n_components(map) == 3
        singleton_nodes = Set{Any}()
        for c in components(map)
            n_nodes(c) == 1 && push!(singleton_nodes, only(runs(c)))
        end
        @test singleton_nodes == Set(Any[99, "orphanC"])
    end

    @testset "n_nodes/component_sizes correctness" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        link!(map, 1, "b", :negative)
        link!(map, 2, "c", :positive)

        @test n_nodes(map) == n_runs(map)
        for c in components(map)
            @test n_nodes(c) == length(runs(c))
        end
        @test Set(component_sizes(map)) == Set(n_nodes.(components(map)))
    end

    @testset "edge/role fidelity per component" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        link!(map, 1, "blank1", :blank)
        link!(map, 2, "b", :positive)

        for c in components(map)
            comp_nodes = Set(runs(c))
            expected = Set(e for e in edges(map) if e.run in comp_nodes && e.linked_run in comp_nodes)
            @test Set(edges(c)) == expected
            for r in comp_nodes
                @test Set(relation_types(c, r)) == Set(relation_types(map, r))
                @test Set(roles(c, r)) == Set(roles(map, r))
            end
        end
    end

    @testset "metadata preservation and non-aliasing" begin
        map = RunMap()
        link!(map, 1, "a", :blank; metadata=Dict(:note => "x"))

        comp = only(components(map))
        @test edge_metadata(comp, 1, "a", :blank) == Dict(:note => "x")

        set_metadata!(comp, 1, "a", :blank, Dict(:note => "changed"))
        @test edge_metadata(map, 1, "a", :blank) == Dict(:note => "x")
    end

    @testset "empty map" begin
        map = RunMap()
        @test components(map) == RunMap{Any}[]
        @test n_components(map) == 0
        @test component_sizes(map) == Int[]
    end

    @testset "map not mutated" begin
        map = RunMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "b", :negative)

        before = (n_runs(map), n_edges(map), Set(edges(map)))
        components(map)
        n_components(map)
        component_sizes(map)
        after = (n_runs(map), n_edges(map), Set(edges(map)))
        @test before == after
    end
end

@testset "scheduling" begin
    @testset "greedy/MILP group-count agreement" begin
        for (n, capacity) in [(10, 3), (9, 3), (1, 5), (7, 1)]
            g_greedy = assign_groups_greedy(n, capacity)
            g_milp = assign_groups_MILP(n, capacity)
            expected = cld(n, capacity)
            @test length(unique(g_greedy)) == expected
            @test length(unique(g_milp)) == expected
            @test all(count(==(g), g_greedy) <= capacity for g in unique(g_greedy))
            @test all(count(==(g), g_milp) <= capacity for g in unique(g_milp))
            @test length(g_greedy) == n && length(g_milp) == n
        end
    end

    @testset "weighted bin-packing (FFD and MILP)" begin
        weights = [4, 3, 3, 2, 2, 1]
        capacity = 5
        for solver_fun in (assign_groups_greedy, assign_groups_MILP)
            g = solver_fun(weights, capacity)
            @test length(g) == length(weights)
            for grp in unique(g)
                total = sum(weights[i] for i in eachindex(weights) if g[i] == grp)
                @test total <= capacity
            end
        end

        # MILP should never need more groups than greedy's warm bound
        g_greedy = assign_groups_greedy(weights, capacity)
        g_milp = assign_groups_MILP(weights, capacity)
        @test length(unique(g_milp)) <= length(unique(g_greedy))

        # weight exceeding capacity throws
        @test_throws ArgumentError assign_groups_greedy([10], 5)
        @test_throws ArgumentError assign_groups_MILP([10], 5)

        # empty weights
        @test assign_groups_greedy(Int[], 5) == Int[]
        @test assign_groups_MILP(Int[], 5) == Int[]
    end

    @testset "schedule_uniform_controls: components/sizes" begin
        runs_list = collect(1:10)
        role_counts = Dict(:positive => 1, :negative => 1)
        cap = 5 # group_capacity = 5 - 2 = 3 -> ceil(10/3) = 4 groups
        for solver in ("greedy", "MILP")
            map = schedule_uniform_controls(runs_list, role_counts, cap; solver=solver)
            @test n_components(map) == cld(10, 3)
            @test all(<=(cap), component_sizes(map))
            @test Set(runs_list) ⊆ Set(runs(map))
            @test n_runs(map) - length(runs_list) == n_components(map) * 2
        end
    end

    @testset "dense linking within each group" begin
        runs_list = collect(1:6)
        role_counts = Dict(:positive => 2, :negative => 1)
        cap = 8 # C_count=3, group_capacity=5
        map = schedule_uniform_controls(runs_list, role_counts, cap; solver="greedy")
        for comp in components(map)
            comp_runs = filter(n -> n in runs_list, runs(comp))
            comp_controls = filter(n -> !(n in runs_list), runs(comp))
            for r in comp_runs, c in comp_controls
                @test has_link(comp, r, c)
            end
            for c in comp_controls
                @test Set(roles(comp, c)) ⊆ Set([:positive, :negative])
            end
            @test count(c -> :positive in roles(comp, c), comp_controls) == 2
            @test count(c -> :negative in roles(comp, c), comp_controls) == 1
        end
    end

    @testset "default linked-run id factory format" begin
        ids = [default_linked_run_id_factory(g, r, i) for g in 1:2 for r in (:positive, :negative) for i in 1:2]
        @test length(ids) == length(unique(ids))
        @test default_linked_run_id_factory(1, :positive, 1) == :positive_g1_1
        @test default_linked_run_id_factory(3, :negative, 2) == :negative_g3_2
    end

    @testset "custom linked_run_id_factory and type resolution" begin
        runs_list = collect(1:4)
        role_counts = Dict(:blank => 1)
        cap = 4

        # types differ (Int runs, String ids) -> falls back to RunMap{Any}
        factory(g, r, i) = "custom_$(g)_$(r)_$(i)"
        map = schedule_uniform_controls(runs_list, role_counts, cap; linked_run_id_factory=factory)
        @test map isa RunMap{Any}
        @test all(x -> x isa String, filter(n -> !(n in runs_list), runs(map)))

        # types coincide (Symbol runs, default Symbol-returning factory) -> concrete RunMap{Symbol}
        sym_runs = [:r1, :r2, :r3, :r4]
        map2 = schedule_uniform_controls(sym_runs, role_counts, cap)
        @test map2 isa RunMap{Symbol}
    end

    @testset "validation errors" begin
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict{Symbol,Int}(), 5)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 0), 5)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 1, :negative => 1), 2)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 1, "positive" => 1), 5)
    end

    @testset "empty runs short-circuits without invoking a solver" begin
        map = schedule_uniform_controls(Int[], Dict(:positive => 1), 5)
        @test map isa RunMap{Int}
        @test n_runs(map) == 0

        # bogus solver name would KeyError if ever invoked -- confirms short-circuit truly skips dispatch
        @test schedule_uniform_controls(Int[], Dict(:positive => 1), 5; solver="not_a_real_solver") isa RunMap
    end

    @testset "solver kwargs forwarding (MILP optimizer/timelimit)" begin
        runs_list = collect(1:6)
        map = schedule_uniform_controls(runs_list, Dict(:positive => 1), 4;
                                         solver="MILP", timelimit=10)
        @test n_components(map) == cld(6, 3)
    end
end

@testset "schedule_duplicates" begin
    @testset "basic construction" begin
        map = schedule_duplicates([:A, :B], 2)
        @test Set(linked_runs(map, :A)) == Set([:A_dup1, :A_dup2])
        @test Set(relation_types(map, :A)) == Set([:duplicate])
        @test linking_runs(map, :A_dup1) == [:A]
        @test n_runs(map) == 6 # 2 runs + 4 duplicates
    end

    @testset "default id factory format" begin
        @test default_duplicate_id_factory(:A, 1) == :A_dup1
        @test default_duplicate_id_factory("run1", 3) == Symbol("run1_dup3")
    end

    @testset "custom factory and type resolution" begin
        factory(run, i) = "$(run)_copy$(i)"
        map = schedule_duplicates([:A, :B], 1; duplicate_id_factory=factory)
        @test map isa RunMap{Any} # Symbol runs, String ids -> promote_type(Symbol,String)==Any

        map2 = schedule_duplicates(["A", "B"], 1; duplicate_id_factory=factory)
        @test map2 isa RunMap{String} # String runs, String ids coincide
    end

    @testset "n_duplicates == 0 still registers runs" begin
        map = schedule_duplicates([1, 2, 3], 0)
        @test map isa RunMap{Int}
        @test Set(runs(map)) == Set([1, 2, 3])
        @test n_edges(map) == 0
    end

    @testset "empty runs" begin
        map = schedule_duplicates(Int[], 2)
        @test map isa RunMap{Int}
        @test n_runs(map) == 0
    end
end

@testset "schedule_controls!" begin
    @testset "extends an existing map" begin
        map = schedule_duplicates([:A, :B], 1)
        pre_edges = Set(edges(map))

        pools = Dict(:positive => [:X1, :X2], :negative => [:Y1, :Y2])
        schedule_controls!(map, runs(map), pools, Dict(:positive => 1, :negative => 1), 4)

        @test pre_edges ⊆ Set(edges(map)) # original edges survive
        @test n_edges(map) > length(pre_edges)
    end

    @testset "dense linking and pool exclusivity" begin
        map = RunMap{Symbol}()
        for r in [:r1, :r2, :r3, :r4]
            add_run!(map, r)
        end
        pools = Dict(:positive => [:X1, :X2], :negative => [:Y1, :Y2])
        schedule_controls!(map, [:r1, :r2, :r3, :r4], pools, Dict(:positive => 1, :negative => 1), 4)

        @test n_components(map) == 2
        used_controls = Set{Symbol}()
        for comp in components(map)
            comp_runs = filter(n -> n in [:r1, :r2, :r3, :r4], runs(comp))
            comp_controls = filter(n -> !(n in [:r1, :r2, :r3, :r4]), runs(comp))
            @test length(comp_controls) == 2
            for r in comp_runs, c in comp_controls
                @test has_link(comp, r, c)
            end
            for c in comp_controls
                @test c ∉ used_controls # exclusivity: never claimed by another group
                push!(used_controls, c)
            end
        end
        @test used_controls == Set([:X1, :X2, :Y1, :Y2])
    end

    @testset "insufficient supply throws" begin
        map = RunMap{Symbol}()
        for r in [:r1, :r2, :r3, :r4]
            add_run!(map, r)
        end
        pools = Dict(:positive => [:X1]) # only 1 available, but 2 groups need 1 each -> insufficient? actually need 2
        @test_throws ArgumentError schedule_controls!(map, [:r1, :r2, :r3, :r4], pools, Dict(:positive => 1), 3)
    end

    @testset "missing role in pool throws" begin
        map = RunMap{Symbol}()
        add_run!(map, :r1)
        pools = Dict(:positive => [:X1, :X2])
        @test_throws ArgumentError schedule_controls!(map, [:r1], pools, Dict(:positive => 1, :negative => 1), 4)
    end

    @testset "empty active_runs is a no-op" begin
        map = schedule_duplicates([:A], 1)
        before = Set(edges(map))
        schedule_controls!(map, Symbol[], Dict(:positive => [:X1]), Dict(:positive => 1), 4)
        @test Set(edges(map)) == before
    end

    @testset "cluster-aware: existing cluster never split across groups" begin
        # A has 1 duplicate (cluster size 2); B, C, D are orphans (cluster size 1 each).
        map = schedule_duplicates([:A], 1)
        add_run!(map, :B)
        add_run!(map, :C)
        add_run!(map, :D)
        active = [:A, :A_dup1, :B, :C, :D]

        pools = Dict(:positive => [:X1, :X2, :X3])
        schedule_controls!(map, active, pools, Dict(:positive => 1), 3) # group_capacity=2

        # A and A_dup1 (already linked) must be in the same component.
        a_comp = only(filter(c -> :A in runs(c), components(map)))
        @test :A_dup1 in runs(a_comp)
        @test all(<=(3), component_sizes(map))
    end

    @testset "cluster larger than group_capacity throws" begin
        map = schedule_duplicates([:A], 3) # cluster {A, A_dup1, A_dup2, A_dup3} has size 4
        pools = Dict(:positive => [:X1, :X2])
        @test_throws ArgumentError schedule_controls!(map, runs(map), pools, Dict(:positive => 1), 4) # group_capacity=3 < 4
    end
end

@testset "two-stage pipeline integration" begin
    map = schedule_duplicates([:A, :B, :C], 2) # 3 originals + 6 duplicates = 9 active runs
    active = runs(map)
    @test length(active) == 9

    pools = Dict(:positive => [Symbol("X$i") for i in 1:6], :negative => [Symbol("Y$i") for i in 1:6])
    schedule_controls!(map, active, pools, Dict(:positive => 1, :negative => 1), 5) # group_capacity = 5-2 = 3

    # Every active run gets exactly one positive and one negative control -- guaranteed
    # regardless of how the partitioner grouped nodes.
    for r in active
        @test count(c -> :positive in roles(map, c), linked_runs(map, r)) == 1
        @test count(c -> :negative in roles(map, c), linked_runs(map, r)) == 1
    end

    # Cluster-aware partitioning: A/A_dup1/A_dup2 form one pre-existing cluster of
    # weight 3 (== group_capacity), so it lands in its own group exactly, and the
    # partitioner still uses exactly cld(9,3)=3 groups overall.
    used_positive = Set(c for r in active for c in linked_runs(map, r) if :positive in roles(map, c))
    used_negative = Set(c for r in active for c in linked_runs(map, r) if :negative in roles(map, c))
    @test length(used_positive) == cld(9, 3)
    @test length(used_negative) == cld(9, 3)

    # Components/cap guarantees now hold exactly, since clusters are never split
    # across groups.
    @test n_components(map) == cld(9, 3)
    @test all(<=(5), component_sizes(map))

    # A and both its duplicates always end up in the same final component.
    a_component = only(filter(c -> :A in runs(c), components(map)))
    @test Set([:A, :A_dup1, :A_dup2]) ⊆ Set(runs(a_component))
end

@testset "JSON round-trip" begin
    map = RunMap()
    add_run!(map, 3) # orphan node
    add_run!(map, "orphanControl") # orphan node
    link!(map, 1, "posA", :positive)
    link!(map, 1, "blankA", :blank; metadata=Dict(:note => "plate1"))
    link!(map, 2, "posA", :positive)

    s = runmap_to_json(map)
    @test s isa String

    map2 = json_to_runmap(s)
    @test Set(runs(map2)) == Set(runs(map))
    @test n_edges(map2) == n_edges(map)
    @test edge_metadata(map2, 1, "blankA", :blank) == Dict(:note => "plate1")

    mktempdir() do dir
        path = joinpath(dir, "map.json")
        write_json(path, map)
        map3 = read_runmap_json(path)
        @test n_edges(map3) == n_edges(map)
        @test Set(runs(map3)) == Set(runs(map))
    end
end
