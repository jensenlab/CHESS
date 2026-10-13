# Static @reagent definitions for every Solid, alphabetized by lab ID. Generated once from the
# author-time cache (JLConstants_database.db) via register_reagent! -- see chemical_utils.jl. To add
# a new compound, call register_reagent!, paste the returned line in below (alphabetically), commit.

@reagent HCl "Hydrochloric Acid" Solid (CHESSCore.H⁺+Cl⁻) 1.05u"g/mL" missing
@reagent NaOH "Sodium Hydroxide" Solid (Na⁺+CHESSCore.OH⁻) 1.5u"g/mL" missing
@reagent acetamide "Acetamide" Solid "C2H5NO" 1.159u"g/mL" 178
@reagent acid_red_1 "Acid Red 1" Solid "C18H13N3Na2O8S2" missing 19522
@reagent adenine "adenine" Solid "C5H5N5" missing 190
@reagent adenosine "adenosine" Solid "C10H13N5O4" missing 60961
@reagent adonitol "Adonitol (Ribitol)" Solid "C5H12O5" missing 6912
@reagent agar "agar" Solid "C14H24O9" missing 71571511
@reagent agmatine "Agmatine" Solid "C5H14N4" missing 199
@reagent alanine "DL-alanine" Solid "C3H7NO2" missing 602
@reagent alpha_amylase "alpha-Amylase from porcine pancreas (Type VI-B)" Solid opaque missing missing
# ^ Sold by enzyme activity (1 MU pack), not by mass. An enzyme preparation, so registered
# opaque with no molar mass, for identity/inventory purposes only, same as the other undefined biological
# materials here.
@reagent_product alpha_amylase "Sigma-Aldrich" catalog_number="A3176" product_name="alpha-Amylase from porcine pancreas Type VI-B"
@reagent alpha_cyclodextrin "Alpha-Cyclodextrin" Solid "C36H60O30" missing 444913
@reagent alpha_ketoglutaric_acid "Alpha Ketoglutaric Acid (2-Oxoglutaric Acid)" Solid "C5H6O5" missing 51
@reagent amitrole "amitrole (3-amino-1,2,4-triazole)" Solid "C2H4N4" 1.138u"g/mL" 1639
@reagent ammonium_chloride "Ammonium_chloride" Solid (NH4⁺+Cl⁻) 1.53u"g/mL" missing
@reagent ammonium_nitrate "Ammonium Nitrate" Solid (NH4⁺+NO3⁻) 1.72u"g/mL" missing
@reagent ammonium_sulfate "Ammonium Sulfate" Solid (2*NH4⁺+SO4²⁻) 1.78u"g/mL" missing
@reagent amoxicillin "amoxicillin" Solid "C16H19N3O5S" missing 33613
@reagent ampicillin "ampicillin" Solid "C16H19N3O4S" missing 6249
@reagent arabinan "Arabinan" Solid opaque missing missing
# ^ Sigma-Aldrich AABH9BD89ECE-250MG (sugar-beet arabinan). Polydisperse polysaccharide, no PubChem
# CID/fixed MW exists -- registered for identity/inventory purposes only (same pattern as agar/
# dextrin/tryptone: a real, named lab reagent with no single-molecule MW to report).
@reagent_product arabinan "Sigma-Aldrich" catalog_number="AABH9BD89ECE" product_name="Arabinan from sugar beet"
@reagent arabinose "D-Arabinose" Solid "C5H10O5" missing 66308
# ^ fixed 2026-08-13: was incorrectly CID 188324 (D-Arabinose 5-phosphate, MW 230.11), a different,
# phosphorylated compound -- corrected to plain D-Arabinose (CID 66308) while registering l_arabinose
# alongside it.
@reagent arbutin "Arbutin" Solid "C12H16O7" missing 440936
@reagent arginine "L-arginine" Solid "C6H14N4O2" missing 6322
@reagent ascorbate "L-Ascorbic Acid" Solid "C6H8O6" missing 54670067
@reagent asparagine "L-asparagine" Solid "C4H8N2O3" 1.543u"g/mL" 6267
@reagent aspartic_acid "L-aspartic acid" Solid "C4H7NO4" 1.6603u"g/mL" 5960
@reagent b_nadp "β-NADP (β-nicotinamide adenine dinucleotide phosphate)" Solid "C21H28N7O17P3" missing 5885
# ^ corrected 2026-10-13: this was registered as b_nadph, NADPH, but it is NADP, the oxidized form. The
# lab's received list gives the vendor product "B-NICOTINAMIDE ADENINE DINUCLEOTIDE PHOS" (cut off by the
# order system) with formula C21H28N7O17P3, and CID 5885 is NADP. The ordering sheet planned catalog
# COMH042346F4, noted "tetra sodium hydrate"; the order and the received list show N5755. The lab calls it
# CoenzymeII (b-nadph).
@reagent_product b_nadp "Sigma-Aldrich" catalog_number="N5755" product_name="β-Nicotinamide adenine dinucleotide phosphate" notes="Manufactured by CombiBlocks. The product name is cut off in the order record."
@reagent beef_extract "Beef Extract" Solid opaque missing missing
@reagent beef_heart "Beef Heart" Solid opaque missing missing
@reagent benzamadine "benzamidine" Solid "C7H8N2" missing 2332
@species MethylBetaDGlucoside "Methyl-beta-D-glucopyranoside" 0 "C7H14O6" 445238
@reagent beta_methyl_d_glucoside "Methyl-beta-D-glucopyranoside Hemihydrate" Solid (MethylBetaDGlucoside + 0.5*H2O) missing missing
# ^ Thermo/Acros AC270920250 is the hemihydrate, not anhydrous: one mole of the glucoside with half a mole
# of water (194.18 + 18.015/2 = 203.19). PubChem's own "hemihydrate"-titled CID (75487602, MW 212.20) is
# internally inconsistent -- its formula is actually a full monohydrate's, not a hemihydrate's -- confirmed
# against the clean 2:1 compound:water co-crystal entry (CID 2724704, MW 406.38 = 2x194.18+18.02).
# The glucoside species carries the anhydrous parent's CID (445238); no PubChem CID accurately represents
# the hemihydrate on its own, and the reagent has none.
@reagent_product beta_methyl_d_glucoside "Fisher Scientific" catalog_number="AC270920250" product_name="Methyl-beta-D-glucopyranoside hemihydrate" notes="Thermo Scientific (Acros Organics)"
@reagent bhi "Brain Heart Infusion Broth" Solid opaque missing missing
@reagent biotin "biotin" Solid "C10H16N2O3S" missing 171548
@reagent bleomycin "bleomycin" Solid opaque(1415.6u"g/mol") missing 5360373
@reagent boric_acid "Boric Acid" Solid "BH3O3" 1.435u"g/mL" 7628
@reagent sodium_butyrate "Sodium Butyrate" Solid 110.09u"g/mol" missing missing
@reagent_product sodium_butyrate "Sigma-Aldrich" catalog_number="303410" product_name="Butyric acid, sodium salt" grade="98%"
@reagent calcium_chloride "calcium chloride dihydrate" Solid (Ca²⁺+2*Cl⁻+2*H2O) 1.85u"g/mL" missing  # dihydrate
@reagent calcium_l_threonate "Calcium L-threonate" Solid "C8H14CaO10" missing 13388558
@reagent carbenicillin "carbenicillin" Solid "C17H18N2O6S" missing 20824
@reagent carnitine "D,L-Carnitine" Solid "C7H15NO3" missing 288
@reagent ceftriaxone "ceftriaxone" Solid "C18H18N8O7S3" missing 5479530
@reagent cellobiose "cellobiose" Solid "C12H22O11" missing 294
@reagent cellulose_triacetate "Cellulose Triacetate" Solid opaque missing missing
# ^ Thermo Scientific/Acros AC177822500 (CAS 9012-09-3, repeat unit (C24H32O16)n) -- lab_id/name
# reflect the actual product on the shelf, not plain cellulose. Polymer, no PubChem CID/fixed MW;
# no Dissolution/AcidBaseSystem (same non-discrete-material treatment as arabinan/
# hydrolyzed_mucin below).
@reagent_product cellulose_triacetate "Thermo Scientific" catalog_number="AC177822500" notes="Acros Organics, CAS 9012-09-3"
@reagent chloramphenicol "chloramphenicol" Solid "C11H12Cl2N2O5" missing 5959
@reagent chlortetracycline "chlortetracycline" Solid 515.3u"g/mol" missing missing
@reagent choline_chloride "Choline Chloride" Solid (Choline⁺ + Cl⁻) missing missing
# ^ Sigma C7527 choline chloride (139.62 g/mol). The choline cation is `Choline⁺` (ions.jl, CID 305).
@reagent_product choline_chloride "Sigma-Aldrich" catalog_number="C7527" product_name="Choline chloride, suitable for cell culture" grade=">98%"
@reagent ciprofloxacin "ciprofloxacin" Solid "C17H18FN3O3" missing 2764
@reagent citric_acid "Citric Acid" Solid "C6H8O7" 1.54u"g/mL" 311
@reagent citruline "L-citruline" Solid "C6H13N3O3" missing 9750
@reagent cobalt_chloride "Cobalt (II) Chloride Hexahydrate" Solid (Co²⁺+2*Cl⁻+6*H2O) 1.924u"g/mL" missing  # hexahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 3032536, real anhydrous density ~3.35 g/mL) but
# the stored density (1.924) actually matches the hexahydrate's -- corrected to the hexahydrate CID
# (24643); molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent cobalt_nitrate "Cobalt (II) Nitrate Hexahydrate" Solid (Co²⁺+2*NO3⁻+6*H2O) 1.88u"g/mL" missing  # hexahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 25000, density 1.54 -- neither the anhydrous
# nor hexahydrate reference density) -- corrected to hexahydrate (CID 24821, density 1.88) per the
# lab's own purchase record (Sigma 230375-100G, "COBALT(II) NITRATE HEXAHYDRATE, 98%").
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 6 H2O.
@reagent_product cobalt_nitrate "Sigma-Aldrich" catalog_number="230375" product_name="Cobalt(II) nitrate hexahydrate" grade="98%"
@reagent colistin "colistin" Solid "C52H98N16O13" missing 5311054
@reagent copper_chloride "Copper (II) Chloride Dihydrate" Solid (Cu²⁺+2*Cl⁻+2*H2O) 2.54u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24014, real anhydrous density ~3.4 g/mL) but the
# stored density (2.54) actually matches the dihydrate's -- corrected to the dihydrate CID (61482);
# molecular_weight derives from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent copper_sulfate "Copper (II) Sulfate Pentahydrate" Solid (Cu²⁺+SO4²⁻+5*H2O) 2.29u"g/mL" missing  # pentahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24462, real anhydrous density ~3.6 g/mL) but the
# stored density (2.29) actually matches the pentahydrate's -- corrected to the pentahydrate CID
# (24463); molecular_weight derives from the Dissolution (electrolytes.jl), now including 5 H2O.
@reagent cyclohexamide "cycloheximide" Solid "C15H23NO4" missing 6197
@reagent cycloserine "cycloserine" Solid "C3H6N2O2" missing 6234
@reagent cysteine "L-Cysteine hydrochloride monohydrate" Solid missing missing missing
@reagent_product cysteine "Thermo Fisher Scientific" catalog_number="BP376" product_name="L-Cysteine hydrochloride monohydrate"
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
@reagent doxycycline "doxycycline" Solid 480.9u"g/mol" missing missing
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
@reagent_product glutamine "Sigma-Aldrich" catalog_number="G3126" product_name="L-Glutamine, ReagentPlus" grade="≥99%"
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
@reagent_product hydrolyzed_mucin "Sigma-Aldrich" catalog_number="M1778" notes="CAS 84082-64-4"
@reagent hypoxanthine "Hypoxanthine" Solid "C5H4N4O" missing 135398638
@reagent inosine "inosine" Solid "C10H12N4O5" missing 135398641
@reagent iron_chloride "Iron Chloride (Ferric Chloride)" Solid (Fe³⁺+3*Cl⁻) 2.8u"g/mL" missing
# ^ checked 2026-08-14: not in the lab stocklist, but its stored density matches the anhydrous reference value
# cleanly, unlike the hydrates fixed in this file -- confirmed anhydrous.
@reagent iron_nitrate "iron (III) nitrate nonahydrate" Solid (Fe³⁺+3*NO3⁻+9*H2O) 1.68u"g/mL" missing  # nonahydrate
@reagent iron_sulfate "iron (II) sulfate heptahydrate" Solid (Fe²⁺+SO4²⁻+7*H2O) 1.895u"g/mL" missing  # heptahydrate
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
@reagent lysine "L-Lysine monohydrochloride" Solid missing missing missing
@reagent_product lysine "Sigma-Aldrich" catalog_number="L5626" product_name="L-Lysine monohydrochloride" grade=">98%"
@reagent magnesium_sulfate "magnesium sulfate heptahydrate" Solid (Mg²⁺+SO4²⁻+7*H2O) 1.68u"g/mL" missing  # heptahydrate
@reagent malic_acid "Malic Acid" Solid "C4H6O5" 1.601u"g/mL" 525
@reagent maltodextrin "maltodextrin" Solid opaque missing missing
@reagent maltose "Maltose" Solid "C12H22O11" missing 439186
@reagent manganese_chloride "Manganese (II) Chloride Tetrahydrate" Solid (Mn²⁺+2*Cl⁻+4*H2O) 2.01u"g/mL" missing  # tetrahydrate
@reagent manganese_sulfate "manganese sulfate monohydrate" Solid (Mn²⁺+SO4²⁻+H2O) 2.95u"g/mL" missing  # monohydrate
@reagent mannitol "D-mannitol" Solid "C6H14O6" 1.489u"g/mL" 6251
@reagent mannose "D-mannose" Solid "C6H12O6" missing 18950
@reagent marine_broth "Marine Broth" Solid opaque missing missing
@reagent melibiose "melibiose" Solid "C12H22O11" missing 11458
@reagent methionine "L-methionine" Solid "C5H11NO2S" 1.178u"g/mL" 6137
@reagent middlebrook_7h9_broth "Middlebrook 7H9 Broth Base" Solid opaque missing missing
@reagent miltefosine "miltefosine" Solid "C21H46NO4P" missing 3599
@reagent minocycline "minocycline hydrochloride" Solid 493.9u"g/mol" missing missing
@reagent mrs_broth "MRS broth" Solid opaque missing missing
@reagent mops "MOPS" Solid "C7H15NO4S" missing 70807
@reagent mucin_type_ii "Mucin from porcine stomach (Type II)" Solid opaque missing missing
# ^ Partially purified porcine gastric mucin; a different product from hydrolyzed_mucin.
# Heterogeneous glycoprotein with no PubChem CID/fixed MW; registered for
# identity/inventory purposes only, same as hydrolyzed_mucin.
@reagent_product mucin_type_ii "Sigma-Aldrich" catalog_number="M2378" product_name="Mucin from porcine stomach Type II"
@reagent myo_inositol "myo-inositol" Solid "C6H12O6" missing 892
@reagent n_acetylgalactosamine "N-Acetyl-D-Galactosamine" Solid "C8H15NO6" missing 35717
@reagent n_acetylneuraminate "N-Acetylneuraminic Acid" Solid "C11H19NO9" missing 439197
@reagent neomycin "neomycin" Solid "C23H46N6O13" missing 8378
# ^ fixed 2026-10-12: was CID 8738 (butyl lactate, C7H14O3), a transposed-digit typo, with butyl lactate's
# density (0.98) -- corrected to neomycin (CID 8378). The formula is the free base. The salt form of the
# product bought was not checked, so a sulfate would need a Dissolution.
@reagent niacinamide "niacinamide (nicotinamide)" Solid "C6H6N2O" 1.4u"g/mL" 936
@reagent nickel_chloride "Nickel (II) Chloride" Solid (Ni²⁺+2*Cl⁻) 3.55u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Reagent_StockList.xlsx): Sigma N6136-100G "anhydrous".
@reagent_product nickel_chloride "Sigma-Aldrich" catalog_number="N6136" product_name="Nickel chloride, cell culture tested"
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
@reagent potassium_aluminum_sulfate "Potassium Aluminum Sulfate Dodecahydrate" Solid (K⁺+Al³⁺+2*SO4²⁻+12*H2O) 1.725u"g/mL" missing  # dodecahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24856), but the stored density (1.725) is
# PubChem's own dodecahydrate-labeled value, and potassium alum is essentially never sold anhydrous
# -- corrected to the dodecahydrate CID (62667); molecular_weight derives from the Dissolution
# (electrolytes.jl), now including 12 H2O.
@reagent potassium_chloride "Potassium Chloride" Solid (K⁺+Cl⁻) 1.984u"g/mL" missing
@reagent potassium_phosphate_di "potassium phosphate dibasic" Solid (2*K⁺+HPO4²⁻) missing missing
@reagent potassium_phosphate_mono "potassium phosphate monobasic" Solid (K⁺+H2PO4⁻) 2.34u"g/mL" missing
@reagent proline "L-proline" Solid "C5H9NO2" 1.064u"g/mL" 145742
@reagent promethazine "promethazine" Solid "C17H20N2S" missing 4927
@reagent propionic_acid "Propionic Acid" Solid "C3H6O2" 0.995u"g/mL" 1032
@reagent putrescine "Putrescine" Solid "C4H12N2" 0.877u"g/mL" 1045
@reagent pyridoxal "pyridoxal hydrochloride" Solid "C8H10ClNO3" missing 6171
@reagent pyridoxamine "pyridoxamine dihydrochloride" Solid "C8H14Cl2N2O2" missing 10664
@reagent sodium_pyruvate "Sodium Pyruvate" Solid 110.04u"g/mol" missing missing
@reagent_product sodium_pyruvate "Sigma-Aldrich" catalog_number="P5280" product_name="Pyruvic acid sodium, cell culture tested"
@reagent raffinose "Raffinose" Solid "C18H32O16" missing 439242
@reagent resazurin "Resazurin" Solid "C12H7NO4" missing 11077
@reagent riboflavin "riboflavin (vitamin B2)" Solid "C17H20N4O6" missing 493570
@reagent ribothymidine "ribothymidine (5-methyluridine)" Solid "C10H14N2O6" missing 445408
@reagent rifampicin "rifampicin" Solid "C43H58N4O12" missing 135398735
@reagent salicin "Salicin" Solid "C13H18O7" missing 439503
@reagent serine "L-serine" Solid "C3H7NO3" 1.6u"g/mL" 5951
@reagent shikimic_acid "Shikimic Acid" Solid "C7H10O5" missing 8742
@reagent silver_nitrate "silver_nitrate" Solid (Ag⁺+NO3⁻) 4.35u"g/mL" missing
@reagent sodium_acetate_anhydrous "sodium acetate" Solid (Na⁺+OAc⁻) 1.528u"g/mL" missing
# ^ note 2026-08-14: a purchase logged as "acetate" (catalog "S28625-500 G") was originally assumed
# to be this anhydrous salt, but S28625 isn't a real Sigma catalog number -- checked against the
# lab's actual stocklist (Reagent_StockList.xlsx), which lists the same item (same price, same
# size) under catalog S8625-500G with formula CH3COONa.3H2O, i.e. sodium_acetate_trihydrate below.
# Digit-transposition typo in the original purchase log, not a registry error -- no code change
# needed since both reagents already existed; flagged so future stock-building uses the right one.
@reagent sodium_acetate_trihydrate "sodium acetate trihydrate" Solid (Na⁺+OAc⁻+3*H2O) 1.528u"g/mL" missing
@reagent sodium_bicarbonate "sodium bicarbonate" Solid (Na⁺+HCO3⁻) 2.159u"g/mL" missing
@reagent sodium_carbonate "Sodium Carbonate" Solid (2*Na⁺+CO3²⁻) 2.54u"g/mL" missing
@reagent sodium_chloride "Sodium Chloride" Solid (Na⁺+Cl⁻) missing missing
# ^ fixed 2026-08-14: stored CID was 5324 (Sulfaguanidine), a transposed-digit typo -- corrected to
# 5234 (Sodium Chloride). MW/density were already `missing`, so this doesn't change any derived
# value, only the CID metadata.
@reagent sodium_citrate_dihydrate "Sodium Citrate Dihydrate" Solid missing missing missing
# ^ Fisherbrand S279-500. Vendor listing says "citrate buffer solution" but the product is actually
# the raw salt, Sodium Citrate Dihydrate (trisodium citrate dihydrate, CAS 6132-04-3) -- not a
# premixed buffer. molecular_weight is `missing` and derived instead from its Dissolution
# (electrolytes.jl: 3*Na+ + Citrate3- + 2*H2O), matching sodium_acetate_trihydrate's convention.
@reagent_product sodium_citrate_dihydrate "Fisher Scientific" catalog_number="S279-500" product_name="Sodium citrate dihydrate" notes="Listed by the vendor as a citrate buffer solution; the product is the salt"
@reagent sodium_dichromate "Sodium Dichromate Dihydrate" Solid (2*Na⁺+Cr2O7²⁻+2*H2O) 2.35u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 25408) -- corrected to dihydrate (CID 108005)
# per the lab's own purchase record (Sigma 398063-100G, whose catalog listing is "Sodium dichromate
# dihydrate"). Density (2.35) was already the dihydrate's value, unchanged. molecular_weight derives
# from the Dissolution (electrolytes.jl), now including 2 H2O.
@reagent_product sodium_dichromate "Sigma-Aldrich" catalog_number="398063" product_name="Sodium dichromate dihydrate"
@reagent sodium_molybdate "Sodium Molybdate Dihydrate" Solid (2*Na⁺+MoO4²⁻+2*H2O) 3.5u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 61424, density 3.78) -- corrected to dihydrate
# (CID 16211258, density 3.5) per the lab's own purchase record (catalog 243655-100G, "Sodium
# molybdate dihydrate"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent_product sodium_molybdate "Sigma-Aldrich" catalog_number="243655" product_name="Sodium molybdate dihydrate" grade="98+%"
@reagent sodium_phosphate_di "sodium phosphate dibasic heptahydrate" Solid (2*Na⁺+HPO4²⁻+7*H2O) missing missing  # heptahydrate
@reagent sodium_phosphate_di_anhydrous "sodium phosphate dibasic anhydrous" Solid (2*Na⁺+HPO4²⁻) missing missing  # anhydrous (e.g. Sigma S9763)
@reagent_product sodium_phosphate_di_anhydrous "Sigma-Aldrich" catalog_number="S9763" product_name="Sodium phosphate dibasic" grade="ACS reagent"
@reagent sodium_phosphate_mono "sodium phosphate monobasic monohydrate" Solid (Na⁺+H2PO4⁻+H2O) missing missing  # monohydrate
@reagent sodium_selenite "Sodium Selenite" Solid (2*Na⁺+SeO3²⁻) 3.1u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Reagent_StockList.xlsx): Sigma 71950-100G "ANHYDROUS".
@reagent_product sodium_selenite "Sigma-Aldrich" catalog_number="71950" product_name="Sodium selenite, anhydrous" grade="≥90.0%"
@reagent sodium_succinate_hexahydrate "Sodium Succinate Hexahydrate" Solid (2*Na⁺+C4H4O4²⁻+6*H2O) missing missing
@reagent sodium_tungstate "Sodium Tungstate Dihydrate" Solid (2*Na⁺+WO4²⁻+2*H2O) 3.25u"g/mL" missing  # dihydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 26052, density 4.179) -- corrected to dihydrate
# (CID 150191, density 3.25) per the lab's own purchase record (Sigma 223336-100G, "SODIUM TUNGSTATE
# DIHYDRATE, ACS REAGENT"). molecular_weight derives from the Dissolution (electrolytes.jl), now
# including 2 H2O.
@reagent_product sodium_tungstate "Sigma-Aldrich" catalog_number="223336" product_name="Sodium tungstate dihydrate" grade="ACS reagent"
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
@reagent tartrate "sodium tartrate dihydrate" Solid missing missing missing
@reagent taurine "Taurine" Solid "C2H7NO3S" missing 1123
@reagent tetracycline "tetracycline_hydrochloride" Solid 480.9u"g/mol" missing missing
@reagent thb "Todd-Hewitt Broth" Solid opaque missing missing
@reagent thiamine "thiamine hydrochloride" Solid "C12H18Cl2N4OS" missing 6202
@reagent thiourea "Thiourea" Solid "CH4N2S" 1.405u"g/mL" 2723790
@reagent_product thiourea "Sigma-Aldrich" catalog_number="T7875" product_name="Thiourea, ReagentPlus" grade="≥99.0%"
@reagent threonine "L-threonine" Solid "C4H9NO3" missing 6288
@reagent thymine "thymine" Solid "C5H6N2O2" missing 1135
@reagent tin_fluoride "Tin (II) Fluoride" Solid (Sn²⁺+2*F⁻) 2.79u"g/mL" missing
@reagent tobramycin "tobramycin" Solid "C18H37N5O9" missing 36294
@reagent trehalose "D-(+)-trehalose dihydrate" Solid "C12H26O13" missing 181978
@reagent triclosan "triclosan" Solid "C12H7Cl3O2" missing 5564
@reagent tryptic_soy_broth "Tryptic Soy Broth" Solid opaque missing missing
@reagent tryptone "tryptone" Solid opaque missing missing
@reagent tryptophan "L-tryptophan" Solid "C11H12N2O2" missing 6305
@reagent tryptose "Tryptose" Solid opaque missing missing
@reagent tyrosine "L-tyrosine" Solid "C9H11NO3" missing 6057
@reagent uracil "uracil" Solid "C4H4N2O2" missing 1174
@reagent urea "Urea" Solid "CH4N2O" 1.34u"g/mL" 1176
# ^ Anhydrous neutral urea. Density is PubChem's. No AcidBaseSystem: urea is
# a very weak base, conjugate acid pKa 0.10 at 21 °C (Perrin, Dissociation Constants of Organic Bases
# in Aqueous Solution, IUPAC Chem. Data Ser., 1965, via PubChem CID 1176), so it is not protonated in
# the working pH range.
@reagent_product urea "Sigma-Aldrich" catalog_number="U5128" product_name="Urea ACS reagent" grade="ACS reagent"
@reagent uridine "uridine" Solid "C9H12N2O6" missing 6029
@reagent valine "L-valine" Solid "C5H11NO2" 1.23u"g/mL" 6287
@reagent vancomycin "vancomycin" Solid "C66H75Cl2N9O24" missing 14969
@reagent vitamin_b12 "vitamin B12" Solid "C63H88CoN14O14P" missing 165339223
@reagent vitamin_k1 "Vitamin K1 (phylloquinone)" Solid "C31H46O2" 0.964u"g/mL" 5284607
@reagent xanthine "xanthine" Solid "C5H4N4O2" missing 1188
@reagent xanthosine "xanthosine" Solid "C10H12N4O6" missing 64959
@reagent xylitol "Xylitol" Solid "C5H12O5" missing 6912
# ^ fixed 2026-10-12: was CID 581285 ("xylitol, 1-O-octanoyl-", C13H26O6), a different compound --
# corrected to xylitol. CID 6912 is PubChem's pentitol entry without stereochemistry, which adonitol
# (ribitol) shares; the two are isomers and differ only by name here.
@reagent xylose "D-xylose" Solid "C5H10O5" 1.525u"g/mL" 135191
@reagent yeast_extract "yeast_extract" Solid opaque missing missing
@reagent zinc_chloride "Zinc (II) Chloride" Solid (Zn²⁺+2*Cl⁻) 2.91u"g/mL" missing
# ^ checked 2026-08-14 against the lab stocklist (Sigma Z0152-100G, plain "ZINC CHLORIDE CELL CULTURE", no
# hydrate noted): confirmed anhydrous, unlike zinc_sulfate below.
@reagent_product zinc_chloride "Sigma-Aldrich" catalog_number="Z0152" product_name="Zinc chloride, cell culture"
@reagent zinc_sulfate "Zinc Sulfate Heptahydrate" Solid (Zn²⁺+SO4²⁻+7*H2O) 1.97u"g/mL" missing  # heptahydrate
# ^ fixed 2026-08-14: was registered anhydrous (CID 24424, real anhydrous density ~3.8 g/mL) -- the
# stored density (1.96) actually matched the heptahydrate's, and the lab's own purchase record
# (Reagent_StockList.xlsx: Sigma Z0251-100G, "ZINC SULFATE HEPTAHYDRATE") confirms it. Corrected to
# the heptahydrate CID (62640); molecular_weight derives from the Dissolution (electrolytes.jl),
# now including 7 H2O.
@reagent_product zinc_sulfate "Sigma-Aldrich" catalog_number="Z0251" product_name="Zinc sulfate heptahydrate, cell culture"
