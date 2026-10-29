# A cache of a location with an attribute that was set to missing: it stores no value and the unit of the attribute (as the
# events do), and a cache written before that fix, with the text "missing" as its unit, can still be read.

@testset "caching: an attribute without a value" begin
    uc_plate = generate_location(WP96,"uc plate")
    upload(set_attribute!,uc_plate,Temperature(25u"°C")); sleep(0.02)
    upload(set_attribute!,uc_plate,Temperature(missing)); sleep(0.02)
    uc_id = location_id(uc_plate)
    cache(uc_plate)
    row = query_db("""SELECT a.Value, a.Unit FROM CachedEnvironments c JOIN CachedAttributes a ON a.AttributeSetID = c.AttributeSetID
        WHERE c.LocationID = ? AND a.AttributeID = 'Temperature' ORDER BY c.ID DESC LIMIT 1""",(uc_id,))
    @test ismissing(row.Value[1])
    @test row.Unit[1] == "°C"
    @test ismissing(CHESSCore.value(CHESSCore.attributes(reconstruct_environment(uc_id))[:Temperature]))
    loc = reconstruct_location(uc_id)
    @test loc isa Location

    # a cache from before the fix
    execute_db("UPDATE CachedAttributes SET Unit = 'missing' WHERE Value IS NULL AND Unit = '°C'")
    @test ismissing(CHESSCore.value(CHESSCore.attributes(reconstruct_environment(uc_id))[:Temperature]))
    @test reconstruct_location(uc_id) isa Location
end
