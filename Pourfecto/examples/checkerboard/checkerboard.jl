using Pourfecto, JLIMS, Unitful
# define three reagents for the problem 
A = string_to_reagent("A",Solid)
B = string_to_reagent("B",Solid) 
water = string_to_reagent("water",Liquid) 
# generate source and target labware
A_reservior = generate(labwares["DeepReservior"])
B_reservior = generate(labwares["DeepReservior"])
target_plate = generate(labwares["WP96"])

# fill source reserviors with liquid 
A_stock=100u"g" * A + 100u"mL" * water 
B_stock =100u"g" * B + 100u"mL" * water

children(A_reservior)[1].stock = 100u"g" * A + 100u"mL" * water 
children(B_reservior)[1].stock = 100u"g" * B + 100u"mL" * water 

# fill target plate in a checkerboard pattern 
drug_vol = 80
for row in 1:8 
    for col in 1:8 
        children(target_plate)[row,col].stock = (drug_vol - 10*(row-1))u"µL" * A_stock + (drug_vol-10*(col-1))u"µL" * B_stock 
    end 
end 


pc1 = pourfecto([A_reservior,B_reservior],[target_plate],["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"])
pc2 = pourfecto([A_reservior,B_reservior],[target_plate],["single_channel","eight_channel_vertical","eight_channel_horizontal","plate_master"];
objective="min_active_flow")








f1 = flows(pc1)
f2 = flows(pc2)


a1 = flows(pc1) .> 1e-4
a2 = flows(pc2) .> 1e-4


ps1 = planned_stocks(pc1) 
ps2 = planned_stocks(pc2)












