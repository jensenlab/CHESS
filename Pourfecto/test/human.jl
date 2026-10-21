using Pourfecto, CHESSCore, Unitful, SCIP, DataFrames, CSV
using Pourfecto.TestUtils

@testset "Human instrument" begin
    nacl = string_to_component("NaCl",Solid)
    gluc = string_to_component("glucose",Solid)
    water = string_to_component("water",Liquid)
    tris = string_to_component("Tris",Liquid)
    naoh = string_to_component("NaOH",Liquid)

    function powder(name,rgt)
        l = build_location(location_kinds[:Conical50],name)
        children(l)[1].stock = 100u"g"*rgt
        return l
    end
    function bottle(name,stock)
        l = build_location(location_kinds[:Bottle1L],name)
        children(l)[1].stock = stock
        return l
    end

    @testset "units and pistons" begin
        @test Pourfecto.amount_unit(50u"g"*nacl) == u"mg"
        @test Pourfecto.amount_unit(5u"mL"*water) == u"µL"
        @test Pourfecto.stock_quantity(2u"g"*nacl) ≈ 2000
        @test Pourfecto.stock_quantity(2u"mL"*water) ≈ 2000


        cfg = Pourfecto.configurations["human"]
        @test [Pourfecto.piston_dimension(p) for p in pistons(head(cfg))] == [:volume,:mass]
        @test test_instrument_interface(cfg)
        @test_throws ErrorException Piston{ContinuousActuator,SingleRepeater}((1u"mL",1u"g"),(1u"mL",2u"mL"),1)
        @test_throws ErrorException human_configuration(min_mass=2u"g",max_mass=1u"g")
    end

    @testset "plan a stock" begin
        p1 = powder("powder_nacl",nacl)
        p2 = powder("powder_glucose",gluc)
        liq = bottle("liquids",100u"mL"*tris)
        wat = bottle("water",900u"mL"*water)
        tgt = bottle("stock",5u"g"*nacl + 2u"g"*gluc + 50u"mL"*tris + 400u"mL"*water)

        pc = pourfecto([p1,p2,liq,wat],[tgt],["human"])
        steps = protocol_steps(pc)
        @test names(steps) == ["step","kind","component","amount","unit","source_labware","source_well","target_labware","target_well","instrument"]
        @test steps.step == 1:4
        @test steps.kind == ["weigh","weigh","pipette","pipette"] # powders first
        @test steps.unit[1] == "mg" && steps.unit[3] == "µL"
        @test steps.amount[1] ≈ 5000 atol=1
        @test steps.amount[2] ≈ 2000 atol=1
        @test steps.amount[3] ≈ 50_000 rtol=1e-3
        @test steps.component[1] == "NaCl"
        @test all(steps.instrument .== "Human")
        @test steps == protocol_steps(pc) # deterministic

        # planned stock matches the target; powder adds no volume
        @test quantity(Pourfecto.planned_stocks(pc)[1]) ≈ 450u"mL" rtol=1e-2

        # compile writes the steps
        mktempdir() do dir
            compile(dir,pc)
            f = joinpath(dir,"Human")
            proto = only(filter(d->isdir(joinpath(f,d)),readdir(f)))
            written = CSV.read(joinpath(f,proto,"protocol_steps.csv"),DataFrame)
            # the protocol lists its sources in slot order, so compare per step rather than by position
            @test sort(written.amount) ≈ sort(steps.amount)
            @test sort(written.kind) == sort(steps.kind)
        end
    end

    @testset "compatibility" begin
        p1 = powder("powder_nacl",nacl)
        wat = bottle("water",900u"mL"*water)
        tgt = bottle("stock",5u"g"*nacl + 400u"mL"*water)
        @test_throws Pourfecto.StockCompatibilityError pourfecto([p1,wat],[tgt],["p200"])
        # powder only through the human, liquid may use either
        pc = pourfecto([p1,wat],[tgt],["human","p200"])
        steps = protocol_steps(pc)
        @test steps.instrument[steps.kind .== "weigh"] == ["Human"]
    end

    @testset "titration is an ordinary planned step" begin
        acid = 100u"mL"*water
        base = bottle("base",50u"mL"*naoh)
        wat = bottle("water",900u"mL"*water)
        p1 = powder("powder_nacl",nacl)
        tgt = bottle("stock",5u"g"*nacl + 400u"mL"*water + 3u"mL"*naoh)
        pc = pourfecto([p1,wat,base],[tgt],["human"])
        steps = protocol_steps(pc)
        row = steps[steps.component .== "NaOH",:]
        @test nrow(row) == 1
        @test row.amount[1] ≈ 3000 rtol=1e-2
    end

    @testset "re-planning a half-made stock" begin
        p1 = powder("powder_nacl",nacl)
        wat = bottle("water",900u"mL"*water)
        # half-made: 2 g NaCl and 200 mL water already in the bottle
        current = bottle("stock",2u"g"*nacl + 200u"mL"*water)
        full = bottle("stock",5u"g"*nacl + 400u"mL"*water)
        pc = pourfecto([p1,wat,current],[full],["human"];allow_in_place=true)
        steps = protocol_steps(pc)
        @test steps.amount[steps.component .== "NaCl"] ≈ [3000.0] atol=1
        @test steps.amount[steps.component .== "water"] ≈ [200_000.0] rtol=1e-3

        # an incomplete declaration (omits what is already in) is infeasible
        incomplete = bottle("stock",1u"g"*nacl + 200u"mL"*water) # less NaCl than the bottle already holds
        # the planner keeps the existing 2 g, so the plan misses the target by more than the solution
        # tolerance: solution_quality flags it, and pourfecto(directory,...) refuses to compile it
        bad = pourfecto([p1,wat,current],[incomplete],["human"];allow_in_place=true)
        @test any(Pourfecto.solution_quality(bad))
        @test_throws ErrorException mktempdir(d->pourfecto(d,[p1,wat,current],[incomplete],["human"];allow_in_place=true))
        @test !any(Pourfecto.solution_quality(pc))
        omits = bottle("stock",3u"g"*nacl)
        @test_throws Pourfecto.InfeasibleSolveError pourfecto([p1,wat,current],[omits],["human"];allow_in_place=true) # drops a component that is already in
    end

    @testset "minimum shot limits" begin
        p1 = powder("powder_nacl",nacl)
        wat = bottle("water",900u"mL"*water)
        tgt = bottle("stock",(0.5u"mg")*nacl + 400u"mL"*water)
        # the smallest weighable amount is 1 mg, so the 0.5 mg target is missed and flagged
        pc = pourfecto([p1,wat],[tgt],["human"];enforce_minimum_shot=true)
        @test any(Pourfecto.solution_quality(pc))
        @test minimum(protocol_steps(pc).amount[protocol_steps(pc).kind .== "weigh"]) >= 1
    end
end
