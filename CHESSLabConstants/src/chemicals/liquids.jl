# Static @reagent definitions for every Liquid, alphabetized by lab ID. Generated once from the
# author-time cache (JLConstants_database.db) via register_reagent! -- see chemical_utils.jl.

@reagent acetic_acid "Acetic Acid" Liquid "C2H4O2" 1.049u"g/mL" 176
@reagent butyric_acid "Butyric Acid" Liquid "C4H8O2" 0.958u"g/mL" 264
@reagent diacetyl "Diacetyl (2,3-Butanedione)" Liquid "C4H6O2" 0.99u"g/mL" 650
@reagent_product diacetyl "Fisher Scientific" catalog_number="B0682100ML" notes="Manufacturer: TCI America"
@reagent dmso "dimethyl sulfoxide" Liquid "C2H6OS" 1.101u"g/mL" 679
@reagent ethanol "ethanol" Liquid "C2H6O" 0.79u"g/mL" 702
@reagent ethanolamine "Ethanolamine" Liquid "C2H7NO" 1.016u"g/mL" 700
@reagent fusayama_meyer_saliva "Fusayama/Meyer Artificial Saliva" Liquid opaque missing missing
# ^ A ready-made multi-component solution. Its composition was not confirmed, so
# it is registered opaque, for identity/inventory purposes only, same as sheep_blood.
@reagent_product fusayama_meyer_saliva "Sigma-Aldrich" catalog_number="SAE0148" product_name="Fusayama/Meyer artificial saliva"
@reagent glycerol "glycerol" Liquid "C3H8O3" 1.261u"g/mL" 753
@reagent_product glycerol "Fisher Scientific" catalog_number="AAJ61059AP" product_name="Glycerol, Molecular Biology Grade" manufacturer_number="Thermo J61059AP"
@reagent hydrogen_peroxide "hydrogen peroxide" Liquid "H2O2" 1.11u"g/mL" 784
@reagent lactic_acid "Lactic Acid (88% w/w solution)" Liquid opaque(CHESSCore.formula_mass("C3H6O3")/0.88) 1.2u"g/mL" 612
# ^ real product is Sigma-Aldrich W261106, "Lactic acid, 88%, FCC" (DL-lactic acid), a liquid: an 88%
# w/w aqueous solution, remainder water. It is declared `opaque` with a purity-adjusted molar mass (the
# formula mass of C3H6O3 divided by 0.88), so volume * density / molar mass yields moles of *real* lactic
# acid per volume of product -- the only lever CHESSCore has for "moles per volume of a solution" -- and
# so `atoms` does not count the product's carbon, hydrogen, and oxygen as if it were pure acid. One
# consequence: the neutral species in lactic_acid's AcidBaseSystem chain (pKa_data.jl) carries this
# purity-adjusted mass, so it no longer differs from Lactate⁻ by exactly one proton's mass --
# cosmetically inconsistent, but doesn't affect the pH solve (moles/charges, not absolute masses, drive
# that). Revisit if CHESSCore ever gains a first-class "purity/assay" concept on Reagent.
@reagent_product lactic_acid "Sigma-Aldrich" catalog_number="W261106" product_name="Lactic acid, 88%, FCC" grade="FCC"
@reagent sheep_blood "Defibrinated Sheep Blood" Liquid opaque missing missing
@reagent_product sheep_blood "Fisher Scientific" catalog_number="R54012" product_name="Thermo Scientific™ Defibrinated Sheep Blood" manufacturer_number="Thermo R54012"
@reagent spermidine "Spermidine" Liquid "C7H19N3" 0.925u"g/mL" 1102
# ^ a liquid as supplied: the lab's stocklist labels it "(liquid)", PubChem gives a melting point below 25 C,
# and Sigma describes S0266 as a neat liquid. It is sold by mass (25 g), but a reagent's type is its phase as
# supplied, so it is dosed with the density, Sigma's literature value of 0.925 g/mL at 25 C, as 0.4 g is 0.432 mL.
@reagent_product spermidine "Sigma-Aldrich" catalog_number="S0266" product_name="SPERMIDINE, BIOREAGENT, FOR MOLECULAR B" notes="Product name is cut off in the stocklist"
@reagent water "water" Liquid "H2O" 1.0u"g/mL" 962
