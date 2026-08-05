using Pourfecto, CHESSCore, Unitful

water = string_to_reagent("water",Liquid)
X = string_to_reagent("X",Liquid) # a reagent already present in the "existing" well content
Y = string_to_reagent("Y",Liquid) # a trace reagent present only in a source, never restated in any target
NaOH = string_to_reagent("NaOH",Liquid) # the reagent being added in place

@testset "in-place planning: diagonal pin, off-diagonal zero, capacity" begin
    s1 = 150u"µL"*water + 50u"µL"*X   # well A existing content, 200µL total
    s2 = 100u"µL"*water + 30u"µL"*X   # well B existing content, 130µL total
    s3 = 100u"mL"*NaOH                # concentrated NaOH reservoir

    t1 = 150u"µL"*water + 50u"µL"*X + 5u"µL"*NaOH
    t2 = 100u"µL"*water + 30u"µL"*X + 3u"µL"*NaOH

    swp = [(1,1),(2,2)]
    caps = [1000.0,1000.0]

    pc = Pourfecto.planner([s1,s2,s3],[t1,t2];
        priority=Pourfecto.PriorityDict("NaOH"=>UInt(0)),
        same_well_pairs=swp,target_capacities=caps)

    V = Pourfecto.transfers(pc)

    @test isapprox(V[1,1],200;atol=1e-2) # existing content of well A carries forward exactly
    @test isapprox(V[2,2],130;atol=1e-2) # existing content of well B carries forward exactly
    @test isapprox(V[1,2],0;atol=1e-2)   # no cross-well leak from well A's pinned content
    @test isapprox(V[2,1],0;atol=1e-2)   # no cross-well leak from well B's pinned content
    @test isapprox(V[3,1],5;atol=1e-2)   # exact NaOH dose delivered to well A
    @test isapprox(V[3,2],3;atol=1e-2)   # exact NaOH dose delivered to well B

    # capacity: well A can't hold its existing 200µL plus any addition if capacity is set below that
    @test_throws ErrorException Pourfecto.planner([s1,s2,s3],[t1,t2];
        priority=Pourfecto.PriorityDict("NaOH"=>UInt(0)),
        same_well_pairs=swp,target_capacities=[190.0,1000.0])
end

@testset "in-place planning: incomplete target declaration is a legitimate infeasibility" begin
    # well A's existing content includes a trace reagent Y that the target never restates anywhere.
    # Y therefore defaults to priority 0 (source-only) and must be exactly zero in every target,
    # directly contradicting the diagonal pin that forces Y's existing amount to carry forward.
    # water/X/NaOH are kept in global balance (source supply >= target demand) so this exercises the
    # solver-level infeasibility (build_planning_model's pin + priority-0 constraint), not the
    # separate, unrelated check_inputs shortage precondition.
    s1 = 150u"µL"*water + 50u"µL"*X + 10u"µL"*Y
    s_naoh = 100u"mL"*NaOH
    t1 = 150u"µL"*water + 50u"µL"*X + 5u"µL"*NaOH # omits Y entirely

    @test_throws ErrorException Pourfecto.planner([s1,s_naoh],[t1];same_well_pairs=[(1,1)],target_capacities=[1000.0])
end

@testset "in-place scheduling end-to-end" begin
    # Well.stock is a single mutable field, so "current state" and "desired state" for the same
    # physical plate must be two separate Labware objects sharing the same name -- same_well_pairs
    # matches by (labware name, well name), not object identity, which is exactly what lets these
    # two objects be recognized as the same physical plate.
    source_plate = build_location(location_kinds[:WP96],"in_place_plate")
    target_plate = build_location(location_kinds[:WP96],"in_place_plate")

    for w in vec(children(source_plate))
        w.stock = 150u"µL"*water + 50u"µL"*X
    end
    for w in vec(children(target_plate))
        w.stock = 150u"µL"*water + 50u"µL"*X + 5u"µL"*NaOH
    end

    reservoir = build_location(location_kinds[:DeepReservoir])
    children(reservoir)[1].stock = 100u"mL"*NaOH

    c = [configurations["p200"],configurations["plate_master"]]

    pc = pourfecto([reservoir,source_plate],[target_plate],c;allow_in_place=true,priority=Pourfecto.PriorityDict("NaOH"=>UInt(0)))

    @test all_planned_approx_target(pc;atol=1e-1*u"µL")

    @test_throws ErrorException pourfecto([reservoir,source_plate],[target_plate],c) # same call, no opt-in, still blocked by default
end
