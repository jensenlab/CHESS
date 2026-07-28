

function test_pourcast_compilation(name::String,pourcast::Pourcast)

    @testset "$name" begin
        # Make test deterministic if names are randomized
        Random.seed!(1234)

        mktempdir() do outroot
            # --- Act ---
            @test compile(outroot, pourcast) === nothing

            # --- Assert: root exists and has expected top-level outputs ---
            @test isdir(outroot)
            @test isfile(joinpath(outroot, "pourcast.json"))

            # --- Assert: per-config type directory created ---
            cfgs = configs(pourcast)
            @test !isempty(cfgs)
            config_slotting = Pourfecto.slotting_requirements(pourcast)

            for c in eachindex(cfgs)
                if sum(config_slotting[c]) > 0 
                    cfgtype = string(nameof(Pourfecto.get_config_type(cfgs[c])))
                    cfgdir  = joinpath(outroot, cfgtype)
                    @test isdir(cfgdir)

                    # At least one protocol subfolder created for this config
                    protos = filter(name -> isdir(joinpath(cfgdir, name)), readdir(cfgdir))
                    @test length(protos) ≥ 1

                    # And those protocol folders are non-empty (instrument files written)
                    for pname in protos
                        pdir = joinpath(cfgdir, pname)
                        @test length(readdir(pdir)) ≥ 1
                    end
                else 
                    continue 
                end 
            end
        end
    end
end 