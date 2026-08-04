using Pourfecto.TestUtils: test_mask_coverage, default_test_labware_kinds

@testset "Masks" begin

    @testset "Mask coverage (generic, per-instrument mask_rules)" begin
        for (name,conf) in configurations
            test_mask_coverage(conf; kinds=default_test_labware_kinds())
        end
    end

end
