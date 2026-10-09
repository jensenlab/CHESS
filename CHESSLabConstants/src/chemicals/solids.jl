# Static @reagent definitions for every Solid, alphabetized by lab ID. Generated once from the
# author-time cache (JLConstants_database.db) via register_reagent! -- see chemical_utils.jl. To add
# a new compound, call register_reagent!, paste the returned line in below (alphabetically), commit.

@reagent HCl "Hydrochloric Acid" Solid missing 1.05u"g/mL" 313
@reagent NaOH "Sodium Hydroxide" Solid missing 1.5u"g/mL" 14798
@reagent acetamide "Acetamide" Solid "C2H5NO" 1.159u"g/mL" 178
@reagent acid_red_1 "Acid Red 1" Solid "C18H13N3Na2O8S2" missing 19522
@reagent adenine "adenine" Solid "C5H5N5" missing 190
@reagent adenosine "adenosine" Solid "C10H13N5O4" missing 60961
@reagent adonitol "Adonitol (Ribitol)" Solid "C5H12O5" missing 6912
@reagent agar "agar" Solid "C14H24O9" missing 71571511
@reagent agmatine "Agmatine" Solid "C5H14N4" missing 199
@reagent alanine "DL-alanine" Solid "C3H7NO2" missing 602
@reagent alpha_cyclodextrin "Alpha-Cyclodextrin" Solid "C36H60O30" missing 444913
@reagent alpha_ketoglutaric_acid "Alpha Ketoglutaric Acid (2-Oxoglutaric Acid)" Solid "C5H6O5" missing 51
@reagent amitrole "amitrole (3-amino-1,2,4-triazole)" Solid "C2H4N4" 1.138u"g/mL" 1639
@reagent ammonium_chloride "Ammonium_chloride" Solid missing 1.53u"g/mL" 25517
@reagent ammonium_nitrate "Ammonium Nitrate" Solid missing 1.72u"g/mL" 22985
@reagent ammonium_sulfate "Ammonium Sulfate" Solid missing 1.78u"g/mL" 6097028
@reagent amoxicillin "amoxicillin" Solid "C16H19N3O5S" missing 33613
@reagent ampicillin "ampicllin" Solid "C16H19N3O4S" missing 6249
@reagent arabinan "Arabinan" Solid opaque missing missing
# ^ Sigma-Aldrich AABH9BD89ECE-250MG (sugar-beet arabinan). Polydisperse polysaccharide, no PubChem
# CID/fixed MW exists -- registered for identity/inventory purposes only (same pattern as agar/
# dextrin/tryptone: a real, named lab reagent with no single-molecule MW to report).
@reagent arabinose "D-Arabinose" Solid "C5H10O5" missing 66308
# ^ fixed 2026-08-13: was incorrectly CID 188324 (D-Arabinose 5-phosphate, MW 230.11), a different,
# phosphorylated compound -- corrected to plain D-Arabinose (CID 66308) while registering l_arabinose
# alongside it.
@reagent arbutin "Arbutin" Solid "C12H16O7" missing 440936
@reagent arginine "L-arginine" Solid "C6H14N4O2" missing 6322
@reagent ascorbate "L-Ascorbic Acid" Solid "C6H8O6" missing 54670067
@reagent asparagine "L-asparagine" Solid "C4H8N2O3" 1.543u"g/mL" 6267
@reagent aspartic_acid "L-aspartic acid" Solid "C4H7NO4" 1.6603u"g/mL" 5960
@reagent b_nadph "β-NADPH (triphosphopyridine nucloetide)" Solid "C21H28N7O17P3" missing 5885
@reagent beef_extract "Beef Extract" Solid opaque missing missing
@reagent beef_heart "Beef Heart" Solid opaque missing missing
@reagent benzamadine "benzamadine" Solid "C7H8N2" missing 2332
@reagent beta_methyl_d_glucoside "Methyl-beta-D-glucopyranoside Hemihydrate" Solid 203.19u"g/mol" missing 445238
# ^ Thermo/Acros AC270920250 is the hemihydrate, not anhydrous (194.18 + 18.015/2 = 203.19, hand-
# computed here). PubChem's own "hemihydrate"-titled CID (75487602, MW 212.20) is internally
# inconsistent -- its formula is actually a full monohydrate's, not a hemihydrate's -- confirmed
# against the clean 2:1 compound:water co-crystal entry (CID 2724704, MW 406.38 = 2x194.18+18.02).
# pubchemid kept as the anhydrous parent (445238), the correct compound identity, since no
# PubChem CID accurately represents the hemihydrate on its own.
@reagent bhi "Brain Heart Infusion Broth" Solid opaque missing missing
@reagent biotin "biotin" Solid "C10H16N2O3S" missing 171548
@reagent bleomycin "bleomycin" Solid opaque(1415.6u"g/mol") missing 5360373
@reagent boric_acid "Boric Acid" Solid "BH3O3" 1.435u"g/mL" 7628
@reagent sodium_butyrate "Sodium Butyrate" Solid 110.09u"g/mol" missing 5222465
@reagent calcium_chloride "calcium chloride dihydrate" Solid missing 1.85u"g/mL" 6093260
@reagent calcium_l_threonate "Calcium L-threonate" Solid "C8H14CaO10" missing 13388558
@reagent carbenicillin "carbenicillin" Solid "C17H18N2O6S" missing 20824
@reagent carnitine "D,L-Carnitine" Solid "C7H15NO3" missing 288
@reagent ceftriaxone "ceftriaxone" Solid "C18H18N8O7S3" missing 5479530
@reagent cellobiose "cellobiose (maltose)" Solid "C12H22O11" missing 294
@reagent cellulose_triacetate "Cellulose Triacetate" Solid opaque missing missing
# ^ Thermo Scientific/Acros AC177822500 (CAS 9012-09-3, repeat unit (C24H32O16)n) -- lab_id/name
# reflect the actual product on the shelf, not plain cellulose. Polymer, no PubChem CID/fixed MW;
# no Dissolution/AcidBaseSystem (same non-discrete-material treatment as arabinan/
# hydrolyzed_mucin below).
@reagent chloramphenicol "chloramphenicol" Solid "C11H12Cl2N2O5" missing 5959
@reagent chlortetracycline "chlortetracycline" Solid 515.3u"g/mol" missing 54682468
@reagent choline_chloride "Choline Chloride" Solid (Choline⁺ + Cl⁻) missing 6209
# ^ Sigma C7527 choline chloride (139.62 g/mol). The choline cation is `Choline⁺` (ions.jl, CID 305).
@reagent ciprofloxacin "ciprofloxacin" Solid "C17H18FN3O3" missing 2764
@reagent citric_acid "Citric Acid" Solid "C6H8O7" 1.54u"g/mL" 311
@reagent citruline "L-citruline" Solid "C6H13N3O3" missing 9750
@reagent cobalt_chloride "Cobalt (II) Chloride Hexahydrate" Solid missing 1.924u"g/mL" 24643
# ^ fixed 2026-08-14: was registered anhydrous (CID 3032536, real anhydrous density ~3.35 g/mL) but
# the stored density (1.924) actually matches the hexahydrate's -- corrected to the hexahydrate CID
# (24643); molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent cobalt_nitrate "Cobalt (II) Nitrate Hexahydrate" Solid missing 1.88u"g/mL" 24821
# ^ fixed 2026-08-14: was registered anhydrous (CID 25000, density 1.54 -- neither the anhydrous
# nor hexahydrate reference density) -- corrected to hexahydrate (CID 24821, density 1.88) per the
# lab's own purchase record (Sigma 230375-100G, "COBALT(II) NITRATE HEXAHYDRATE, 98%").
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent colistin "colistin" Solid "C52H98N16O13" missing 5311054
@reagent copper_chloride "Copper (II) Chloride Dihydrate" Solid missing 2.54u"g/mL" 61482
# ^ fixed 2026-08-14: was registered anhydrous (CID 24014, real anhydrous density ~3.4 g/mL) but the
# stored density (2.54) actually matches the dihydrate's -- corrected to the dihydrate CID (61482);
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent copper_sulfate "Copper (II) Sulfate Pentahydrate" Solid missing 2.29u"g/mL" 24463
# ^ fixed 2026-08-14: was registered anhydrous (CID 24462, real anhydrous density ~3.6 g/mL) but the
# stored density (2.29) actually matches the pentahydrate's -- corrected to the pentahydrate CID
# (24463); molecular_weight derives from the Dissolution (electrolytes.jl), now including 5 H2O.
@reagent cyclohexamide "cyclohexamide" Solid "C15H23NO4" missing 6197
@reagent cycloserine "cycloserine" Solid "C3H6N2O2" missing 6234
@reagent cysteine "L-Cysteine hydrochloride monohydrate" Solid missing missing 23462
@reagent cystine "L-cystine" Solid "C6H12N2O4S2" missing 67678
@reagent cytosine "cytosine" Solid "C4H5N3O" missing 597
@reagent d_alanine "D-Alanine" Solid "C3H7NO2" missing 71080
# ^ distinct from the existing alanine (DL, CID 602) and l_alanine (CID 5950) -- same formula/MW
# as its stereoisomers, but no density data on PubChem for this specific CID (not assumed to match
# l_alanine's 1.432 g/mL just because enantiomers share physical properties -- no per-CID citation).
@reagent d_arabitol "D-Arabitol" Solid "C5H12O5" missing 94154
@reagent d_galactarate "D-Galactaric Acid (Mucic Acid)" Solid "C6H10O8" missing 3037582
@reagent d_galactonate "Calcium D-Galactonate Monohydrate" Solid "C12H24CaO15" missing 129700926
# ^ eMolecules 50-222-8418 is "listed as calcium d-galactonate hydrate" -- CID 129700926's formula
# (C12H24CaO15, 448.39) is exactly the anhydrous salt (C12H22CaO14, 430.37) plus one H2O, i.e. a
# monohydrate.
@reagent d_galacturonate "D-Galacturonic Acid Monohydrate" Solid "C6H12O8" missing 44654794
# ^ Thermo AAJ6628206 is "listed as d-galacturonic acid monohydrate" -- CID 44654794 (212.15 =
# 194.14 + 18.015) is the dedicated monohydrate entry.
@reagent d_glucarate "Calcium D-Glucarate Tetrahydrate (Calcium Saccharate)" Solid "C6H16CaO12" missing 11954337
# ^ Thermo AAJ6694714 is "listed as calcium D-saccharate tetrahydrate" -- CID 11954337 (320.26 =
# 248.20 + 4x18.015) is the dedicated tetrahydrate entry.
@reagent d_gluconate "Potassium D-Gluconate" Solid "C6H11KO7" missing 16760467
@reagent d_glucosamine "D-Glucosamine Hydrochloride" Solid "C6H14ClNO5" missing 91431
@reagent d_glucuronate "D-Glucuronic Acid" Solid "C6H10O7" missing 94715
@reagent d_malic_acid "D-Malic Acid" Solid "C4H6O5" missing 92824
@reagent d_psicose "D-Psicose" Solid "C6H12O6" missing 441036
@reagent d_ribose "D-Ribose" Solid "C5H10O5" missing 10975657
@reagent d_serine "D-Serine" Solid "C3H7NO3" missing 71077
@reagent d_tagatose "D-Tagatose" Solid "C6H12O6" missing 439312
@reagent dextrin "dextrin from corn" Solid "C18H32O16" missing 62698
@reagent dihydroxyacetone "Dihydroxyacetone" Solid "C3H6O3" missing 670
@reagent doxycycline "doxycycline" Solid 480.9u"g/mol" missing 54685920
@reagent dulcitol "Dulcitol (Galactitol)" Solid "C6H14O6" missing 11850
@reagent ectoine "Ectoine" Solid "C6H10N2O2" missing 126041
@reagent edta "EDTA" Solid "C10H16N2O8" 0.86u"g/mL" 6049
@reagent erythromycin "erythromycin" Solid "C37H67NO13" missing 12560
@reagent folic_acid "folic acid" Solid "C19H19N7O6" missing 135398658
@reagent formamide "Formamide" Solid "CH3NO" 1.1334u"g/mL" 713
@reagent formic_acid "Formic Acid" Solid "CH2O2" 1.22u"g/mL" 284
@reagent fructose "D-(-)-fructose" Solid "C6H12O6" missing 5984
@reagent fusaric_acid "fusaric_acid" Solid "C10H13NO2" missing 3442
@reagent fusidic_acid "fusidic_acid" Solid "C31H48O6" missing 3000226
@reagent galactose "D-galactose" Solid "C6H12O6" missing 6036
@reagent gentamicin "gentamicin" Solid "C21H43N5O7" missing 3467
@reagent gifu_anaerobic_broth "Gifu Anaerobic Broth, Modified (GAM)" Solid opaque missing missing
@reagent glcnac "GlcNAc" Solid "C8H15NO6" missing 439174
@reagent glucose "D-glucose" Solid "C6H12O6" 1.2u"g/mL" 5793
@reagent glutamic_acid "L-glutamic_acid" Solid "C5H9NO4" 1.538u"g/mL" 33032
@reagent glutamine "L-glutamine" Solid "C5H10N2O3" 1.364u"g/mL" 5961
# ^ note 2026-08-14: the lab's actual stocklist (Reagent_StockList.xlsx) shows l-glutamine purchased
# both as this solid (Sigma G3126-100G) and as Gibco's 200mM aqueous solution (25-030-081) -- this
# reagent correctly represents the solid form; a Stock built from the Gibco bottle should be dosed
# as a solution (by volume/molarity), not by weighing this reagent. Same situation as sodium_pyruvate
# below (see its own comment).
@reagent glutathione "L-Glutathione (reduced)" Solid "C10H17N3O6S" missing 124886
@reagent glycine "glycine" Solid "C2H5NO2" 1.1607u"g/mL" 750
@reagent guanidine "guanidine" Solid "CH5N3" missing 3520
@reagent guanine "guanine hydrochloride" Solid "C5H6ClN5O" missing 135436483
@reagent guanosine "guanosine" Solid "C10H13N5O5" missing 135398635
@reagent histidine "L-histidine" Solid "C6H9N3O2" missing 6274
@reagent hs_com "2-Mercaptoethanesulfonate Sodium Salt (Coenzyme M)" Solid "C2H5NaO3S2" missing 23662354
# ^ PubChem's canonical entry for this compound is titled "Mesna" (its pharmaceutical name), CID
# 23662354, the anhydrous sodium salt -- a monohydrate exists commercially under a different CAS but
# isn't what's registered here (no catalog number on hand to confirm). No density data on PubChem.
# No AcidBaseSystem: the sulfonate is a strong acid (always ionized, same as other strong-acid
# conjugate bases here); the only thiol pKa's found (7.4, 9.2) are enzyme-active-site-bound values
# from CoM-transferase studies, not the free compound in solution, so not used here.
@reagent hydrolyzed_mucin "Mucin from porcine stomach (Type III)" Solid opaque missing missing
# ^ Sigma M1778 (CAS 84082-64-4), bound sialic acid 0.5-1.5%, partially purified powder. A
# heterogeneous glycoprotein (monomer ~640 kDa, polymeric mucin ~4000-5500 kDa) -- no PubChem
# CID/fixed MW; registered for identity/inventory purposes only, same as arabinan above.
@reagent hypoxanthine "Hypoxanthine" Solid "C5H4N4O" missing 135398638
@reagent inosine "inosine" Solid "C10H12N4O5" missing 135398641
@reagent iron_chloride "Iron Chloride (Ferric Chloride)" Solid missing 2.8u"g/mL" 24380
@reagent iron_nitrate "iron (III) nitrate" Solid missing 1.68u"g/mL" 16211566
@reagent iron_sulfate "iron (II) sulfate" Solid missing 1.895u"g/mL" 62662
@reagent isoleucine "L-isoleucine" Solid "C6H13NO2" missing 6306
@reagent kanamycin "kanamycin" Solid "C18H36N4O11" missing 6032
@reagent l_alanine "L-Alanine" Solid "C3H7NO2" 1.432u"g/mL" 5950
@reagent l_arabinose "L-Arabinose" Solid "C5H10O5" missing 439195
@reagent l_fucose "L-Fucose" Solid "C6H12O5" missing 17106
@reagent l_lyxose "L-Lyxose" Solid "C5H10O5" missing 644176
@reagent l_malic_acid "L-Malic Acid" Solid "C4H6O5" missing 222656
@reagent l_sorbose "L-Sorbose" Solid "C6H12O6" missing 439192
@reagent lactose "D-lactose" Solid "C12H22O11" missing 6134
@reagent lactulose "Lactulose" Solid "C12H22O11" missing 11333
@reagent lb "LB Broth" Solid opaque missing missing
@reagent leucine "L-leucine" Solid "C6H13NO2" 1.293u"g/mL" 6106
@reagent lincomycin "lincomycin" Solid "C18H34N2O6S" missing 3000540
@reagent lipoic_acid "lipoic_acid" Solid "C8H14O2S2" missing 6112
@reagent lysine "L-Lysine monohydrochloride" Solid missing missing 69568
@reagent magnesium_sulfate "magnesium sulfate heptahydrate" Solid missing 1.68u"g/mL" 24843
@reagent malic_acid "Malic Acid" Solid "C4H6O5" 1.601u"g/mL" 525
@reagent maltodextrin "maltodextrin" Solid opaque missing missing
@reagent maltose "Maltose" Solid "C12H22O11" missing 439186
@reagent manganese_chloride "Manganese (II) Chloride" Solid missing 2.01u"g/mL" 643989
@reagent manganese_sulfate "manganese sulfate monohydrate" Solid missing 2.95u"g/mL" 177577
@reagent mannitol "D-mannitol" Solid "C6H14O6" 1.489u"g/mL" 6251
@reagent mannose "D-mannose" Solid "C6H12O6" missing 18950
@reagent marine_broth "Marine Broth" Solid opaque missing missing
@reagent melibiose "melibiose" Solid "C12H22O11" missing 11458
@reagent methionine "L-methionine" Solid "C5H11NO2S" 1.178u"g/mL" 6137
@reagent middlebrook_7h9_broth "Middlebrook 7H9 Broth Base" Solid opaque missing missing
@reagent miltefosine "miltefosine" Solid "C21H46NO4P" missing 3599
@reagent minocycline "minocycline hydrochloride" Solid 493.9u"g/mol" missing 54685925
@reagent mrs_broth "MRS broth" Solid opaque missing missing
@reagent mops "MOPS" Solid "C7H15NO4S" missing 70807
@reagent myo_inositol "myo-inositol" Solid "C6H12O6" missing 892
@reagent n_acetylgalactosamine "N-Acetyl-D-Galactosamine" Solid "C8H15NO6" missing 35717
@reagent n_acetylneuraminate "N-Acetylneuraminic Acid" Solid "C11H19NO9" missing 439197
@reagent neomycin "neomycin" Solid "C7H14O3" 0.98u"g/mL" 8738
@reagent niacinamide "niacinamide (nicotinamide)" Solid "C6H6N2O" 1.4u"g/mL" 936
@reagent nickel_chloride "Nickel (II) Chloride)" Solid missing 3.55u"g/mL" 24385
@reagent nutrient_broth "Nutrient Broth" Solid opaque missing missing
@reagent ofloxacin "ofloxacin" Solid "C18H20FN3O4" missing 4583
@reagent ornithine "L-Ornithine" Solid "C5H12N2O2" missing 6262
@reagent oxacillin "oxacillin" Solid "C19H19N3O5S" missing 6196
@reagent oxalic_acid "Oxalic Acid" Solid "C2H2O4" 1.9u"g/mL" 971
@reagent paba "4-aminobenzoic acid" Solid "C7H7NO2" 1.37u"g/mL" 978
@reagent palatinose "Palatinose (Isomaltulose)" Solid "C12H22O11" missing 83686
@reagent pantothenate "calcium pantothenate" Solid "C18H32CaN2O10" missing 443753
@reagent paromomycin "paromomycin" Solid "C23H45N5O14" missing 165580
@reagent penicillin_g "penicillin_g" Solid "C16H18N2O4S" missing 5904
@reagent peptone "Peptone" Solid opaque missing missing
@reagent phenylalanine "L-phenylalanine" Solid "C9H11NO2" missing 6140
@reagent polymyxin_b "polymyxin_b" Solid "C56H100N16O17S" missing 5702105
@reagent potassium_aluminum_sulfate "Potassium Aluminum Sulfate Dodecahydrate" Solid missing 1.725u"g/mL" 62667
# ^ fixed 2026-08-14: was registered anhydrous (CID 24856), but the stored density (1.725) is
# PubChem's own dodecahydrate-labeled value, and potassium alum is essentially never sold anhydrous
# -- corrected to the dodecahydrate CID (62667); molecular_weight derives from the Dissolution
# (electrolytes.jl), now including 12 H2O.
@reagent potassium_chloride "Potassium Chloride" Solid missing 1.984u"g/mL" 4873
@reagent potassium_phosphate_di "potassium phosphate dibasic" Solid missing missing 24450
@reagent potassium_phosphate_mono "potassium phosphate monobasic" Solid missing 2.34u"g/mL" 516951
@reagent proline "L-proline" Solid "C5H9NO2" 1.064u"g/mL" 145742
@reagent promethazine "promethazine" Solid "C17H20N2S" missing 4927
@reagent propionic_acid "Propionic Acid" Solid "C3H6O2" 0.995u"g/mL" 1032
@reagent putrescine "Putrescine" Solid "C4H12N2" 0.877u"g/mL" 1045
@reagent pyridoxal "pyridoxal hydrochloride" Solid "C8H10ClNO3" missing 6171
@reagent pyridoxamine "pyridoxamine dihydrochloride" Solid "C8H14Cl2N2O2" missing 10664
@reagent sodium_pyruvate "Sodium Pyruvate" Solid 110.04u"g/mol" missing 23662274
@reagent raffinose "Raffinose" Solid "C18H32O16" missing 439242
@reagent resazurin "Resazurin" Solid "C12H7NO4" missing 11077
@reagent riboflavin "riboflavin (vitamin B2)" Solid "C17H20N4O6" missing 493570
@reagent ribothymidine "ribothymidine (5-methyluridine)" Solid "C10H14N2O6" missing 445408
@reagent rifampicin "rifampicin" Solid "C43H58N4O12" missing 135398735
@reagent salicin "Salacin" Solid "C13H18O7" missing 439503
@reagent serine "L-serine" Solid "C3H7NO3" 1.6u"g/mL" 5951
@reagent shikimic_acid "Shikimic Acid" Solid "C7H10O5" missing 8742
@reagent silver_nitrate "silver_nitrate" Solid missing 4.35u"g/mL" 24470
@reagent sodium_acetate_anhydrous "sodium acetate" Solid missing 1.528u"g/mL" 517045
# ^ note 2026-08-14: a purchase logged as "acetate" (catalog "S28625-500 G") was originally assumed
# to be this anhydrous salt, but S28625 isn't a real Sigma catalog number -- checked against the
# lab's actual stocklist (Reagent_StockList.xlsx), which lists the same item (same price, same
# size) under catalog S8625-500G with formula CH3COONa.3H2O, i.e. sodium_acetate_trihydrate below.
# Digit-transposition typo in the original purchase log, not a registry error -- no code change
# needed since both reagents already existed; flagged so future stock-building uses the right one.
@reagent sodium_acetate_trihydrate "sodium acetate trihydrate" Solid missing 1.528u"g/mL" 23665404
@reagent sodium_bicarbonate "sodium bicarbonate" Solid missing 2.159u"g/mL" 516892
@reagent sodium_carbonate "Sodium Carbonate" Solid missing 2.54u"g/mL" 10340
@reagent sodium_chloride "Sodium Chloride" Solid missing missing 5234
# ^ fixed 2026-08-14: stored CID was 5324 (Sulfaguanidine), a transposed-digit typo -- corrected to
# 5234 (Sodium Chloride). MW/density were already `missing`, so this doesn't change any derived
# value, only the CID metadata.
@reagent sodium_citrate_dihydrate "Sodium Citrate Dihydrate" Solid missing missing 71474
# ^ Fisherbrand S279-500. Vendor listing says "citrate buffer solution" but the product is actually
# the raw salt, Sodium Citrate Dihydrate (trisodium citrate dihydrate, CAS 6132-04-3) -- not a
# premixed buffer. molecular_weight is `missing` and derived instead from its Dissolution
# (electrolytes.jl: 3*Na+ + Citrate3- + 2*H2O), matching sodium_acetate_trihydrate's convention.
@reagent sodium_dichromate "Sodium Dichromate Dihydrate" Solid missing 2.35u"g/mL" 108005
# ^ fixed 2026-08-14: was registered anhydrous (CID 25408) -- corrected to dihydrate (CID 108005)
# per the lab's own purchase record (Sigma 398063-100G, whose catalog listing is "Sodium dichromate
# dihydrate"). Density (2.35) was already the dihydrate's value, unchanged. molecular_weight derives
# from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent sodium_molybdate "Sodium Molybdate Dihydrate" Solid missing 3.5u"g/mL" 16211258
# ^ fixed 2026-08-14: was registered anhydrous (CID 61424, density 3.78) -- corrected to dihydrate
# (CID 16211258, density 3.5) per the lab's own purchase record (catalog 243655-100G, "Sodium
# molybdate dihydrate"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent sodium_phosphate_di "sodium phosphate dibasic heptahydrate" Solid missing missing 6096963
@reagent sodium_phosphate_di_anhydrous "sodium phosphate dibasic anhydrous" Solid missing missing 24203
@reagent sodium_phosphate_mono "sodium phosphate mononbasic monohydrate" Solid missing missing 516949
@reagent sodium_selenite "Sodium Selenite" Solid missing 3.1u"g/mL" 24934
@reagent sodium_succinate_hexahydrate "Sodium Succinate Hexahydrate" Solid missing missing 3083938
@reagent sodium_tungstate "Sodium Tungstate Dihydrate" Solid missing 3.25u"g/mL" 150191
# ^ fixed 2026-08-14: was registered anhydrous (CID 26052, density 4.179) -- corrected to dihydrate
# (CID 150191, density 3.25) per the lab's own purchase record (Sigma 223336-100G, "SODIUM TUNGSTATE
# DIHYDRATE, ACS REAGENT"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent soluble_starch "Soluble Starch" Solid opaque missing missing
@reagent sorbitol "D-sorbitol" Solid "C6H14O6" 1.49u"g/mL" 5780
@reagent spectinomycin "spectinomycin" Solid "C14H24N2O7" missing 15541
@reagent spermidine "Spermidine" Solid "C7H19N3" missing 1102
@reagent streptomycin "streptomycin" Solid "C21H39N7O12" missing 19649
@reagent succinic_acid "Succinic Acid" Solid "C4H6O4" 1.572u"g/mL" 1110
@reagent sucrose "sucrose" Solid "C12H22O11" 1.59u"g/mL" 5988
@reagent sulfadiazine "sulfadiazine" Solid "C10H10N4O2S" missing 5215
@reagent sulfamethazine "sulfamethazine" Solid "C12H14N4O2S" 1.4655u"g/mL" 5327
@reagent sulfathiazole "sulfathiazole" Solid "C9H9N3O2S2" missing 5340
@reagent tartrate "sodium tartrate dihydrate" Solid missing missing 12598458
@reagent taurine "Taurine" Solid "C2H7NO3S" missing 1123
@reagent tetracycline "tetracycline_hydrochloride" Solid 480.9u"g/mol" missing 54704426
@reagent thb "Todd-Hewitt Broth" Solid opaque missing missing
@reagent thiamine "thiamine hydrochloride" Solid "C12H18Cl2N4OS" missing 6202
@reagent thiourea "Thiourea" Solid "CH4N2S" 1.405u"g/mL" 2723790
@reagent threonine "L-threonine" Solid "C4H9NO3" missing 6288
@reagent thymine "thymine" Solid "C5H6N2O2" missing 1135
@reagent tin_fluoride "Tin (II) Fluoride" Solid missing 2.79u"g/mL" 24550
@reagent tobramycin "tobramycin" Solid "C18H37N5O9" missing 36294
@reagent trehalose "D-(+)-trehalose dydrate" Solid "C12H26O13" missing 181978
@reagent triclosan "triclosan" Solid "C12H7Cl3O2" missing 5564
@reagent tryptic_soy_broth "Tryptic Soy Broth" Solid opaque missing missing
@reagent tryptone "tryptone" Solid opaque missing missing
@reagent tryptophan "L-tryptophan" Solid "C11H12N2O2" missing 6305
@reagent tryptose "Tryptose" Solid opaque missing missing
@reagent tyrosine "L-tyrosine" Solid "C9H11NO3" missing 6057
@reagent uracil "uracil" Solid "C4H4N2O2" missing 1174
@reagent uridine "uridine" Solid "C9H12N2O6" missing 6029
@reagent valine "L-valine" Solid "C5H11NO2" 1.23u"g/mL" 6287
@reagent vancomycin "vancomycin" Solid "C66H75Cl2N9O24" missing 14969
@reagent vitamin_b12 "vitamin B12" Solid "C63H88CoN14O14P" missing 165339223
@reagent vitamin_k1 "Vitamin K1 (phylloquinone)" Solid "C31H46O2" 0.964u"g/mL" 5284607
@reagent xanthine "xanthine" Solid "C5H4N4O2" missing 1188
@reagent xanthosine "xanthosine" Solid "C10H12N4O6" missing 64959
@reagent xylitol "Xylitol" Solid "C13H26O6" missing 581285
@reagent xylose "xlyose" Solid "C5H10O5" 1.525u"g/mL" 135191
@reagent yeast_extract "yeast_extract" Solid opaque missing missing
@reagent zinc_chloride "Zinc (II) Chloride" Solid missing 2.91u"g/mL" 5727
@reagent zinc_sulfate "Zinc Sulfate Heptahydrate" Solid missing 1.97u"g/mL" 62640
# ^ fixed 2026-08-14: was registered anhydrous (CID 24424, real anhydrous density ~3.8 g/mL) -- the
# stored density (1.96) actually matched the heptahydrate's, and the lab's own purchase record
# (Reagent_StockList.xlsx: Sigma Z0251-100G, "ZINC SULFATE HEPTAHYDRATE") confirms it. Corrected to
# the heptahydrate CID (62640); molecular_weight derives from the Dissolution (electrolytes.jl),
# now including 7 H2O.
