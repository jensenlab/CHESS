using Pourfecto, CHESSCore, Unitful
# define four reagents for the problem 
A = string_to_reagent("A",Solid)
B = string_to_reagent("B",Solid) 
C = string_to_reagent("C",Solid)
D = string_to_reagent("D",Solid)
water = string_to_reagent("water",Liquid) 
# generate source and target labware
solids = [A,B,C,D]

conicals = Labware[]
for sol in solids 
    con = build_location(location_kinds[:Conical50],"$(CHESSCore.name(sol))")
    st = Empty() 
    st+= 20u"g" * sol
    st += 50u"ml" * water 
    deposit!(children(con)[1],st,0)
    push!(conicals,con)
end

con = build_location(location_kinds[:Conical50],"water")
st = 50u"ml" * water 
deposit!(children(con)[1],st,0) 
push!(conicals,con)

target_plates = Labware[]

for _ in 1:3


target_plate = build_location(location_kinds[:DeepWP96])

# fill target plate in a checkerboard pattern 
for row in 1:8 
    for col in 1:12
        children(target_plate)[row,col].stock = row *u"mg" * A + (9-row) * u"mg" * B  + col * u"mg" * C  + (13-col) *u"mg" *D + 200u"µl" * water  
    end 
end 

push!(target_plates,target_plate) 
end 

pc1 = pourfecto(conicals,[target_plates[1]],["nimbus"]) # single dispense file 
 

test_pourcast_compilation("Nimbus Compilation",pc1)
