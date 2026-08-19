using Test, ControlMaps, DataFrames, JSON, HiGHS

import ControlMaps: assign_groups_greedy, assign_groups_MILP

ControlMaps._default_optimizer[] = HiGHS.Optimizer

@testset "Construction" begin
    map = ControlMap()
    @test n_runs(map) == 0
    @test n_controls(map) == 0
    @test n_edges(map) == 0

    typed = ControlMap{Int,String}()
    @test typed isa ControlMap{Int,String}
    @test n_edges(typed) == 0
end

@testset "add_run!/add_control!" begin
    map = ControlMap()
    add_run!(map, 1)
    @test has_run(map, 1)
    @test controls(map, 1) == []

    add_run!(map, 1) # idempotent
    @test n_runs(map) == 1

    add_control!(map, "posA")
    @test has_control(map, "posA")
    @test runs(map, "posA") == []
end

@testset "link! basic round-trip" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)

    @test controls(map, 1) == ["posA"]
    @test runs(map, "posA") == [1]

    # implicit node creation
    @test has_run(map, 1)
    @test has_control(map, "posA")

    @test has_link(map, 1, "posA")
    @test has_link(map, 1, "posA"; type=:positive)
    @test !has_link(map, 1, "posA"; type=:negative)
end

@testset "multiple control types per run" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "negA", :negative)
    link!(map, 1, "blankA", :blank)

    @test Set(controls(map, 1)) == Set(["posA", "negA", "blankA"])
    @test controls(map, 1; type=:positive) == ["posA"]
    @test Set(control_types(map, 1)) == Set([:positive, :negative, :blank])

    # string/symbol control_type equivalence
    map2 = ControlMap()
    link!(map2, 1, "posA", "positive")
    @test controls(map2, 1; type=:positive) == ["posA"]
end

@testset "multiple runs per control" begin
    map = ControlMap()
    link!(map, 1, "blank", :blank)
    link!(map, 2, "blank", :blank)
    link!(map, 3, "blank", :blank)

    @test Set(runs(map, "blank")) == Set([1, 2, 3])
    @test Set(roles(map, "blank")) == Set([:blank])
end

@testset "duplicate link! calls" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "posA", :positive)
    @test n_edges(map) == 1

    link!(map, 1, "posA", :positive; metadata=Dict(:a => 1))
    link!(map, 1, "posA", :positive; metadata=Dict(:b => 2))
    @test n_edges(map) == 1
    @test edge_metadata(map, 1, "posA", :positive) == Dict(:a => 1, :b => 2)
end

@testset "unlink!" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "posA", :negative)

    unlink!(map, 1, "posA", :positive)
    @test !has_link(map, 1, "posA"; type=:positive)
    @test has_link(map, 1, "posA"; type=:negative)

    unlink!(map, 1, "posA")
    @test !has_link(map, 1, "posA")
    @test has_run(map, 1) # orphan node survives
    @test has_control(map, "posA")

    # no-op on nonexistent edge
    unlink!(map, 999, "nope")
    @test n_edges(map) == 0
end

@testset "remove_run!/remove_control!" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "negA", :negative)
    link!(map, 2, "posA", :positive)

    remove_run!(map, 1)
    @test !has_run(map, 1)
    @test controls(map, 1) == []
    @test runs(map, "posA") == [2]
    @test runs(map, "negA") == []

    remove_control!(map, "posA")
    @test !has_control(map, "posA")
    @test controls(map, 2) == []

    # no-op on never-registered node
    remove_run!(map, 999)
    remove_control!(map, "nope")
end

@testset "metadata" begin
    map = ControlMap()
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
    map = ControlMap()
    link!(map, 1, "posA", :positive)

    @test controls(map, 999) == []
    @test runs(map, "nope") == []

    unlink!(map, 1, "posA")
    @test controls(map, 1) == [] # orphaned but registered
end

@testset "edges/iteration" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 2, "negA", :negative)

    e = edges(map)
    @test length(e) == n_edges(map) == 2
    @test Set((x.run, x.control, x.control_type) for x in e) ==
          Set([(1, "posA", :positive), (2, "negA", :negative)])

    @test Set(collect(map)) == Set(e)
