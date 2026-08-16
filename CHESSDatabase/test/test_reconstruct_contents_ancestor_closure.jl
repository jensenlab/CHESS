# Regression tests for Bug B: `get_transfer_ancestors`'s ancestor closure used to only discover
# transfers feeding *into* an already-known well, never other transfers that well sent *away* to a
# destination outside the closure. Reconstructing a well downstream of such an interim withdrawal
# resurrected stock that had already left -- silently wrong for a partial withdrawal, an outright
# crash (negative-quantity mixing error) for a full drain. See
# ../src/reconstruction/reconstruct_contents.jl's `get_transfer_ancestors`/`reconstruct_contents` for
# the fixed mechanism (the `Core` column distinguishing the real ancestor closure from the extra
# "collateral" edges pulled in purely to track a core well's balance correctly).
#
# Runs against the shared database/connection `build_test_database.jl` already set up (new locations
# here get fresh IDs via `generate_location`, so no collision with that file's fixtures) -- same
# pattern `test_reconstruct_contents_bootstrap.jl` uses.

@testset "get_transfer_ancestors accounts for interim withdrawals (Bug B)" begin

    @testset "real transfers: partial withdrawal to an unrelated well" begin
        bacl_lab = generate_location(Lab,"bacl lab 1")
        bacl_room = generate_location(Room,"bacl room 1")
        upload(move_into!,bacl_lab,bacl_room)
        bacl_bottleA = generate_location(Bottle1L,"bacl A")
        bacl_bottleC = generate_location(Bottle1L,"bacl C")
        upload(move_into!,bacl_room,bacl_bottleA)
        upload(move_into!,bacl_room,bacl_bottleC)
        bacl_aw = bacl_bottleA[1,1]
        bacl_cw = bacl_bottleC[1,1]
        deposit!(bacl_aw,500u"mL"*rgt"water",1)
        deposit!(bacl_cw,500u"mL"*rgt"glycerol",1)
        cache(bacl_aw); cache(bacl_cw)

        bacl_plate = generate_location(WP96,"bacl plate 1")
        upload(move_into!,bacl_room,bacl_plate)
        bacl_W, bacl_Y, bacl_X = bacl_plate[1,1], bacl_plate[1,2], bacl_plate[1,3]

        upload(transfer!,bacl_aw,bacl_W,10u"µL")   # W: +10uL water
        upload(transfer!,bacl_W,bacl_Y,3u"µL")     # W -> Y, partial (unrelated to X); W now has 7uL water
        upload(transfer!,bacl_cw,bacl_W,5u"µL")    # W: +5uL glycerol (W now 7uL water + 5uL glycerol = 12uL true)
        upload(transfer!,bacl_W,bacl_X,5u"µL")     # X should get 5/12 of W's TRUE 12uL, not 5/15 of a phantom 15uL

        bacl_result = reconstruct_location(location_id(bacl_X))
        bacl_stock = stock(bacl_result)
        bacl_liquids = liquids(bacl_stock)
        @test isapprox(ustrip(uconvert(u"µL",bacl_liquids[rgt"water"])), 5/12*7.0, atol=1e-6)
        @test isapprox(ustrip(uconvert(u"µL",bacl_liquids[rgt"glycerol"])), 5/12*5.0, atol=1e-6)

        @testset "Core column correctly separates the causal path from the collateral edge" begin
            bacl_rows = CHESSDatabase.get_transfer_ancestors([location_id(bacl_X)],0,get_last_sequence_id())
            bacl_by_pair = Dict((row.Source,row.Destination) => row.Core for row in eachrow(bacl_rows))
            @test bacl_by_pair[(location_id(bacl_aw),location_id(bacl_W))] == 1
            @test bacl_by_pair[(location_id(bacl_cw),location_id(bacl_W))] == 1
            @test bacl_by_pair[(location_id(bacl_W),location_id(bacl_X))] == 1
            @test bacl_by_pair[(location_id(bacl_W),location_id(bacl_Y))] == 0
        end
    end

    @testset "encumbrances=true: the same interim-withdrawal scenario, built from encumbrances" begin
        bacl_lab2 = generate_location(Lab,"bacl lab 2")
        bacl_room2 = generate_location(Room,"bacl room 2")
        upload(move_into!,bacl_lab2,bacl_room2)
        bacl_bottleA2 = generate_location(Bottle1L,"bacl A2")
        bacl_bottleC2 = generate_location(Bottle1L,"bacl C2")
        upload(move_into!,bacl_room2,bacl_bottleA2)
        upload(move_into!,bacl_room2,bacl_bottleC2)
        bacl_aw2 = bacl_bottleA2[1,1]
        bacl_cw2 = bacl_bottleC2[1,1]
        deposit!(bacl_aw2,500u"mL"*rgt"water",1)
        deposit!(bacl_cw2,500u"mL"*rgt"glycerol",1)
        cache(bacl_aw2); cache(bacl_cw2)

        bacl_plate2 = generate_location(WP96,"bacl plate 2")
        upload(move_into!,bacl_room2,bacl_plate2)
        bacl_W2, bacl_X2 = bacl_plate2[1,1], bacl_plate2[1,2]

        upload(transfer!,bacl_aw2,bacl_W2,10u"µL")
        upload(transfer!,bacl_W2,bacl_plate2[1,3],3u"µL")  # real partial withdrawal, unrelated to X2

        bacl_exp = upload_experiment("bug_b_test","tester")
        bacl_pid = upload_protocol(bacl_exp,"bug_b_protocol")
        bacl_cw2_r = reconstruct_location(location_id(bacl_cw2))
        bacl_W2_r1 = reconstruct_location(location_id(bacl_W2))
        encumber(bacl_pid,transfer!,bacl_cw2_r,bacl_W2_r1,5u"µL")   # planned: C2 -> W2
        bacl_W2_r2 = reconstruct_location(location_id(bacl_W2))
        bacl_X2_r = reconstruct_location(location_id(bacl_X2))
        encumber(bacl_pid,transfer!,bacl_W2_r2,bacl_X2_r,5u"µL")    # planned: W2 -> X2

        bacl_result2 = reconstruct_location(location_id(bacl_X2);encumbrances=true)
        bacl_liquids2 = liquids(stock(bacl_result2))
        @test isapprox(ustrip(uconvert(u"µL",bacl_liquids2[rgt"water"])), 5/12*7.0, atol=1e-6)
        @test isapprox(ustrip(uconvert(u"µL",bacl_liquids2[rgt"glycerol"])), 5/12*5.0, atol=1e-6)
    end

    @testset "a cycle in the transfer graph reconstructs correctly (and terminates)" begin
        bacl_lab3 = generate_location(Lab,"bacl lab 3")
        bacl_room3 = generate_location(Room,"bacl room 3")
        upload(move_into!,bacl_lab3,bacl_room3)
        bacl_bottleD = generate_location(Bottle1L,"bacl D")
        upload(move_into!,bacl_room3,bacl_bottleD)
        bacl_dw = bacl_bottleD[1,1]
        deposit!(bacl_dw,500u"mL"*rgt"water",1)
        cache(bacl_dw)

        bacl_plate3 = generate_location(WP96,"bacl plate 3")
        upload(move_into!,bacl_room3,bacl_plate3)
        bacl_W3,bacl_Y3,bacl_V3,bacl_X3 = bacl_plate3[1,1],bacl_plate3[1,2],bacl_plate3[1,3],bacl_plate3[1,4]

        upload(transfer!,bacl_dw,bacl_W3,10u"µL")   # D -> W3
        upload(transfer!,bacl_W3,bacl_Y3,4u"µL")    # W3 -> Y3 (partial, W3 now has 6uL)
        upload(transfer!,bacl_Y3,bacl_V3,4u"µL")    # Y3 -> V3 (full drain of Y3)
        upload(transfer!,bacl_V3,bacl_W3,4u"µL")    # V3 -> W3, cycles back (W3 now has 10uL again)
        upload(transfer!,bacl_W3,bacl_X3,5u"µL")    # X3 should get exactly half of W3's true 10uL water

        bacl_result3 = reconstruct_location(location_id(bacl_X3))
        bacl_liquids3 = liquids(stock(bacl_result3))
        @test isapprox(ustrip(uconvert(u"µL",bacl_liquids3[rgt"water"])), 5.0, atol=1e-6)
    end

end
