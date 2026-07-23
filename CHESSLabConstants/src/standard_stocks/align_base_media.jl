
# THY (ATCC 2716)
@stock atcc_thy_1000mL (
1000u"mL"*water +
30u"g"*thb +
20u"g"*yeast_extract)

@stock atcc_thy_agar_1000mL (atcc_thy_1000mL + 15u"g" *agar)




# LB (ATCC 1364 no ampicillin)
@stock lb_1000mL (
1000u"mL" * water +
25u"g" * lb)

@stock lb_agar_1000mL (lb_1000mL + 15u"g" * agar)





# Modified Reinforced Clostridial
@stock modified_reinforced_clostridial_1000mL (
10u"g" * tryptose +
10u"g" * beef_extract +
3u"g" * yeast_extract +
5u"g" * glucose +
5u"g" * sodium_chloride +
1u"g" * soluble_starch +
0.5u"g" * cysteine +
3u"g" * sodium_acetate_anhydrous +
0.00001u"g" * resazurin +
1000u"mL" * water)

@stock modified_reinforced_clostridial__agar_1000mL (modified_reinforced_clostridial_1000mL + 15u"g"* agar)



# Gifu Anaerobic Broth, Modified (GAM)
@stock gifu_anaerobic_broth_1000mL (
41.7u"g" * gifu_anaerobic_broth +
1000u"mL" * water)

@stock gifu_anaerobic_agar_1000mL (gifu_anaerobic_broth_1000mL + 15u"g" * agar)



# Tryptic Soy Broth (ATCC 18)
@stock tryptic_soy_broth_1000mL (
30u"g" * tryptic_soy_broth +
1000u"mL" * water)

@stock tryptic_soy_agar_1000mL (tryptic_soy_broth_1000mL + 15u"g" *agar)

# Brain Heart Infusion Broth (ATCC 44)
@stock brain_heart_infusion_broth_1000mL (
37u"g" * bhi +
1000u"mL" * water)

@stock brain_heart_infusion_agar_1000mL (brain_heart_infusion_broth_1000mL + 15u"g" * agar)

# M9 Minimal Medium (ATCC 2511) 
m9_salts = 
12.8u"g" * sodium_phosphate_di +
3u"g" * potassium_phosphate_di + 
0.5u"g" * sodium_chloride + 
1u"g" * ammonium_chloride + 
478u"mL" * water 


m9_glucose = 
20u"g" * glucose + 
100u"mL" * water 

m9_magnesium_sulfate = 
1.204u"g" * magnesium_sulfate + 
10u"mL" * water 

m9_calcium_chloride = 
1.110u"g" * calcium_chloride + 
10u"mL" * water 

m9_thiamine = 
0.05u"g" * thiamine + 
10u"mL" * water
m9_supplement = 
(20/100) * m9_glucose + 
(2/10) * m9_magnesium_sulfate + 
(0.1/10) * m9_calcium_chloride + 
(0.1/10) * m9_thiamine 


@stock m9_broth_1000mL (m9_salts + m9_supplement + 500u"mL"* water)
@stock m9_agar_1000mL (m9_broth_1000mL + 15u"g" * agar)

# Marine Medium (ATCC 0002)

@stock marine_broth_1000mL (
37.4u"g" * marine_broth +
1000u"mL" * water)

@stock marine_agar_1000mL (marine_broth_1000mL + 15u"g" * agar)

# Tryptic Soy Medium with Sheep Blood

@stock tryptic_soy_sheep_blood_1000mL (
30u"g" * tryptic_soy_broth +
950u"mL" * water +
50u"mL" * sheep_blood)

@stock tryptic_soy_sheep_blood_agar_1000mL (tryptic_soy_sheep_blood_1000mL + 15u"g" * agar)


# Nurtient Broth (ATCC 3)

@stock nutrient_broth_1000mL (
8u"g" * nutrient_broth +
1000u"mL"* water)

@stock nutrient_agar_1000mL (nutrient_broth_1000mL + 15u"g" * agar)


# MRS Broth (ATCC 416)
@stock mrs_broth_1000mL (
55u"g" * mrs_broth +
1000u"mL" * water)

@stock mrs_agar_1000mL (mrs_broth_1000mL + 15u"g" * agar)

