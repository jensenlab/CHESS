using Pourfecto, CHESSCore, Unitful
# same style of end-to-end scenario as nimbus_compilation.jl, using the 4-channel Nimbus instead.
# 3 solid reagents + 1 water diluent = 4 distinct sources, matching n_channels -- the current
# "tip tied to reagent" model requires reagent (source) count <= channel count (see
# batch_design_four_channel's docstring; reassignment across more reagents than channels is
# explicit follow-up work, not yet supported).
A4 = string_to_component("A4ch",Solid)
B4 = string_to_component("B4ch",Solid)
C4 = string_to_component("C4ch",Solid)
water4 = string_to_component("water4ch",Liquid)
solids4 = [A4,B4,C4]

conicals4 = Labware[]
for sol in solids4
    con = build_location(location_kinds[:Conical50],"$(CHESSCore.name(sol))")
    st = Empty()
    st += 20u"g" * sol
    st += 50u"ml" * water4
    deposit!(children(con)[1],st,0)
    push!(conicals4,con)
end

con4 = build_location(location_kinds[:Conical50],"water4ch")
st4 = 50u"ml" * water4
deposit!(children(con4)[1],st4,0)
push!(conicals4,con4)

target_plate4 = build_location(location_kinds[:DeepWP96])
# rows close together (adjacent letters) throughout -- exercises the minimum row-spacing
# constraint for cross-channel merge opportunities
for row in 1:8
    for col in 1:12
        children(target_plate4)[row,col].stock = row *u"mg" * A4 + (9-row) * u"mg" * B4 + col * u"mg" * C4 + 200u"µl" * water4
    end
end

pc4 = pourfecto(conicals4,[target_plate4],["nimbus_four_channel"])

test_pourcast_compilation("NimbusFourChannel Compilation",pc4)