end

@testset "DataFrame round-trip" begin
    map = ControlMap()
    link!(map, 1, "posA", :positive)
    link!(map, 1, "blankA", :blank; metadata=Dict(:note => "plate1"))
    link!(map, 2, "posA", :positive)

    df = DataFrame(map)
    @test df isa DataFrame
    @test nrow(df) == n_edges(map)
    @test Set(names(df)) == Set(["run", "control", "control_type", "metadata"])

    map2 = ControlMap(df)
    @test Set(edges(map)) == Set(edges(map2))

    # custom column names
    df3 = DataFrame(map)
    rename!(df3, :run => :sample)
    map3 = ControlMap(df3; run_col=:sample)
    @test Set(edges(map)) == Set(edges(map3))
end

@testset "components" begin
    @testset "single connected component" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "a", :positive)
        link!(map, 2, "b", :negative)

        @test n_components(map) == 1
        comps = components(map)
        @test length(comps) == 1
        c = comps[1]
        @test Set(edges(c)) == Set(edges(map))
        @test Set(runs(c)) == Set(runs(map))
        @test Set(controls(c)) == Set(controls(map))
    end

    @testset "multiple disjoint components" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "b", :positive)

        @test n_components(map) == 2
        node_sets = Set(Set(vcat(runs(c), controls(c))) for c in components(map))
        @test node_sets == Set([Set([1, "a"]), Set([2, "b"])])
        @test Set(component_sizes(map)) == Set([2, 2])
    end

    @testset "orphan run and orphan control as singletons" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        add_run!(map, 99)
        add_control!(map, "orphanC")

        @test n_components(map) == 3
        singleton_nodes = Set{Any}()
        for c in components(map)
            n_nodes(c) == 1 && push!(singleton_nodes, only(vcat(runs(c), controls(c))))
        end
        @test singleton_nodes == Set(Any[99, "orphanC"])
    end

    @testset "n_nodes/component_sizes correctness" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        link!(map, 1, "b", :negative)
        link!(map, 2, "c", :positive)

        @test n_nodes(map) == n_runs(map) + n_controls(map)
        for c in components(map)
            @test n_nodes(c) == length(runs(c)) + length(controls(c))
        end
        @test Set(component_sizes(map)) == Set(n_nodes.(components(map)))
    end

    @testset "edge/role fidelity per component" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        link!(map, 1, "blank1", :blank)
        link!(map, 2, "b", :positive)

        for c in components(map)
            comp_runs = Set(runs(c))
            comp_controls = Set(controls(c))
            expected = Set(e for e in edges(map) if e.run in comp_runs && e.control in comp_controls)
            @test Set(edges(c)) == expected
            for r in comp_runs
                @test Set(control_types(c, r)) == Set(control_types(map, r))
            end
            for ctrl in comp_controls
                @test Set(roles(c, ctrl)) == Set(roles(map, ctrl))
            end
        end
    end

    @testset "metadata preservation and non-aliasing" begin
        map = ControlMap()
        link!(map, 1, "a", :blank; metadata=Dict(:note => "x"))

        comp = only(components(map))
        @test edge_metadata(comp, 1, "a", :blank) == Dict(:note => "x")

        set_metadata!(comp, 1, "a", :blank, Dict(:note => "changed"))
        @test edge_metadata(map, 1, "a", :blank) == Dict(:note => "x")
    end

    @testset "empty map" begin
        map = ControlMap()
        @test components(map) == ControlMap{Any,Any}[]
        @test n_components(map) == 0
        @test component_sizes(map) == Int[]
    end

    @testset "R == C same-value collision" begin
        map = ControlMap{Int,Int}()
        add_run!(map, 1)
        add_control!(map, 1)

        @test n_components(map) == 2
    end

    @testset "map not mutated" begin
        map = ControlMap()
        link!(map, 1, "a", :positive)
        link!(map, 2, "b", :negative)

        before = (n_runs(map), n_controls(map), n_edges(map), Set(edges(map)))
        components(map)
        n_components(map)
        component_sizes(map)
        after = (n_runs(map), n_controls(map), n_edges(map), Set(edges(map)))
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

    @testset "schedule_uniform_controls: components/sizes" begin
        runs_list = collect(1:10)
        role_counts = Dict(:positive => 1, :negative => 1)
        cap = 5 # group_capacity = 5 - 2 = 3 -> ceil(10/3) = 4 groups
        for solver in ("greedy", "MILP")
            map = schedule_uniform_controls(runs_list, role_counts, cap; solver=solver)
            @test n_components(map) == cld(10, 3)
            @test all(<=(cap), component_sizes(map))
            @test Set(runs(map)) == Set(runs_list)
            @test n_controls(map) == n_components(map) * 2
        end
    end

    @testset "dense linking within each group" begin
        runs_list = collect(1:6)
        role_counts = Dict(:positive => 2, :negative => 1)
        cap = 8 # C_count=3, group_capacity=5
        map = schedule_uniform_controls(runs_list, role_counts, cap; solver="greedy")
        for comp in components(map)
            comp_runs = runs(comp)
            comp_controls = controls(comp)
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

    @testset "default control id factory format" begin
        ids = [default_control_id_factory(g, r, i) for g in 1:2 for r in (:positive, :negative) for i in 1:2]
        @test length(ids) == length(unique(ids))
        @test default_control_id_factory(1, :positive, 1) == :positive_g1_1
        @test default_control_id_factory(3, :negative, 2) == :negative_g3_2
    end

    @testset "custom control_id_factory" begin
        runs_list = collect(1:4)
        role_counts = Dict(:blank => 1)
        cap = 4
        factory(g, r, i) = "custom_$(g)_$(r)_$(i)"
        map = schedule_uniform_controls(runs_list, role_counts, cap; control_id_factory=factory)
        @test map isa ControlMap{Int,String}
        @test all(startswith(c, "custom_") for c in controls(map))
    end

    @testset "validation errors" begin
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict{Symbol,Int}(), 5)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 0), 5)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 1, :negative => 1), 2)
        @test_throws ArgumentError schedule_uniform_controls([1, 2], Dict(:positive => 1, "positive" => 1), 5)
    end

    @testset "empty runs short-circuits without invoking a solver" begin
        map = schedule_uniform_controls(Int[], Dict(:positive => 1), 5)
        @test map isa ControlMap{Int,Any}
        @test n_runs(map) == 0 && n_controls(map) == 0

        # bogus solver name would KeyError if ever invoked -- confirms short-circuit truly skips dispatch
        @test schedule_uniform_controls(Int[], Dict(:positive => 1), 5; solver="not_a_real_solver") isa ControlMap
    end

    @testset "solver kwargs forwarding (MILP optimizer/timelimit)" begin
        runs_list = collect(1:6)
        map = schedule_uniform_controls(runs_list, Dict(:positive => 1), 4;
                                         solver="MILP", timelimit=10)
        @test n_components(map) == cld(6, 3)
    end
end

@testset "JSON round-trip" begin
    map = ControlMap()
    add_run!(map, 3) # orphan run
    add_control!(map, "orphanControl") # orphan control
    link!(map, 1, "posA", :positive)
    link!(map, 1, "blankA", :blank; metadata=Dict(:note => "plate1"))
    link!(map, 2, "posA", :positive)

    s = controlmap_to_json(map)
    @test s isa String

    map2 = json_to_controlmap(s)
    @test Set(runs(map2)) == Set(runs(map))
    @test Set(controls(map2)) == Set(controls(map))
    @test n_edges(map2) == n_edges(map)
    @test edge_metadata(map2, 1, "blankA", :blank) == Dict(:note => "plate1")

    mktempdir() do dir
        path = joinpath(dir, "map.json")
        write_json(path, map)
        map3 = read_controlmap_json(path)
        @test n_edges(map3) == n_edges(map)
        @test Set(runs(map3)) == Set(runs(map))
    end
end
