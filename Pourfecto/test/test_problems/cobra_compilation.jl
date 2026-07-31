using Pourfecto, CHESSCore, Unitful, Random, HiGHS
Random.seed!(48207531)

# using the same setup as the combinatorial media test 

reagents = [string_to_reagent("R$i",Solid) for i in 1:48]
water = string_to_reagent("water",Liquid)


source_deep_well = build_location(location_kinds[:DeepWP96])



for r in eachindex(reagents)
    st = 2u"ml" * water  + 2u"g" * reagents[r] 
    well = children(source_deep_well)[r]
    well.stock = st
    well2 = children(source_deep_well)[r+length(reagents)]
    well2.stock =2u"ml" * water 
end 

n_plates = 2

target_plates = Labware[]

for p in 1:n_plates 
    plt = build_location(location_kinds[:WP96])
    for well in children(plt) 
        well.stock = 200u"µL" * water 
        for r in reagents 
            if rand() <= 0.5
                well.stock += 5u"mg" * r 
            end 
        end 
    end 
    push!(target_plates,plt)
end 


configurations["cobra"].settings["cobra_path"] = "C:\\Cobra\\"

priority = PriorityDict("water" => typemax(UInt64))

# This fixture's continuous QP (48 reagents x 288 wells) is too large for SCIP (the test suite's
# default free solver) to solve within a reasonable time limit; HiGHS handles it quickly. min_cost_flow
# (the default objective, used here) has no MILP flag and no quadratic scheduling constraints, so
# HiGHS's lack of indicator/quadratic-constraint support (which rules it out as the global default --
# see runtests.jl) doesn't apply here.
pc1 = pourfecto([source_deep_well],target_plates,[configurations["cobra"]];priority=priority,optimizer=HiGHS.Optimizer)

test_pourcast_compilation("Cobra Compilation",pc1)

#compile("/Users/BDavid/Desktop/test_cobra_compile",pc1)