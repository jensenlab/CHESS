using Pourfecto, CHESSCore, Unitful
# small, single-source/single-target problem specifically to exercise the enforce_minimum_shot=true
# MIQP branch (adds binary QI variables) with a solver that supports it (SCIP) -- kept tiny so the
# MIQP solve stays fast.
A = string_to_reagent("A",Solid)
water = string_to_reagent("water",Liquid)

source = build_location(location_kinds[:Conical15],"A source")
st = Empty()
st += 1u"g" * A
st += 5u"ml" * water
deposit!(children(source)[1],st,0)

target = build_location(location_kinds[:Conical15],"A target")
children(target)[1].stock = 100u"mg" * A + 500u"µL" * water

pc = pourfecto([source],[target],["single_channel"];optimizer=SCIP.Optimizer,enforce_minimum_shot=true)

test_pourcast_compilation("Minimum Shot MIQP",pc)
