 const phosphates_25x_1L = 
    5u"g" * potassium_phosphate_di + 
    25u"g" *potassium_phosphate_mono + 
    79u"g" * sodium_phosphate_mono + 
    346.8u"g" *sodium_phosphate_di + 
    1u"L" * water 

 const magnesium_500x_250mL=
    87.5u"g" * magnesium_sulfate+
    250u"mL"* water

 const manganese_1000x_250mL = 
    1.25u"g" *manganese_sulfate+
    250u"mL" * water

 const sodium_acetate_50x_500mL = 
    112.5u"g" * sodium_acetate_trihydrate+
    500u"mL" *water

 const sodium_bicarbonate_20x_1L = 
    50u"g" *sodium_bicarbonate+
    1u"L" * water

 const calcium_chloride_1000x_50mL = 
    338u"mg" *calcium_chloride+
    50u"mL"* water


 const iron_1000x_50mL=
    50u"mg" * iron_nitrate+
    250u"mg" * iron_sulfate+
    50u"mL" * water

 const cysteine_500x_50mL = 
    16.25u"g" * cysteine+
    50u"mL"*water

 const vitamins_1000x_50mL = 
    10u"mg" * paba+
    10u"mg" * biotin + 
    40u"mg" * folic_acid + 
    50u"mg" * niacinamide + 
    125u"mg" * b_nadph + 
    100u"mg" * pantothenate + 
    50u"mg" * pyridoxal + 
    50u"mg" * pyridoxamine + 
    100u"mg" * riboflavin + 
    50u"mg" * thiamine + 
    5u"mg" * vitamin_b12 + 
    50u"mL" * water 


 const bases_100x_200mL = 
    500u"mg" * adenine+
    500u"mg" * guanine + 
    500u"mg" * uracil+
    200u"mL" *water

 const amino_acids_50x_500mL = 
    2.5u"g" * alanine+
    2.5u"g" * arginine + 
    2.5u"g" * aspartic_acid + 
    2.5u"g" * asparagine + 
    2.5u"g" * glutamic_acid + 
    2.5u"g" * glutamine + 
    2.5u"g" * glycine + 
    2.5u"g" * histidine + 
    2.5u"g" * isoleucine + 
    2.5u"g" * leucine + 
    2.5u"g" * lysine + 
    2.5u"g" * methionine + 
    2.5u"g" * phenylalanine + 
    2.5u"g" * proline + 
    2.5u"g" * serine + 
    5u"g" * threonine + 
    2.5u"g" * tryptophan + 
    2.5u"g" * tyrosine + 
    2.5u"g" * valine + 
    500u"mL" * water 


 @stock cdm_glucose_500mL (
    0.5/50*iron_1000x_50mL +
     20/1000*phosphates_25x_1L+
     1/250*magnesium_500x_250mL+
     0.5/250*manganese_1000x_250mL+
     10/500*sodium_acetate_50x_500mL+
     10/500*amino_acids_50x_500mL+
     0.5/50 * vitamins_1000x_50mL+
     5/200*bases_100x_200mL+
     0.5/50*calcium_chloride_1000x_50mL+
     1/50 * cysteine_500x_50mL+
     25/1000 * sodium_bicarbonate_20x_1L+
     5u"g" *glucose +
     426u"mL"*water)




