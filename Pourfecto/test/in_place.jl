using Pourfecto, CHESSCore, Unitful

@testset "in-place labware name gating and same_well_pairs" begin
    plate_a = build_location(location_kinds[:WP96])
    plate_b = build_location(location_kinds[:WP96]) # independently built -> distinct random name

    # distinct labware: unaffected by in-place gating either way
    @test Pourfecto.all_unique_labware_names([plate_a],[plate_b])
    @test Pourfecto.unambiguous_labware_names([plate_a],[plate_b])

    # same physical labware used as both source and target
    @test !Pourfecto.all_unique_labware_names([plate_a],[plate_a]) # blocked by default
    @test Pourfecto.unambiguous_labware_names([plate_a],[plate_a]) # allowed when opted in

    # genuine ambiguity (a name repeated within one side alone) is never allowed
    @test !Pourfecto.unambiguous_labware_names([plate_a,plate_a],[plate_b])
    @test !Pourfecto.unambiguous_labware_names([plate_a],[plate_b,plate_b])

    swp = Pourfecto.same_well_pairs([plate_a],[plate_a])
    @test length(swp) == length(vec(children(plate_a)))
    @test all(p -> p[1] == p[2], swp) # same object queried on both sides -> identity mapping

    @test isempty(Pourfecto.same_well_pairs([plate_a],[plate_b])) # no shared labware name -> nothing pinned

    caps = Pourfecto.target_well_capacities([plate_a])
    @test length(caps) == length(vec(children(plate_a)))
end

@testset "scheduler rejects shared labware names unless allow_in_place" begin
    plate = build_location(location_kinds[:WP96])
    c = [configurations["p200"],configurations["plate_master"]]

    @test_throws ErrorException Pourfecto.scheduler([plate],[plate],c)
    @test_throws ErrorException Pourfecto.scheduler([plate],[plate],c;allow_in_place=false)
    @test_throws ErrorException Pourfecto.scheduler([plate,plate],[plate],c;allow_in_place=true) # ambiguous within sources alone
end
